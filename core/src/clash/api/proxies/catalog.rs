use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::MihomoError;
use crate::clash::api::MihomoTarget;
use crate::utils::text::contains_filter;

use super::value::{field_or, first_field, proxy_delay};
use cache::{CachedCatalog, CachedGroup, CachedNode};
use parse::{intern_member_list, push_icon};
pub use types::{
    ProxyCatalog, ProxyGroupEntry, ProxyMemberEntry, ProxyMemberSection, ProxyMemberSort,
    ProxyMemberWindow,
};

mod cache;
mod member_window;
mod node_state;
mod parse;
mod types;

pub(crate) use member_window::cached_group_member_names;
pub use member_window::{proxy_group_member_window, proxy_group_members};
use node_state::cached_node;
pub(crate) use node_state::{
    cache_proxy_detail, cached_node_providers, cached_proxy_detail, refresh_cached_node_detail,
    update_cached_node_delay, update_cached_node_delay_window, update_cached_node_delays,
};

const PROVIDER_NODES_REFRESH_INTERVAL: Duration = Duration::from_secs(5 * 60);

pub(crate) fn clear_proxy_catalog_cache(target: &MihomoTarget) {
    cache::clear_catalog(target);
}

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
    let cache_token = cache::begin_catalog_load(&target);
    let previous_provider_nodes_checked_at = cache::provider_nodes_checked_at(&target);
    let refresh_provider_nodes = provider_nodes_are_stale(previous_provider_nodes_checked_at);
    let force_provider_refresh =
        refresh_provider_nodes && previous_provider_nodes_checked_at.is_some();
    let provider_request = async {
        if refresh_provider_nodes {
            provider_nodes(&target, force_provider_refresh).await.ok()
        } else {
            None
        }
    };
    let (raw, fresh_provider_nodes) = tokio::join!(client.get_json("proxies"), provider_request);
    let raw = match raw {
        Ok(raw) => raw,
        Err(error) => {
            cache::finish_catalog_load(&target, cache_token);
            return Err(error);
        }
    };
    let Some(proxies) = raw.get("proxies").and_then(Value::as_object) else {
        cache::finish_catalog_load(&target, cache_token);
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
        let now_delay = top_level_node.map(proxy_delay).unwrap_or(-1);
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

    let provider_nodes_checked_at = if fresh_provider_nodes.is_some() {
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
    let missing_delays: HashSet<&str> = groups
        .iter()
        .filter(|(_, group)| group.now_delay < 0 && !group.now.is_empty())
        .map(|(_, group)| group.now.as_str())
        .collect();
    let previous_delays = cache::node_delays(&target, &missing_delays);
    drop(missing_delays);
    for (_, group) in &mut groups {
        if group.now_delay < 0
            && let Some(delay) = previous_delays.get(group.now.as_str())
        {
            group.now_delay = *delay;
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
        names[id as usize] = name;
    }
    let mut nodes = Vec::with_capacity(names.len());
    for name in &names {
        nodes.push(proxies.get(name).map(cached_node).or_else(|| {
            fresh_provider_nodes
                .as_ref()
                .and_then(|nodes| nodes.summaries.get(name))
                .cloned()
        }));
    }
    cache::replace_catalog(
        &target,
        cache_token,
        CachedCatalog {
            names,
            lower_names: None,
            nodes,
            groups: cached_groups,
            direct_details: Default::default(),
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
}

async fn provider_nodes(target: &MihomoTarget, force: bool) -> Result<ProviderNodes, MihomoError> {
    let data = crate::clash::api::providers::proxy_provider_data(target.clone(), force).await?;
    let mut summaries = HashMap::new();
    data.for_each_node(|provider, node| {
        summaries.insert(
            node.name.to_string(),
            CachedNode {
                proxy_type: node.proxy_type.clone(),
                delay: node.delay.load(std::sync::atomic::Ordering::Relaxed),
                provider: Some(Box::from(
                    node.provider_override.as_deref().unwrap_or(provider),
                )),
            },
        );
    });
    Ok(ProviderNodes { summaries })
}

fn provider_nodes_are_stale(checked_at: Option<Instant>) -> bool {
    checked_at.is_none_or(|checked_at| checked_at.elapsed() >= PROVIDER_NODES_REFRESH_INTERVAL)
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
