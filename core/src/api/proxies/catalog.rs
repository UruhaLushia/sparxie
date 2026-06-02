use std::collections::{HashMap, HashSet};

use serde_json::Value;

use crate::MihomoError;
use crate::api::MihomoTarget;

use super::value::{field_or, first_field, string_list, value_to_i32};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ProxyMemberSort {
    #[default]
    Original,
    Name,
    Delay,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyCatalog {
    pub groups: Vec<ProxyGroupEntry>,
    pub nodes: Vec<ProxyNodeEntry>,
    pub icon_urls: Vec<String>,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyGroupEntry {
    pub name: String,
    pub proxy_type: String,
    pub icon: String,
    pub all: Vec<String>,
    pub now: String,
    pub test_url: String,
    pub fixed: String,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyNodeEntry {
    pub name: String,
    pub proxy_type: String,
    pub icon: String,
    pub delay: i32,
}

/// Structured proxy + group catalog. Rust parses mihomo's `/proxies`, applies
/// hidden-group filtering, preserves UI ordering (`GLOBAL.all`), and returns
/// the node/group index Dart needs.
pub async fn proxy_catalog(
    target: MihomoTarget,
    include_hidden: bool,
    filter: String,
    member_sort: ProxyMemberSort,
) -> Result<ProxyCatalog, MihomoError> {
    let raw = target.client()?.get_json("proxies").await?;
    let Some(proxies) = raw.get("proxies").and_then(Value::as_object) else {
        return Ok(ProxyCatalog::default());
    };

    let mut nodes = Vec::with_capacity(proxies.len());
    let mut groups = Vec::new();
    let mut icon_urls = Vec::new();
    let mut seen_icons = HashSet::new();

    for (name, data) in proxies {
        let proxy_type = field_or(data, "type", "Proxy");
        let icon = field_or(data, "icon", "");
        push_icon(&mut icon_urls, &mut seen_icons, &icon);
        nodes.push(ProxyNodeEntry {
            name: name.clone(),
            proxy_type,
            icon,
            delay: history_delay(data.get("history")),
        });
    }

    let node_delays = if member_sort == ProxyMemberSort::Delay {
        Some(
            nodes
                .iter()
                .map(|node| (node.name.as_str(), node.delay))
                .collect::<HashMap<_, _>>(),
        )
    } else {
        None
    };
    let filter = filter.trim().to_lowercase();
    // Group order comes from the upstream GLOBAL list; member sorting should
    // only affect the displayed members inside each group.
    let global_all = proxies
        .get("GLOBAL")
        .map(|data| string_list(data.get("all")))
        .filter(|all| !all.is_empty());

    for (position, (name, data)) in proxies.iter().enumerate() {
        let mut all = string_list(data.get("all"));
        if all.is_empty() {
            continue;
        }
        let hidden = data.get("hidden").and_then(Value::as_bool).unwrap_or(false);
        if hidden && !include_hidden {
            continue;
        }
        if !proxy_group_matches(name, &all, &filter) {
            continue;
        }
        sort_members(&mut all, member_sort, node_delays.as_ref());
        let icon = field_or(data, "icon", "");
        push_icon(&mut icon_urls, &mut seen_icons, &icon);
        groups.push((
            position,
            ProxyGroupEntry {
                name: name.clone(),
                proxy_type: field_or(data, "type", "Selector"),
                icon,
                all,
                now: field_or(data, "now", ""),
                test_url: first_field(data, &["testUrl", "tester"]),
                fixed: field_or(data, "fixed", ""),
            },
        ));
    }

    let group_positions: HashMap<&str, usize> = global_all
        .as_ref()
        .map(|names| {
            names
                .iter()
                .enumerate()
                .map(|(i, name)| (name.as_str(), i))
                .collect()
        })
        .unwrap_or_default();

    groups.sort_by(|(a_pos, a), (b_pos, b)| {
        let a_is_global = a.name == "GLOBAL";
        let b_is_global = b.name == "GLOBAL";
        match (a_is_global, b_is_global) {
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
    });

    Ok(ProxyCatalog {
        groups: groups.into_iter().map(|(_, group)| group).collect(),
        nodes,
        icon_urls,
    })
}

fn proxy_group_matches(name: &str, members: &[String], filter: &str) -> bool {
    filter.is_empty()
        || name.to_lowercase().contains(filter)
        || members
            .iter()
            .any(|member| member.to_lowercase().contains(filter))
}

fn sort_members(names: &mut [String], sort: ProxyMemberSort, delays: Option<&HashMap<&str, i32>>) {
    match sort {
        ProxyMemberSort::Original => {}
        ProxyMemberSort::Name => names.sort_by_cached_key(|name| name.to_lowercase()),
        ProxyMemberSort::Delay => {
            let Some(delays) = delays else {
                return;
            };
            names.sort_by_cached_key(|name| {
                (delay_score(delay_of(delays, name)), name.to_lowercase())
            });
        }
    }
}

fn delay_of(delays: &HashMap<&str, i32>, name: &str) -> i32 {
    delays.get(name).copied().unwrap_or(-1)
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

fn push_icon(icon_urls: &mut Vec<String>, seen: &mut HashSet<String>, icon: &str) {
    if !icon.is_empty() && seen.insert(icon.to_string()) {
        icon_urls.push(icon.to_string());
    }
}

fn history_delay(value: Option<&Value>) -> i32 {
    let Some(items) = value.and_then(Value::as_array) else {
        return -1;
    };
    let Some(last) = items.last() else {
        return -1;
    };
    last.get("delay").map(value_to_i32).unwrap_or_default()
}
