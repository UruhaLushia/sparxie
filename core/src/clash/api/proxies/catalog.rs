use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::MihomoError;
use crate::clash::api::{MihomoTarget, urlencode};

use super::value::{field_or, first_field};

use cache::{CachedCatalog, CachedGroup, CachedNode};
use parse::{contains_filter, history_delay, intern_member_list, push_icon};
pub use types::{ProxyCatalog, ProxyGroupEntry, ProxyMemberEntry, ProxyMemberSort};

mod cache;
mod parse;
mod types;

const PROVIDER_NODES_REFRESH_INTERVAL: Duration = Duration::from_secs(5 * 60);

/// Structured proxy + group catalog. Rust parses mihomo's `/proxies`, applies
/// hidden-group filtering, preserves UI ordering (`GLOBAL.all`), caches full
/// group members in Rust, and returns only group summaries to Dart.
pub async fn proxy_catalog(
    target: MihomoTarget,
    include_hidden: bool,
    _resolve_provider_current_delay: bool,
    filter: String,
) -> Result<ProxyCatalog, MihomoError> {
    let client = target.client()?;
    let previous_nodes = cache::node_details(&target);
    let previous_provider_nodes_checked_at = cache::provider_nodes_checked_at(&target);
    let previous_provider_details = cache::provider_details(&target);
    let refresh_provider_nodes = provider_nodes_are_stale(previous_provider_nodes_checked_at);
    let provider_request = async {
        if refresh_provider_nodes {
            provider_nodes(&client).await.ok()
        } else {
            None
        }
    };
    let (raw, fresh_provider_nodes) = tokio::join!(client.get_json("proxies"), provider_request);
    let raw = raw?;
    let Some(proxies) = raw.get("proxies").and_then(Value::as_object) else {
        return Ok(ProxyCatalog::default());
    };

    let mut groups = Vec::new();
    let mut cached_groups = HashMap::new();
    let mut name_ids = HashMap::new();
    let mut icon_urls = Vec::new();
    let mut seen_icons = HashSet::new();

    let filter = filter.trim();
    let filter = if filter.is_ascii() {
        Cow::Borrowed(filter)
    } else {
        Cow::Owned(filter.to_lowercase())
    };
    // Group order comes from the upstream GLOBAL list; member sorting should
    // only affect the displayed members inside each group.
    let global_all = proxies
        .get("GLOBAL")
        .and_then(|data| data.get("all"))
        .and_then(Value::as_array)
        .filter(|all| !all.is_empty());

    for (position, (name, data)) in proxies.iter().enumerate() {
        let all = data.get("all");
        let hidden = data.get("hidden").and_then(Value::as_bool).unwrap_or(false);
        if hidden && !include_hidden {
            continue;
        }
        let member_filter = if contains_filter(name, filter.as_ref()) {
            ""
        } else {
            filter.as_ref()
        };
        let (members, members_hash) = intern_member_list(all, &mut name_ids, member_filter);
        if members.is_empty() {
            continue;
        }
        let member_count = members.len();
        let icon = field_or(data, "icon", "");
        let now = field_or(data, "now", "");
        let top_level_node = proxies.get(now.as_str());
        let cached_node = previous_nodes.get(now.as_str());
        let now_delay = top_level_node
            .map(proxy_delay)
            .or_else(|| cached_node.map(|node| node.delay))
            .unwrap_or(-1);
        push_icon(&mut icon_urls, &mut seen_icons, &icon);
        cached_groups.insert(name.clone(), CachedGroup::new(members));
        groups.push((
            position,
            ProxyGroupEntry {
                name: name.clone(),
                proxy_type: field_or(data, "type", "Selector"),
                icon,
                member_count: member_count.min(u32::MAX as usize) as u32,
                members_hash,
                now,
                now_delay,
                test_url: first_field(data, &["testUrl", "tester"]),
                fixed: field_or(data, "fixed", ""),
            },
        ));
    }

    let provider_nodes_checked_at = if refresh_provider_nodes {
        Some(Instant::now())
    } else {
        previous_provider_nodes_checked_at
    };
    if let Some(nodes) = fresh_provider_nodes.as_ref() {
        for (_, group) in &mut groups {
            if proxies.contains_key(group.now.as_str()) {
                continue;
            }
            if let Some(node) = nodes.summaries.get(group.now.as_str()) {
                group.now_delay = node.delay;
            }
        }
    }

    let group_positions: HashMap<&str, usize> = global_all
        .map(|names| {
            names
                .iter()
                .enumerate()
                .filter_map(|(i, name)| name.as_str().map(|name| (name, i)))
                .collect()
        })
        .unwrap_or_default();
    groups.sort_by(|(a_pos, a), (b_pos, b)| group_order(a_pos, a, b_pos, b, &group_positions));

    let mut names = vec![String::new(); name_ids.len()];
    for (name, id) in name_ids {
        names[id] = name;
    }
    let mut nodes = Vec::with_capacity(names.len());
    for name in &names {
        nodes.push(
            proxies
                .get(name)
                .map(cached_node)
                .or_else(|| {
                    fresh_provider_nodes
                        .as_ref()
                        .and_then(|nodes| nodes.summaries.get(name))
                        .cloned()
                })
                .or_else(|| previous_nodes.get(name).cloned()),
        );
    }
    let mut direct_details = HashMap::new();
    for data in proxies.values() {
        let Some(members) = data.get("all").and_then(Value::as_array) else {
            continue;
        };
        for name in members.iter().filter_map(Value::as_str) {
            if direct_details.contains_key(name) {
                continue;
            }
            if let Some(detail) = proxies.get(name) {
                direct_details.insert(name.to_string(), detail.to_string());
            }
        }
    }
    let provider_details = fresh_provider_nodes
        .map(|nodes| Arc::new(nodes.details))
        .unwrap_or(previous_provider_details);
    cache::replace_catalog(
        &target,
        CachedCatalog {
            names,
            lower_names: None,
            nodes,
            groups: cached_groups,
            direct_details,
            provider_details,
            filter: filter.into_owned(),
            provider_nodes_checked_at,
        },
    );

    Ok(ProxyCatalog {
        groups: groups.into_iter().map(|(_, group)| group).collect(),
        icon_urls,
    })
}

struct ProviderNodes {
    summaries: HashMap<String, CachedNode>,
    details: HashMap<String, String>,
}

async fn provider_nodes(
    client: &crate::clash::client::MihomoClient,
) -> Result<ProviderNodes, MihomoError> {
    let raw = client.get_json("providers/proxies").await?;
    let mut summaries = HashMap::new();
    let mut details = HashMap::new();
    let Some(providers) = raw.get("providers").and_then(Value::as_object) else {
        return Ok(ProviderNodes { summaries, details });
    };
    for (provider_name, provider) in providers {
        if field_or(provider, "vehicleType", "") == "Compatible" {
            continue;
        }
        let Some(nodes) = provider.get("proxies").and_then(Value::as_array) else {
            continue;
        };
        for node in nodes {
            let name = field_or(node, "name", "");
            if !name.is_empty() {
                let provider_name =
                    node_provider_name(node).unwrap_or_else(|| provider_name.clone());
                details.insert(name.clone(), provider_node_detail(node, &provider_name));
                summaries.insert(name, cached_node_with_provider(node, Some(provider_name)));
            }
        }
    }
    Ok(ProviderNodes { summaries, details })
}

pub(crate) async fn refresh_cached_provider_nodes(
    target: &MihomoTarget,
) -> Result<(), MihomoError> {
    cache::mark_provider_nodes_checked(target, Instant::now());
    let client = target.client()?;
    if let Ok(nodes) = provider_nodes(&client).await {
        cache::merge_provider_nodes(target, nodes.summaries, nodes.details);
    }
    Ok(())
}

pub(crate) async fn cached_proxy_detail(
    target: &MihomoTarget,
    name: &str,
) -> Result<Option<String>, MihomoError> {
    if !cache::has_catalog(target) {
        refresh_cached_catalog(target).await?;
    }
    if let Some(detail) = cache::proxy_detail(target, name) {
        return Ok(Some(detail));
    }
    refresh_cached_provider_nodes(target).await?;
    Ok(cache::proxy_detail(target, name))
}

fn provider_nodes_are_stale(checked_at: Option<Instant>) -> bool {
    checked_at.is_none_or(|checked_at| checked_at.elapsed() >= PROVIDER_NODES_REFRESH_INTERVAL)
}

pub(crate) async fn refresh_cached_node_detail(
    target: &MihomoTarget,
    name: &str,
    provider_backed: bool,
) -> Result<(), MihomoError> {
    if provider_backed {
        return refresh_cached_provider_nodes(target).await;
    }
    let path = format!("proxies/{}", urlencode(name));
    let detail = target.client()?.get_json(&path).await?.to_string();
    cache::set_direct_detail(target, name.to_string(), detail);
    Ok(())
}

fn cached_node(data: &Value) -> CachedNode {
    cached_node_with_provider(data, node_provider_name(data))
}

fn cached_node_with_provider(data: &Value, provider: Option<String>) -> CachedNode {
    CachedNode {
        proxy_type: field_or(data, "type", "Proxy"),
        delay: proxy_delay(data),
        provider,
    }
}

fn provider_node_detail(data: &Value, provider: &str) -> String {
    if !field_or(data, "provider-name", "").is_empty() {
        return data.to_string();
    }
    let mut detail = data.clone();
    if let Some(fields) = detail.as_object_mut() {
        fields.insert(
            "provider-name".to_string(),
            Value::String(provider.to_string()),
        );
    }
    detail.to_string()
}

fn node_provider_name(data: &Value) -> Option<String> {
    let provider = field_or(data, "provider-name", "");
    (!provider.is_empty()).then_some(provider)
}

fn proxy_delay(data: &Value) -> i32 {
    let history = history_delay(data.get("history"));
    if history >= 0 {
        history
    } else {
        data.get("delay")
            .map(super::value::value_to_i32)
            .unwrap_or(-1)
    }
}

/// Windowed members for one proxy group. The full member list stays in Rust so
/// very large groups do not cross the bridge on every catalog refresh.
pub async fn proxy_group_members(
    target: MihomoTarget,
    group: String,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    if !cache::has_catalog(&target) {
        refresh_cached_catalog(&target).await?;
    }
    if cache::group_needs_provider_nodes(&target, &group) {
        refresh_cached_provider_nodes(&target).await?;
    }
    if let Some(entries) = cache::member_entries(&target, &group, offset, limit, member_sort) {
        return Ok(entries);
    }
    refresh_cached_catalog(&target).await?;
    if cache::group_needs_provider_nodes(&target, &group) {
        refresh_cached_provider_nodes(&target).await?;
    }
    Ok(cache::member_entries(&target, &group, offset, limit, member_sort).unwrap_or_default())
}

pub(crate) async fn cached_group_member_names(
    target: MihomoTarget,
    group: &str,
) -> Result<Vec<String>, MihomoError> {
    if !cache::has_catalog(&target) {
        refresh_cached_catalog(&target).await?;
    }
    Ok(cache::member_names(&target, group))
}

async fn refresh_cached_catalog(target: &MihomoTarget) -> Result<(), MihomoError> {
    let filter = cache::cached_filter(target).unwrap_or_default();
    let _ = proxy_catalog(target.clone(), true, false, filter).await?;
    Ok(())
}

pub(crate) async fn cached_node_providers(
    target: MihomoTarget,
    names: &[String],
) -> Result<HashMap<String, String>, MihomoError> {
    let names: HashSet<String> = names.iter().cloned().collect();
    if names.is_empty() {
        return Ok(HashMap::new());
    }
    if !cache::has_catalog(&target) {
        refresh_cached_catalog(&target).await?;
    }
    if cache::names_need_provider_nodes(&target, &names) {
        refresh_cached_provider_nodes(&target).await?;
    }
    Ok(cache::node_providers(&target, &names))
}

pub(crate) fn update_cached_node_delay(target: &MihomoTarget, name: &str, delay: i32) {
    cache::update_node_delays(target, [(name, delay)]);
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn update_cached_node_delay_window(
    target: &MihomoTarget,
    group: &str,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    _window_members_hash: u32,
    name: &str,
    delay: i32,
) -> Option<(bool, Vec<ProxyMemberEntry>)> {
    if window_limit == 0 {
        update_cached_node_delay(target, name, delay);
        return None;
    }
    let before = cache::member_entries(target, group, window_offset, window_limit, member_sort)
        .unwrap_or_default();
    let visible_delay_changed = before
        .iter()
        .find(|entry| entry.name == name)
        .is_some_and(|entry| entry.delay != delay);

    if member_sort != ProxyMemberSort::Delay {
        update_cached_node_delay(target, name, delay);
        return visible_delay_changed.then(|| (true, Vec::new()));
    }

    update_cached_node_delay(target, name, delay);
    let after = cache::member_entries(target, group, window_offset, window_limit, member_sort)
        .unwrap_or_default();
    if same_member_order(&before, &after) {
        visible_delay_changed.then(|| (true, Vec::new()))
    } else {
        Some((false, after))
    }
}

pub(crate) fn update_cached_node_delays<'a>(
    target: &MihomoTarget,
    delays: impl IntoIterator<Item = (&'a str, i32)>,
) {
    cache::update_node_delays(target, delays);
}

fn same_member_order(a: &[ProxyMemberEntry], b: &[ProxyMemberEntry]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(a, b)| a.name == b.name)
}

fn group_order(
    a_pos: &usize,
    a: &ProxyGroupEntry,
    b_pos: &usize,
    b: &ProxyGroupEntry,
    group_positions: &HashMap<&str, usize>,
) -> std::cmp::Ordering {
    match (a.name == "GLOBAL", b.name == "GLOBAL") {
        (true, true) => return a_pos.cmp(b_pos),
        (true, false) => return std::cmp::Ordering::Greater,
        (false, true) => return std::cmp::Ordering::Less,
        (false, false) => {}
    }

    let ai = group_positions.get(a.name.as_str()).copied();
    let bi = group_positions.get(b.name.as_str()).copied();
    match (ai, bi) {
        (Some(ai), Some(bi)) => ai.cmp(&bi).then(a_pos.cmp(b_pos)),
        (Some(_), None) => std::cmp::Ordering::Less,
        (None, Some(_)) => std::cmp::Ordering::Greater,
        (None, None) => a_pos.cmp(b_pos),
    }
}
