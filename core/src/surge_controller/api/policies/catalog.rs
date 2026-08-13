use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;

use crate::MihomoError;
use crate::backend::api::{ProxyCatalog, ProxyGroupEntry, ProxyMemberEntry, ProxyMemberSort};
use crate::surge_controller::api::string_map;
use crate::surge_controller::client::{SurgeControllerTarget, target_key, with_unary_connection};

use super::CACHE_TTL;
use super::parse::{delay_map, group_type, is_auto_group, member_hash, selected_from_delays};
use super::source::{CatalogSource, SourceMember};

struct CatalogCache {
    source: Arc<CatalogSource>,
    delays: HashMap<String, i32>,
    include_hidden: bool,
    filter: String,
    expires_at: Instant,
}

fn cache() -> &'static Mutex<HashMap<String, CatalogCache>> {
    static CACHE: OnceLock<Mutex<HashMap<String, CatalogCache>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(super) fn clear(target: &SurgeControllerTarget) {
    cache()
        .lock()
        .expect("surge controller policy cache poisoned")
        .remove(&target_key(target));
}

pub async fn proxy_catalog(
    target: SurgeControllerTarget,
    include_hidden: bool,
    filter: String,
) -> Result<ProxyCatalog, MihomoError> {
    let source = super::source::load(&target).await?;
    let (environment, delays) = with_unary_connection(&target, |connection| {
        Box::pin(async move {
            let environment = connection.request(["environment"]).await?;
            let delays = connection
                .request(["dump", "auto-test-group-result"])
                .await
                .unwrap_or_default();
            Ok((environment, delays))
        })
    })
    .await?;

    let environment = environment.get("environment").unwrap_or(&environment);
    let selections = string_map(environment.get("ProxyGroupSelection"));
    let overrides = string_map(environment.get("AutoPolicyGroupOverride"));
    let delay_map = delay_map(&delays);
    let needle = filter.trim().to_lowercase();
    let mut entries = Vec::with_capacity(source.groups.len());
    let mut icon_urls = Vec::new();
    let mut seen_icons = HashSet::new();

    for group in &source.groups {
        let name = group.name.clone();
        if group.members.is_empty() || (group.meta.hidden && !include_hidden) {
            continue;
        }
        let now = overrides
            .get(&name)
            .or_else(|| selections.get(&name))
            .cloned()
            .or_else(|| selected_from_delays(&delays, &name))
            .unwrap_or_default();
        let fixed = overrides.get(&name).cloned().unwrap_or_default();
        let selectable = selections.contains_key(&name) || group.meta.selectable;
        let auto =
            group.meta.auto || is_auto_group(&delays, &name) || overrides.contains_key(&name);
        let group_matches = needle.is_empty() || name.to_lowercase().contains(&needle);
        let mut members = group
            .members
            .iter()
            .filter(|member| group_matches || member.name.to_lowercase().contains(&needle))
            .peekable();
        if members.peek().is_none() {
            continue;
        }
        let now_delay = members
            .clone()
            .find(|member| member.name == now)
            .map(|member| member_delay(member, &delay_map))
            .unwrap_or(-1);
        let members_hash = member_hash(members.clone().map(|member| member.name.as_str()));
        let member_count = members.count().min(u32::MAX as usize) as u32;
        if !group.meta.icon.is_empty() && seen_icons.insert(group.meta.icon.as_str()) {
            icon_urls.push(group.meta.icon.clone());
        }
        entries.push(ProxyGroupEntry {
            name,
            proxy_type: if selectable {
                "Selector".into()
            } else if !group.meta.proxy_type.is_empty() {
                group_type(&group.meta.proxy_type)
            } else if auto {
                "Auto".into()
            } else {
                "PolicyGroup".into()
            },
            selectable: selectable || auto,
            icon: group.meta.icon.clone(),
            member_count,
            members_hash,
            now,
            now_delay,
            fixed,
            ..Default::default()
        });
    }

    cache()
        .lock()
        .expect("surge controller policy cache poisoned")
        .insert(
            target_key(&target),
            CatalogCache {
                source,
                delays: delay_map,
                include_hidden,
                filter: needle,
                expires_at: Instant::now() + CACHE_TTL,
            },
        );
    Ok(ProxyCatalog {
        groups: entries,
        icon_urls,
    })
}

pub async fn proxy_group_members(
    target: SurgeControllerTarget,
    group: String,
    offset: u32,
    limit: u32,
    sort: ProxyMemberSort,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    ensure(target.clone()).await?;
    let mut members = members(&target, &group);
    sort_members(&mut members, sort);
    Ok(members
        .into_iter()
        .skip(offset as usize)
        .take(limit as usize)
        .collect())
}

pub(super) async fn ensure(target: SurgeControllerTarget) -> Result<(), MihomoError> {
    if cache()
        .lock()
        .expect("surge controller policy cache poisoned")
        .get(&target_key(&target))
        .is_some_and(|catalog| catalog.expires_at > Instant::now())
    {
        return Ok(());
    }
    proxy_catalog(target, true, String::new()).await?;
    Ok(())
}

pub(super) async fn refresh(target: SurgeControllerTarget) -> Result<(), MihomoError> {
    let (include_hidden, filter) = cache()
        .lock()
        .expect("surge controller policy cache poisoned")
        .get(&target_key(&target))
        .map(|catalog| (catalog.include_hidden, catalog.filter.clone()))
        .unwrap_or((true, String::new()));
    proxy_catalog(target, include_hidden, filter)
        .await
        .map(|_| ())
}

pub(super) fn members(target: &SurgeControllerTarget, group: &str) -> Vec<ProxyMemberEntry> {
    cache()
        .lock()
        .expect("surge controller policy cache poisoned")
        .get(&target_key(target))
        .map(|catalog| catalog_members(catalog, group))
        .unwrap_or_default()
}

pub(super) fn delay_candidates(
    target: &SurgeControllerTarget,
    names: &HashSet<String>,
) -> Vec<(String, usize, Vec<String>)> {
    cache()
        .lock()
        .expect("surge controller policy cache poisoned")
        .get(&target_key(target))
        .map(|catalog| {
            catalog
                .source
                .groups
                .iter()
                .filter_map(|group| {
                    let covered = group
                        .members
                        .iter()
                        .filter(|member| names.contains(&member.name))
                        .map(|member| member.name.clone())
                        .collect::<Vec<_>>();
                    (!covered.is_empty())
                        .then(|| (group.name.clone(), group.members.len(), covered))
                })
                .collect()
        })
        .unwrap_or_default()
}

pub(super) fn delays_by_name(target: &SurgeControllerTarget) -> HashMap<String, i32> {
    let cache = cache()
        .lock()
        .expect("surge controller policy cache poisoned");
    cache
        .get(&target_key(target))
        .into_iter()
        .flat_map(|catalog| {
            catalog
                .source
                .groups
                .iter()
                .flat_map(|group| group.members.iter())
                .map(|member| (member.name.clone(), member_delay(member, &catalog.delays)))
        })
        .collect()
}

fn catalog_members(catalog: &CatalogCache, group_name: &str) -> Vec<ProxyMemberEntry> {
    let Some(group) = catalog
        .source
        .groups
        .iter()
        .find(|group| group.name == group_name)
        .filter(|group| catalog.include_hidden || !group.meta.hidden)
    else {
        return Vec::new();
    };
    let group_matches =
        catalog.filter.is_empty() || group.name.to_lowercase().contains(&catalog.filter);
    group
        .members
        .iter()
        .filter(|member| group_matches || member.name.to_lowercase().contains(&catalog.filter))
        .map(|member| ProxyMemberEntry {
            name: member.name.clone(),
            proxy_type: member.proxy_type.clone(),
            delay: member_delay(member, &catalog.delays),
        })
        .collect()
}

fn member_delay(member: &SourceMember, delays: &HashMap<String, i32>) -> i32 {
    member
        .delay_key
        .as_ref()
        .and_then(|key| delays.get(key))
        .or_else(|| delays.get(&member.name))
        .copied()
        .unwrap_or(-1)
}

fn sort_members(entries: &mut [ProxyMemberEntry], sort: ProxyMemberSort) {
    match sort {
        ProxyMemberSort::Original => {}
        ProxyMemberSort::Name => entries.sort_by(|a, b| a.name.cmp(&b.name)),
        ProxyMemberSort::Delay => entries.sort_by(|a, b| {
            let a_delay = if a.delay < 0 { i32::MAX } else { a.delay };
            let b_delay = if b.delay < 0 { i32::MAX } else { b.delay };
            a_delay.cmp(&b_delay).then_with(|| a.name.cmp(&b.name))
        }),
    }
}
