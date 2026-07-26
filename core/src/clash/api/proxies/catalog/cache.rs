use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;

use crate::clash::api::MihomoTarget;

use super::{ProxyMemberEntry, ProxyMemberSort};

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
    sorted_members: Option<(ProxyMemberSort, Vec<usize>)>,
}

#[frb(ignore)]
pub(super) struct CachedCatalog {
    pub(super) names: Vec<String>,
    pub(super) lower_names: Option<Vec<String>>,
    pub(super) nodes: Vec<Option<CachedNode>>,
    pub(super) groups: HashMap<String, CachedGroup>,
    pub(super) filter: String,
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
            sorted_members: None,
        }
    }

    fn member_ids(
        &mut self,
        sort: ProxyMemberSort,
        lower_names: &[String],
        nodes: &[Option<CachedNode>],
    ) -> &[usize] {
        match sort {
            ProxyMemberSort::Original => &self.members,
            ProxyMemberSort::Name | ProxyMemberSort::Delay => {
                let stale = self
                    .sorted_members
                    .as_ref()
                    .is_none_or(|(cached_sort, _)| *cached_sort != sort);
                if stale {
                    let mut ids = self.members.clone();
                    sort_members(&mut ids, sort, lower_names, nodes);
                    self.sorted_members = Some((sort, ids));
                }
                self.sorted_members
                    .as_ref()
                    .map(|(_, ids)| ids.as_slice())
                    .unwrap_or(&self.members)
            }
        }
    }

    fn clear_sorted_members(&mut self) {
        self.sorted_members = None;
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

pub(super) fn has_catalog(target: &MihomoTarget) -> bool {
    let key = cache_key(target);
    catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned")
        .as_ref()
        .is_some_and(|(cached_key, _)| cached_key == &key)
}

pub(super) fn member_entries(
    target: &MihomoTarget,
    group_name: &str,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
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
        let ids = group.member_ids(member_sort, lower_names.as_deref().unwrap_or(&[]), nodes);
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

pub(super) fn merge_nodes(target: &MihomoTarget, incoming: HashMap<String, CachedNode>) {
    if incoming.is_empty() {
        return;
    }
    let _ = with_catalog(target, |catalog| {
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
                Some(existing) if node.provider.is_some() && existing.provider != node.provider => {
                    existing.provider = node.provider.clone();
                    if existing.proxy_type == "Proxy" {
                        existing.proxy_type.clone_from(&node.proxy_type);
                    }
                    changed = true;
                }
                _ => {}
            }
        }
        if changed {
            for group in catalog.groups.values_mut() {
                group.clear_sorted_members();
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
                group.clear_sorted_members();
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
            .member_ids(ProxyMemberSort::Original, &[], nodes)
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

fn needs_lower_names(sort: ProxyMemberSort) -> bool {
    matches!(sort, ProxyMemberSort::Name | ProxyMemberSort::Delay)
}
