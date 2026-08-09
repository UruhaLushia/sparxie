use std::collections::{HashMap, VecDeque};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use flutter_rust_bridge::frb;

use crate::clash::api::MihomoTarget;

use super::ProxyMemberSort;

mod members;
mod nodes;
mod sort;

pub(super) use members::{member_entries, member_names, member_position, member_sections};
pub(super) use nodes::{
    merge_provider_nodes, names_need_provider_nodes, node_delays, node_providers,
    update_node_delays,
};

const DIRECT_DETAIL_CACHE_LIMIT: usize = 16;

#[derive(Clone, Eq, PartialEq)]
#[frb(ignore)]
pub(super) struct CachedNode {
    pub(super) proxy_type: Box<str>,
    pub(super) delay: i32,
    pub(super) provider: Option<Box<str>>,
}

#[frb(ignore)]
pub(super) struct CachedGroup {
    pub(super) members: Vec<u32>,
    ordered_members: Option<(ProxyMemberSort, bool, Vec<u32>)>,
}

#[frb(ignore)]
pub(super) struct CachedCatalog {
    pub(super) names: Vec<String>,
    pub(super) lower_names: Option<Vec<String>>,
    pub(super) nodes: Vec<Option<CachedNode>>,
    pub(super) groups: HashMap<String, CachedGroup>,
    pub(super) direct_details: VecDeque<(String, String)>,
    pub(super) filter: String,
    pub(super) provider_nodes_checked_at: Option<Instant>,
}

impl CachedCatalog {
    fn reuse_derived_state(&mut self, previous: &mut Self) {
        if self.names != previous.names {
            return;
        }
        self.lower_names = previous.lower_names.take();
        if self.nodes != previous.nodes {
            return;
        }
        for (name, group) in &mut self.groups {
            let Some(previous_group) = previous.groups.get_mut(name) else {
                continue;
            };
            if group.members == previous_group.members {
                group.ordered_members = previous_group.ordered_members.take();
            }
        }
    }

    fn reuse_missing_nodes(&mut self, previous: &Self) {
        if self.names == previous.names {
            for (node, previous_node) in self.nodes.iter_mut().zip(&previous.nodes) {
                if node.is_none() {
                    node.clone_from(previous_node);
                }
            }
            return;
        }
        let Self { names, nodes, .. } = self;
        let missing: HashMap<&str, usize> = names
            .iter()
            .enumerate()
            .filter(|(index, _)| nodes.get(*index).is_none_or(Option::is_none))
            .map(|(index, name)| (name.as_str(), index))
            .collect();
        if missing.is_empty() {
            return;
        }
        for (name, node) in previous.names.iter().zip(&previous.nodes) {
            let Some(index) = missing.get(name.as_str()) else {
                continue;
            };
            if let Some(slot) = nodes.get_mut(*index) {
                slot.clone_from(node);
            }
        }
    }
}

impl CachedGroup {
    pub(super) fn new(members: Vec<u32>) -> Self {
        Self {
            members,
            ordered_members: None,
        }
    }

    fn clear_ordered_members(&mut self) {
        self.ordered_members = None;
    }
}

#[derive(Default)]
struct CatalogCacheState {
    value: Option<(String, CachedCatalog)>,
    next: u64,
    active: Option<(String, u64)>,
}

pub(super) fn replace_catalog(target: &MihomoTarget, token: u64, mut catalog: CachedCatalog) {
    let key = cache_key(target);
    let mut state = catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned");
    if !state
        .active
        .as_ref()
        .is_some_and(|(active_key, active_token)| active_key == &key && *active_token == token)
    {
        return;
    }
    state.active = None;
    if let Some((cached_key, previous)) = state.value.as_mut()
        && cached_key == &key
    {
        catalog.direct_details = std::mem::take(&mut previous.direct_details);
        catalog.reuse_missing_nodes(previous);
        catalog.reuse_derived_state(previous);
    }
    state.value = Some((key, catalog));
}

pub(super) fn begin_catalog_load(target: &MihomoTarget) -> u64 {
    let key = cache_key(target);
    let mut state = catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned");
    if state
        .value
        .as_ref()
        .is_some_and(|(cached_key, _)| cached_key != &key)
    {
        state.value = None;
    }
    state.next = state.next.wrapping_add(1);
    let token = state.next;
    state.active = Some((key, token));
    token
}

pub(super) fn finish_catalog_load(target: &MihomoTarget, token: u64) {
    let key = cache_key(target);
    let mut state = catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned");
    if state
        .active
        .as_ref()
        .is_some_and(|(active_key, active_token)| active_key == &key && *active_token == token)
    {
        state.active = None;
    }
}

pub(super) fn clear_catalog(target: &MihomoTarget) {
    let key = cache_key(target);
    let mut state = catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned");
    if state
        .active
        .as_ref()
        .is_some_and(|(active_key, _)| active_key == &key)
    {
        state.active = None;
    }
    if state
        .value
        .as_ref()
        .is_some_and(|(cached_key, _)| cached_key == &key)
    {
        state.value = None;
    }
}

pub(super) fn cached_filter(target: &MihomoTarget) -> Option<String> {
    with_catalog(target, |catalog| catalog.filter.clone())
}

pub(super) fn provider_nodes_checked_at(target: &MihomoTarget) -> Option<Instant> {
    with_catalog(target, |catalog| catalog.provider_nodes_checked_at).flatten()
}

pub(super) fn proxy_detail(target: &MihomoTarget, name: &str) -> Option<String> {
    with_catalog(target, |catalog| {
        let position = catalog
            .direct_details
            .iter()
            .position(|(entry_name, _)| entry_name == name)?;
        let entry = catalog.direct_details.remove(position)?;
        let detail = entry.1.clone();
        catalog.direct_details.push_back(entry);
        Some(detail)
    })
    .flatten()
}

pub(super) fn set_direct_detail(target: &MihomoTarget, name: String, detail: String) {
    let _ = with_catalog(target, |catalog| {
        if let Some(position) = catalog
            .direct_details
            .iter()
            .position(|(entry_name, _)| entry_name == &name)
        {
            catalog.direct_details.remove(position);
        }
        catalog.direct_details.push_back((name, detail));
        if catalog.direct_details.len() > DIRECT_DETAIL_CACHE_LIMIT {
            catalog.direct_details.pop_front();
        }
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
        .value
        .as_ref()
        .is_some_and(|(cached_key, _)| cached_key == &key)
}

pub(super) fn has_group(target: &MihomoTarget, group_name: &str) -> bool {
    with_catalog(target, |catalog| catalog.groups.contains_key(group_name)).unwrap_or(false)
}

fn with_catalog<T>(target: &MihomoTarget, f: impl FnOnce(&mut CachedCatalog) -> T) -> Option<T> {
    let key = cache_key(target);
    let mut state = catalog_cache()
        .lock()
        .expect("proxy catalog cache poisoned");
    match state.value.as_mut() {
        Some((cached_key, catalog)) if cached_key == &key => Some(f(catalog)),
        _ => None,
    }
}

fn catalog_cache() -> &'static Mutex<CatalogCacheState> {
    static C: OnceLock<Mutex<CatalogCacheState>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(CatalogCacheState::default()))
}

fn cache_key(target: &MihomoTarget) -> String {
    target.identity_key()
}
