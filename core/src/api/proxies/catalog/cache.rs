use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;

use crate::api::MihomoTarget;

use super::{ProxyMemberEntry, ProxyMemberSort};

#[frb(ignore)]
pub(super) struct CachedNode {
    pub(super) proxy_type: String,
    pub(super) delay: i32,
}

#[frb(ignore)]
pub(super) struct CachedGroup {
    pub(super) members: Vec<usize>,
    sorted_members: Option<(ProxyMemberSort, Vec<usize>)>,
}

#[frb(ignore)]
pub(super) struct CachedCatalog {
    pub(super) names: Vec<String>,
    pub(super) nodes: HashMap<usize, CachedNode>,
    pub(super) groups: HashMap<String, CachedGroup>,
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
        names: &[String],
        nodes: &HashMap<usize, CachedNode>,
    ) -> &[usize] {
        match sort {
            ProxyMemberSort::Original => &self.members,
            ProxyMemberSort::Name | ProxyMemberSort::Delay => {
                let stale = self
                    .sorted_members
                    .as_ref()
                    .map_or(true, |(cached_sort, _)| *cached_sort != sort);
                if stale {
                    let mut ids = self.members.clone();
                    sort_members(&mut ids, sort, names, nodes);
                    self.sorted_members = Some((sort, ids));
                }
                self.sorted_members
                    .as_ref()
                    .map(|(_, ids)| ids.as_slice())
                    .unwrap_or(&self.members)
            }
        }
    }
}

pub(super) fn replace_catalog(target: &MihomoTarget, catalog: CachedCatalog) {
    catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned")
        .replace((cache_key(target), catalog));
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
) -> Vec<ProxyMemberEntry> {
    with_catalog(target, |catalog| {
        let CachedCatalog {
            names,
            nodes,
            groups,
        } = catalog;
        let Some(group) = groups.get_mut(group_name) else {
            return Vec::new();
        };
        let ids = group.member_ids(member_sort, names, nodes);
        let start = (offset as usize).min(ids.len());
        let end = start.saturating_add(limit as usize).min(ids.len());
        ids[start..end]
            .iter()
            .map(|id| member_entry(*id, names, nodes))
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
        } = catalog;
        let Some(group) = groups.get_mut(group_name) else {
            return Vec::new();
        };
        group
            .member_ids(ProxyMemberSort::Original, names, nodes)
            .iter()
            .filter_map(|id| names.get(*id).cloned())
            .collect()
    })
    .unwrap_or_default()
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

fn member_entry(
    id: usize,
    names: &[String],
    nodes: &HashMap<usize, CachedNode>,
) -> ProxyMemberEntry {
    let node = nodes.get(&id);
    ProxyMemberEntry {
        name: names.get(id).cloned().unwrap_or_default(),
        proxy_type: node
            .map(|node| node.proxy_type.clone())
            .unwrap_or_else(|| "Proxy".to_string()),
        delay: node.map(|node| node.delay).unwrap_or(-1),
    }
}

fn sort_members(
    member_ids: &mut [usize],
    sort: ProxyMemberSort,
    names: &[String],
    nodes: &HashMap<usize, CachedNode>,
) {
    match sort {
        ProxyMemberSort::Original => {}
        ProxyMemberSort::Name => {
            member_ids.sort_by_cached_key(|id| names.get(*id).map(|s| s.to_lowercase()))
        }
        ProxyMemberSort::Delay => {
            member_ids.sort_by_cached_key(|id| {
                (
                    delay_score(delay_of(nodes, *id)),
                    names.get(*id).map(|s| s.to_lowercase()),
                )
            });
        }
    }
}

fn delay_of(nodes: &HashMap<usize, CachedNode>, id: usize) -> i32 {
    nodes.get(&id).map(|node| node.delay).unwrap_or(-1)
}

fn delay_score(delay: i32) -> i32 {
    if delay < 0 {
        1 << 30
    } else if delay == 0 {
        (1 << 30) - 1
    } else {
        delay
    }
}
