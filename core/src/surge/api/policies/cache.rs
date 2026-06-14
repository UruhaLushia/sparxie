use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use crate::backend::api::ProxyMemberEntry;
use crate::surge::client::{SurgeTarget, target_key};

#[derive(Clone, Debug, Default)]
pub(super) struct CachedPolicyMember {
    pub(super) entry: ProxyMemberEntry,
    pub(super) line_hash: String,
}

#[derive(Clone, Debug, Default)]
struct CachedCatalog {
    groups: HashMap<String, Vec<CachedPolicyMember>>,
}

fn catalog_cache() -> &'static Mutex<HashMap<String, CachedCatalog>> {
    static C: OnceLock<Mutex<HashMap<String, CachedCatalog>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(super) fn contains_catalog(target: &SurgeTarget) -> bool {
    catalog_cache()
        .lock()
        .expect("surge catalog cache poisoned")
        .contains_key(&target_key(target))
}

pub(super) fn store_catalog(
    target: &SurgeTarget,
    groups: HashMap<String, Vec<CachedPolicyMember>>,
) {
    catalog_cache()
        .lock()
        .expect("surge catalog cache poisoned")
        .insert(target_key(target), CachedCatalog { groups });
}

pub(super) fn cached_group_members(target: &SurgeTarget, group: &str) -> Vec<CachedPolicyMember> {
    catalog_cache()
        .lock()
        .expect("surge catalog cache poisoned")
        .get(&target_key(target))
        .and_then(|c| c.groups.get(group))
        .cloned()
        .unwrap_or_default()
}

pub(super) fn cached_members_by_name(target: &SurgeTarget) -> HashMap<String, CachedPolicyMember> {
    let mut out = HashMap::new();
    if let Some(catalog) = catalog_cache()
        .lock()
        .expect("surge catalog cache poisoned")
        .get(&target_key(target))
    {
        for members in catalog.groups.values() {
            for member in members {
                out.entry(member.entry.name.clone())
                    .or_insert_with(|| member.clone());
            }
        }
    }
    out
}

pub(super) fn cached_member_delay(target: &SurgeTarget, group: &str, name: &str) -> i32 {
    cached_group_members(target, group)
        .into_iter()
        .find(|member| member.entry.name == name)
        .map(|member| member.entry.delay)
        .unwrap_or(-1)
}

pub(super) fn update_cached_delay(target: &SurgeTarget, name: &str, delay: i32) {
    let mut guard = catalog_cache()
        .lock()
        .expect("surge catalog cache poisoned");
    let Some(catalog) = guard.get_mut(&target_key(target)) else {
        return;
    };
    for members in catalog.groups.values_mut() {
        for member in members {
            if member.entry.name == name {
                member.entry.delay = delay;
            }
        }
    }
}

pub(super) fn update_cached_delays(target: &SurgeTarget, delays: &HashMap<String, i32>) {
    let mut guard = catalog_cache()
        .lock()
        .expect("surge catalog cache poisoned");
    let Some(catalog) = guard.get_mut(&target_key(target)) else {
        return;
    };
    for members in catalog.groups.values_mut() {
        for member in members {
            member.entry.delay = delays
                .get(&member.line_hash)
                .or_else(|| delays.get(&member.entry.name))
                .copied()
                .unwrap_or(member.entry.delay);
        }
    }
}
