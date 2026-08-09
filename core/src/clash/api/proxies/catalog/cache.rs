use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;

use flutter_rust_bridge::frb;

use crate::clash::api::MihomoTarget;

use super::{ProxyMemberEntry, ProxyMemberSection, ProxyMemberSort};

mod sort;

use sort::sort_members;

#[derive(Clone)]
#[frb(ignore)]
pub(super) struct CachedNode {
    pub(super) proxy_type: String,
    pub(super) delay: i32,
    pub(super) provider: Option<String>,
}

#[frb(ignore)]
pub(super) struct CachedGroup {
    pub(super) members: Vec<usize>,
    ordered_members: Option<(ProxyMemberSort, bool, Vec<usize>)>,
}

#[frb(ignore)]
pub(super) struct CachedCatalog {
    pub(super) names: Vec<String>,
    pub(super) lower_names: Option<Vec<String>>,
    pub(super) nodes: Vec<Option<CachedNode>>,
    pub(super) groups: HashMap<String, CachedGroup>,
    pub(super) direct_details: HashMap<String, String>,
    pub(super) provider_details: Arc<HashMap<String, String>>,
    pub(super) filter: String,
    pub(super) provider_nodes_checked_at: Option<Instant>,
}

impl CachedCatalog {
    fn ensure_lower_names(&mut self) {
        if self.lower_names.is_none() {
            self.lower_names = Some(self.names.iter().map(|name| name.to_lowercase()).collect());
        }
    }
}

impl CachedGroup {
    pub(super) fn new(members: Vec<usize>) -> Self {
        Self {
            members,
            ordered_members: None,
        }
    }

    fn member_ids(
        &mut self,
        sort: ProxyMemberSort,
        group_by_provider: bool,
        lower_names: &[String],
        nodes: &[Option<CachedNode>],
    ) -> &[usize] {
        let stale =
            self.ordered_members
                .as_ref()
                .is_none_or(|(cached_sort, cached_grouping, _)| {
                    *cached_sort != sort || *cached_grouping != group_by_provider
                });
        if stale {
            let mut ids = self.members.clone();
            if group_by_provider {
                let mut provider_positions = HashMap::<String, usize>::from([(String::new(), 0)]);
                let mut provider_members = vec![Vec::<usize>::new()];
                for id in ids {
                    let provider = provider_of(nodes, id).to_string();
                    let position = match provider_positions.get(&provider) {
                        Some(position) => *position,
                        None => {
                            let position = provider_members.len();
                            provider_positions.insert(provider, position);
                            provider_members.push(Vec::new());
                            position
                        }
                    };
                    provider_members[position].push(id);
                }

                ids = Vec::with_capacity(self.members.len());
                for mut members in provider_members {
                    sort_members(&mut members, sort, lower_names, nodes);
                    ids.extend(members);
                }
            } else {
                sort_members(&mut ids, sort, lower_names, nodes);
            }
            self.ordered_members = Some((sort, group_by_provider, ids));
        }
        self.ordered_members
            .as_ref()
            .map(|(_, _, ids)| ids.as_slice())
            .unwrap_or(&self.members)
    }

    fn clear_ordered_members(&mut self) {
        self.ordered_members = None;
    }
}

pub(super) fn replace_catalog(target: &MihomoTarget, catalog: CachedCatalog) {
    catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned")
        .replace((cache_key(target), catalog));
}

pub(super) fn cached_filter(target: &MihomoTarget) -> Option<String> {
    with_catalog(target, |catalog| catalog.filter.clone())
}

pub(super) fn provider_nodes_checked_at(target: &MihomoTarget) -> Option<Instant> {
    with_catalog(target, |catalog| catalog.provider_nodes_checked_at).flatten()
}

pub(super) fn provider_details(target: &MihomoTarget) -> Arc<HashMap<String, String>> {
    with_catalog(target, |catalog| Arc::clone(&catalog.provider_details)).unwrap_or_default()
}

pub(super) fn proxy_detail(target: &MihomoTarget, name: &str) -> Option<String> {
    with_catalog(target, |catalog| {
        catalog
            .direct_details
            .get(name)
            .or_else(|| catalog.provider_details.get(name))
            .cloned()
    })
    .flatten()
}

pub(super) fn set_direct_detail(target: &MihomoTarget, name: String, detail: String) {
    let _ = with_catalog(target, |catalog| {
        catalog.direct_details.insert(name, detail);
    });
}

pub(super) fn mark_provider_nodes_checked(target: &MihomoTarget, checked_at: Instant) {
    let _ = with_catalog(target, |catalog| {
        catalog.provider_nodes_checked_at = Some(checked_at);
    });
}

pub(super) fn has_catalog(target: &MihomoTarget) -> bool {
    let key = cache_key(target);
    catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned")
        .as_ref()
        .is_some_and(|(cached_key, _)| cached_key == &key)
}

pub(super) fn has_group(target: &MihomoTarget, group_name: &str) -> bool {
    with_catalog(target, |catalog| catalog.groups.contains_key(group_name)).unwrap_or(false)
}

pub(super) fn member_entries(
    target: &MihomoTarget,
    group_name: &str,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
) -> Option<Vec<ProxyMemberEntry>> {
    with_catalog(target, |catalog| {
        if needs_lower_names(member_sort) {
            catalog.ensure_lower_names();
        }
        let CachedCatalog {
            names,
            lower_names,
            nodes,
            groups,
            ..
        } = catalog;
        let group = groups.get_mut(group_name)?;
        let ids = group.member_ids(
            member_sort,
            group_by_provider,
            lower_names.as_deref().unwrap_or(&[]),
            nodes,
        );
        let start = (offset as usize).min(ids.len());
        let end = start.saturating_add(limit as usize).min(ids.len());
        Some(
            ids[start..end]
                .iter()
                .map(|id| member_entry(*id, names, nodes))
                .collect(),
        )
    })
    .flatten()
}

pub(super) fn member_sections(
    target: &MihomoTarget,
    group_name: &str,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
) -> Vec<ProxyMemberSection> {
    if !group_by_provider {
        return Vec::new();
    }
    with_catalog(target, |catalog| {
        if needs_lower_names(member_sort) {
            catalog.ensure_lower_names();
        }
        let CachedCatalog {
            lower_names,
            nodes,
            groups,
            ..
        } = catalog;
        let Some(group) = groups.get_mut(group_name) else {
            return Vec::new();
        };
        let ids = group.member_ids(
            member_sort,
            true,
            lower_names.as_deref().unwrap_or(&[]),
            nodes,
        );
        let mut has_provider = false;
        let mut sections = Vec::<ProxyMemberSection>::new();
        for (index, id) in ids.iter().enumerate() {
            let provider = provider_of(nodes, *id);
            has_provider |= !provider.is_empty();
            if let Some(section) = sections.last_mut()
                && section.provider == provider
            {
                section.count = section.count.saturating_add(1);
                continue;
            }
            sections.push(ProxyMemberSection {
                provider: provider.to_string(),
                offset: index.min(u32::MAX as usize) as u32,
                count: 1,
            });
        }
        if has_provider { sections } else { Vec::new() }
    })
    .unwrap_or_default()
}

pub(super) fn member_position(
    target: &MihomoTarget,
    group_name: &str,
    name: &str,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
) -> Option<(usize, usize)> {
    with_catalog(target, |catalog| {
        if needs_lower_names(member_sort) {
            catalog.ensure_lower_names();
        }
        let CachedCatalog {
            names,
            lower_names,
            nodes,
            groups,
            ..
        } = catalog;
        let group = groups.get_mut(group_name)?;
        let ids = group.member_ids(
            member_sort,
            group_by_provider,
            lower_names.as_deref().unwrap_or(&[]),
            nodes,
        );
        let index = ids
            .iter()
            .position(|id| names.get(*id).is_some_and(|member| member == name))?;
        Some((index, ids.len()))
    })
    .flatten()
}

pub(super) fn group_needs_provider_nodes(target: &MihomoTarget, group_name: &str) -> bool {
    with_catalog(target, |catalog| {
        let CachedCatalog { nodes, groups, .. } = catalog;
        let Some(group) = groups.get(group_name) else {
            return false;
        };
        group
            .members
            .iter()
            .any(|id| needs_provider_node(nodes.get(*id).and_then(Option::as_ref), groups))
    })
    .unwrap_or(false)
}

pub(super) fn merge_provider_nodes(
    target: &MihomoTarget,
    incoming: HashMap<String, CachedNode>,
    details: HashMap<String, String>,
) {
    let _ = with_catalog(target, |catalog| {
        catalog.provider_details = Arc::new(details);
        let mut changed = false;
        for (id, name) in catalog.names.iter().enumerate() {
            let Some(node) = incoming.get(name) else {
                continue;
            };
            let Some(slot) = catalog.nodes.get_mut(id) else {
                continue;
            };
            match slot {
                None => {
                    *slot = Some(node.clone());
                    changed = true;
                }
                Some(existing) => {
                    let mut node_changed = false;
                    if node.provider.is_some() && existing.provider != node.provider {
                        existing.provider = node.provider.clone();
                        node_changed = true;
                    }
                    if existing.proxy_type == "Proxy" && existing.proxy_type != node.proxy_type {
                        existing.proxy_type.clone_from(&node.proxy_type);
                        node_changed = true;
                    }
                    if existing.delay != node.delay {
                        existing.delay = node.delay;
                        node_changed = true;
                    }
                    changed |= node_changed;
                }
            }
        }
        if changed {
            for group in catalog.groups.values_mut() {
                group.clear_ordered_members();
            }
        }
        changed
    });
}

pub(super) fn update_node_delays<'a>(
    target: &MihomoTarget,
    delays: impl IntoIterator<Item = (&'a str, i32)>,
) {
    let mut delays: HashMap<&str, i32> = delays.into_iter().collect();
    if delays.is_empty() {
        return;
    }
    let _ = with_catalog(target, |catalog| {
        let mut changed_ids = HashSet::new();
        for (id, name) in catalog.names.iter().enumerate() {
            let Some(delay) = delays.remove(name.as_str()) else {
                continue;
            };
            let Some(slot) = catalog.nodes.get_mut(id) else {
                continue;
            };
            match slot {
                Some(node) if node.delay != delay => {
                    node.delay = delay;
                    changed_ids.insert(id);
                }
                None => {
                    *slot = Some(CachedNode {
                        proxy_type: "Proxy".to_string(),
                        delay,
                        provider: None,
                    });
                    changed_ids.insert(id);
                }
                _ => {}
            }
            if delays.is_empty() {
                break;
            }
        }
        if changed_ids.is_empty() {
            return;
        }
        for group in catalog.groups.values_mut() {
            if group.members.iter().any(|id| changed_ids.contains(id)) {
                group.clear_ordered_members();
            }
        }
    });
}

pub(super) fn node_details(target: &MihomoTarget) -> HashMap<String, CachedNode> {
    with_catalog(target, |catalog| {
        catalog
            .names
            .iter()
            .zip(catalog.nodes.iter())
            .filter_map(|(name, node)| node.as_ref().map(|node| (name.clone(), node.clone())))
            .collect()
    })
    .unwrap_or_default()
}

pub(super) fn member_names(target: &MihomoTarget, group_name: &str) -> Vec<String> {
    with_catalog(target, |catalog| {
        let CachedCatalog {
            names,
            nodes,
            groups,
            ..
        } = catalog;
        let Some(group) = groups.get_mut(group_name) else {
            return Vec::new();
        };
        group
            .member_ids(ProxyMemberSort::Original, false, &[], nodes)
            .iter()
            .filter_map(|id| names.get(*id).cloned())
            .collect()
    })
    .unwrap_or_default()
}

pub(super) fn node_providers(
    target: &MihomoTarget,
    names: &HashSet<String>,
) -> HashMap<String, String> {
    with_catalog(target, |catalog| {
        catalog
            .names
            .iter()
            .enumerate()
            .filter(|(_, name)| names.contains(*name))
            .filter_map(|(id, name)| {
                catalog
                    .nodes
                    .get(id)
                    .and_then(Option::as_ref)
                    .and_then(|node| node.provider.clone())
                    .map(|provider| (name.clone(), provider))
            })
            .collect()
    })
    .unwrap_or_default()
}

pub(super) fn names_need_provider_nodes(target: &MihomoTarget, names: &HashSet<String>) -> bool {
    with_catalog(target, |catalog| {
        catalog
            .names
            .iter()
            .enumerate()
            .filter(|(_, name)| names.contains(*name))
            .any(|(id, _)| {
                needs_provider_node(
                    catalog.nodes.get(id).and_then(Option::as_ref),
                    &catalog.groups,
                )
            })
    })
    .unwrap_or(false)
}

fn needs_provider_node(node: Option<&CachedNode>, groups: &HashMap<String, CachedGroup>) -> bool {
    match node {
        None => true,
        Some(node) => {
            if node
                .provider
                .as_deref()
                .is_some_and(|provider| groups.contains_key(provider))
            {
                return true;
            }
            node.provider.is_none() && node.proxy_type == "Proxy"
        }
    }
}

fn with_catalog<T>(target: &MihomoTarget, f: impl FnOnce(&mut CachedCatalog) -> T) -> Option<T> {
    let key = cache_key(target);
    let mut guard = catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned");
    match guard.as_mut() {
        Some((cached_key, catalog)) if cached_key == &key => Some(f(catalog)),
        _ => None,
    }
}

fn catalog_cache() -> &'static Mutex<Option<(String, CachedCatalog)>> {
    static C: OnceLock<Mutex<Option<(String, CachedCatalog)>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(None))
}

fn cache_key(target: &MihomoTarget) -> String {
    format!(
        "{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or("")
    )
}

fn member_entry(id: usize, names: &[String], nodes: &[Option<CachedNode>]) -> ProxyMemberEntry {
    let node = nodes.get(id).and_then(Option::as_ref);
    ProxyMemberEntry {
        name: names.get(id).cloned().unwrap_or_default(),
        proxy_type: node
            .map(|node| node.proxy_type.clone())
            .unwrap_or_else(|| "Proxy".to_string()),
        delay: node.map(|node| node.delay).unwrap_or(-1),
    }
}

fn provider_of(nodes: &[Option<CachedNode>], id: usize) -> &str {
    nodes
        .get(id)
        .and_then(Option::as_ref)
        .and_then(|node| node.provider.as_deref())
        .unwrap_or_default()
}

fn needs_lower_names(sort: ProxyMemberSort) -> bool {
    matches!(sort, ProxyMemberSort::Name | ProxyMemberSort::Delay)
}
