use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use serde_json::Value;

use crate::MihomoError;
use crate::backend::api::{ProxyProviderEntry, ProxyProviderNodeWindow, RuleProviderEntry};
use crate::cache::target::ActiveTargetCache;
use crate::surge_controller::client::{SurgeControllerTarget, target_key};

use super::{command_ok, policies};

mod parse;

use parse::{
    resource_display_name, resource_key, resource_matches_group, resource_time, resource_type,
    resource_updatable, resources,
};

#[derive(Default)]
struct ProxyResourceSnapshot {
    nodes: HashMap<String, policies::ResourceMembers>,
}

fn proxy_cache() -> &'static Mutex<HashMap<String, ProxyResourceSnapshot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, ProxyResourceSnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn resource_cache() -> &'static ActiveTargetCache<Value> {
    static CACHE: OnceLock<ActiveTargetCache<Value>> = OnceLock::new();
    CACHE.get_or_init(ActiveTargetCache::new)
}

pub async fn proxy_provider_catalog(
    target: SurgeControllerTarget,
    force: bool,
) -> Result<Vec<ProxyProviderEntry>, MihomoError> {
    if force {
        policies::clear_cache(&target);
    }
    let raw = resource_list(&target, force).await?;
    let resources = resources(&raw, &["policy-group"]);
    let groups = policies::resource_groups(&target).await?;
    let mut snapshot = ProxyResourceSnapshot::default();
    let mut catalog = Vec::with_capacity(resources.len());

    for resource in resources {
        let key = resource_key(resource);
        if key.is_empty() {
            continue;
        }
        let matched_groups = groups
            .iter()
            .filter(|group| resource_matches_group(resource, &group.name, &group.detail))
            .collect::<Vec<_>>();
        let matched_group = (matched_groups.len() == 1).then(|| matched_groups[0]);
        let nodes = matched_group
            .map(policies::resource_group_members)
            .filter(|members| members.len() > 0);
        catalog.push(ProxyProviderEntry {
            key: key.clone(),
            name: resource_display_name(resource, matched_group.map(|group| group.name.as_str())),
            vehicle_type: resource_type(resource),
            proxies: nodes
                .as_ref()
                .map(|nodes| nodes.len().min(u32::MAX as usize) as u32)
                .unwrap_or_default(),
            updated_at: resource_time(resource),
            updatable: resource_updatable(resource),
            ..Default::default()
        });
        if let Some(nodes) = nodes {
            snapshot.nodes.insert(key, nodes);
        }
    }
    catalog.sort_by(|a, b| a.name.cmp(&b.name));
    proxy_cache()
        .lock()
        .expect("surge controller resource cache poisoned")
        .insert(target_key(&target), snapshot);
    Ok(catalog)
}

pub async fn proxy_provider_nodes(
    target: SurgeControllerTarget,
    resource_key: String,
    filter: String,
    offset: u32,
    limit: u32,
) -> Result<ProxyProviderNodeWindow, MihomoError> {
    let key = target_key(&target);
    if !proxy_cache()
        .lock()
        .expect("surge controller resource cache poisoned")
        .contains_key(&key)
    {
        proxy_provider_catalog(target.clone(), false).await?;
    }
    let nodes = proxy_cache()
        .lock()
        .expect("surge controller resource cache poisoned")
        .get(&key)
        .and_then(|snapshot| snapshot.nodes.get(&resource_key))
        .cloned();
    let Some(nodes) = nodes else {
        return Ok(ProxyProviderNodeWindow::default());
    };
    let total = nodes.len();
    let (filtered, start, entries) = nodes.window(&filter, offset, limit);
    Ok(ProxyProviderNodeWindow {
        total: total.min(u32::MAX as usize) as u32,
        filtered: filtered.min(u32::MAX as usize) as u32,
        offset: start.min(u32::MAX as usize) as u32,
        entries,
    })
}

pub async fn rule_provider_catalog(
    target: SurgeControllerTarget,
    force: bool,
) -> Result<Vec<RuleProviderEntry>, MihomoError> {
    let mut catalog = resources(
        &resource_list(&target, force).await?,
        &["ruleset", "domainset", "script"],
    )
    .into_iter()
    .filter_map(|item| {
        let key = resource_key(item);
        (!key.is_empty()).then(|| RuleProviderEntry {
            key,
            name: resource_display_name(item, None),
            vehicle_type: resource_type(item),
            updated_at: resource_time(item),
            updatable: resource_updatable(item),
            ..Default::default()
        })
    })
    .collect::<Vec<_>>();
    catalog.sort_by(|a, b| {
        a.vehicle_type
            .cmp(&b.vehicle_type)
            .then_with(|| a.name.cmp(&b.name))
    });
    Ok(catalog)
}

pub async fn proxy_provider_update(
    target: SurgeControllerTarget,
    name: String,
) -> Result<(), MihomoError> {
    update_resource(&target, name).await?;
    policies::clear_cache(&target);
    Ok(())
}

pub async fn rule_provider_update(
    target: SurgeControllerTarget,
    name: String,
) -> Result<(), MihomoError> {
    update_resource(&target, name).await
}

async fn update_resource(target: &SurgeControllerTarget, name: String) -> Result<(), MihomoError> {
    command_ok(target, ["external-resource".into(), "update".into(), name]).await?;
    clear_cache(target);
    Ok(())
}

pub(super) fn clear_cache(target: &SurgeControllerTarget) {
    let key = target_key(target);
    proxy_cache()
        .lock()
        .expect("surge controller resource cache poisoned")
        .remove(&key);
    resource_cache().clear(&key);
}

async fn resource_list(target: &SurgeControllerTarget, force: bool) -> Result<Value, MihomoError> {
    let key = target_key(target);
    let load_target = target.clone();
    resource_cache()
        .load(&key, force, move || async move {
            load_target.request(["external-resource", "list"]).await
        })
        .await
}
