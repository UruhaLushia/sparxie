use std::borrow::Cow;
use std::collections::{HashMap, HashSet};

use serde_json::Value;

use crate::MihomoError;
use crate::api::MihomoTarget;

use super::value::{field_or, first_field};

use cache::{CachedCatalog, CachedGroup, CachedNode};
use parse::{history_delay, intern_member_list, member_count, proxy_group_matches, push_icon};

mod cache;
mod parse;

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
    pub icon_urls: Vec<String>,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyGroupEntry {
    pub name: String,
    pub proxy_type: String,
    pub icon: String,
    pub member_count: u32,
    pub members_hash: u32,
    pub initial_members: Vec<ProxyMemberEntry>,
    pub now: String,
    pub test_url: String,
    pub fixed: String,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyMemberEntry {
    pub name: String,
    pub proxy_type: String,
    pub delay: i32,
}

/// Structured proxy + group catalog. Rust parses mihomo's `/proxies`, applies
/// hidden-group filtering, preserves UI ordering (`GLOBAL.all`), caches full
/// group members in Rust, and returns only group summaries to Dart.
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

    const INITIAL_MEMBERS_LIMIT: usize = 32;

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
        let initial_member_ids = if member_count <= INITIAL_MEMBERS_LIMIT {
            members.clone()
        } else {
            Vec::new()
        };
        cached_groups.insert(name.clone(), CachedGroup::new(members));
        groups.push((
            position,
            ProxyGroupEntry {
                name: name.clone(),
                proxy_type: field_or(data, "type", "Selector"),
                icon,
                member_count: member_count.min(u32::MAX as usize) as u32,
                members_hash,
                initial_members: Vec::new(),
                now: field_or(data, "now", ""),
                test_url: first_field(data, &["testUrl", "tester"]),
                fixed: field_or(data, "fixed", ""),
            },
            initial_member_ids,
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
    groups
        .sort_by(|(a_pos, a, _), (b_pos, b, _)| group_order(a_pos, a, b_pos, b, &group_positions));

    let mut names = vec![String::new(); name_ids.len()];
    for (name, id) in name_ids {
        names[id] = name;
    }
    let mut nodes = Vec::with_capacity(names.len());
    for name in &names {
        nodes.push(proxies.get(name).map(|data| CachedNode {
            proxy_type: field_or(data, "type", "Proxy"),
            delay: history_delay(data.get("history")),
        }));
    }
    for (_, group, initial_member_ids) in &mut groups {
        if initial_member_ids.is_empty() {
            continue;
        }
        group.initial_members = cache::member_entries_for_ids(
            std::mem::take(initial_member_ids),
            member_sort,
            &names,
            &nodes,
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
        groups: groups.into_iter().map(|(_, group, _)| group).collect(),
        icon_urls,
    })
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
        let _ = proxy_catalog(target.clone(), true, String::new(), member_sort).await?;
    }
    if let Some(entries) = cache::member_entries(&target, &group, offset, limit, member_sort) {
        return Ok(entries);
    }
    let _ = proxy_catalog(target.clone(), true, String::new(), member_sort).await?;
    Ok(cache::member_entries(&target, &group, offset, limit, member_sort).unwrap_or_default())
}

pub(crate) async fn cached_group_member_names(
    target: MihomoTarget,
    group: String,
) -> Result<Vec<String>, MihomoError> {
    if !cache::has_catalog(&target) {
        let _ = proxy_catalog(
            target.clone(),
            true,
            String::new(),
            ProxyMemberSort::Original,
        )
        .await?;
    }
    Ok(cache::member_names(&target, &group))
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
