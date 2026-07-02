use std::borrow::Cow;
use std::collections::{HashMap, HashSet};

use serde_json::Value;

use crate::MihomoError;
use crate::clash::api::MihomoTarget;

use super::value::{field_or, first_field};

use cache::{CachedCatalog, CachedGroup, CachedNode};
use parse::{history_delay, intern_member_list, member_count, proxy_group_matches, push_icon};
pub use types::{ProxyCatalog, ProxyGroupEntry, ProxyMemberEntry, ProxyMemberSort};

mod cache;
mod parse;
mod types;

/// Structured proxy + group catalog. Rust parses mihomo's `/proxies`, applies
/// hidden-group filtering, preserves UI ordering (`GLOBAL.all`), caches full
/// group members in Rust, and returns only group summaries to Dart.
pub async fn proxy_catalog(
    target: MihomoTarget,
    include_hidden: bool,
    filter: String,
) -> Result<ProxyCatalog, MihomoError> {
    let client = target.client()?;
    let raw = client.get_json("proxies").await?;
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
        let member_count = member_count(all);
        if member_count == 0 {
            continue;
        }
        let hidden = data.get("hidden").and_then(Value::as_bool).unwrap_or(false);
        if hidden && !include_hidden {
            continue;
        }
        if !proxy_group_matches(name, all, filter.as_ref()) {
            continue;
        }

        let (members, members_hash) = intern_member_list(all, &mut name_ids);
        let icon = field_or(data, "icon", "");
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
                now: field_or(data, "now", ""),
                test_url: first_field(data, &["testUrl", "tester"]),
                fixed: field_or(data, "fixed", ""),
            },
        ));
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
    let previous_nodes = cache::node_details(&target);
    let mut nodes = Vec::with_capacity(names.len());
    for name in &names {
        nodes.push(
            proxies
                .get(name)
                .map(cached_node)
                .or_else(|| previous_nodes.get(name).cloned()),
        );
    }
    cache::replace_catalog(
        &target,
        CachedCatalog {
            names,
            lower_names: None,
            nodes,
            groups: cached_groups,
        },
    );

    Ok(ProxyCatalog {
        groups: groups.into_iter().map(|(_, group)| group).collect(),
        icon_urls,
    })
}

async fn provider_nodes(
    client: &crate::clash::client::MihomoClient,
) -> Result<HashMap<String, CachedNode>, MihomoError> {
    let raw = client.get_json("providers/proxies").await?;
    let mut out = HashMap::new();
    let Some(providers) = raw.get("providers").and_then(Value::as_object) else {
        return Ok(out);
    };
    for provider in providers.values() {
        if field_or(provider, "vehicleType", "") == "Compatible" {
            continue;
        }
        let Some(nodes) = provider.get("proxies").and_then(Value::as_array) else {
            continue;
        };
        for node in nodes {
            let name = field_or(node, "name", "");
            if !name.is_empty() {
                out.insert(name, cached_node(node));
            }
        }
    }
    Ok(out)
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
        let _ = proxy_catalog(target.clone(), true, String::new()).await?;
    }
    if cache::group_needs_provider_nodes(&target, &group) {
        let client = target.client()?;
        if let Ok(nodes) = provider_nodes(&client).await {
            cache::merge_nodes(&target, nodes);
        }
    }
    if let Some(entries) = cache::member_entries(&target, &group, offset, limit, member_sort) {
        return Ok(entries);
    }
    let _ = proxy_catalog(target.clone(), true, String::new()).await?;
    if cache::group_needs_provider_nodes(&target, &group) {
        let client = target.client()?;
        if let Ok(nodes) = provider_nodes(&client).await {
            cache::merge_nodes(&target, nodes);
        }
    }
    Ok(cache::member_entries(&target, &group, offset, limit, member_sort).unwrap_or_default())
}

pub(crate) async fn cached_group_member_names(
    target: MihomoTarget,
    group: &str,
) -> Result<Vec<String>, MihomoError> {
    if !cache::has_catalog(&target) {
        let _ = proxy_catalog(target.clone(), true, String::new()).await?;
    }
    Ok(cache::member_names(&target, group))
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
        let _ = proxy_catalog(target.clone(), true, String::new()).await?;
    }
    if cache::names_need_provider_nodes(&target, &names) {
        let client = target.client()?;
        if let Ok(nodes) = provider_nodes(&client).await {
            cache::merge_nodes(&target, nodes);
        }
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
