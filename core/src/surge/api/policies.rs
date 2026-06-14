use std::collections::HashMap;

use serde_json::json;

use crate::MihomoError;
use crate::backend::api::{
    GroupDelayEntry, ProxyCatalog, ProxyDelayEntry, ProxyDelayEvent, ProxyGroupEntry,
    ProxyMemberEntry, ProxyMemberSort,
};
use crate::surge::client::SurgeTarget;

mod cache;
mod delay;
mod parse;

use cache::{
    cached_group_members, cached_member_delay, cached_members_by_name, contains_catalog,
    store_catalog, update_cached_delay, update_cached_delays,
};
use delay::{benchmark_delays, delay_for_member, test_policy_group};
use parse::{
    display_group_type, group_meta, member_hash, policy_group_items, policy_group_order,
    policy_members, selected_policy, sort_members,
};

pub async fn proxy_catalog(
    target: SurgeTarget,
    include_hidden: bool,
    filter: String,
) -> Result<ProxyCatalog, MihomoError> {
    let client = target.client()?;
    let raw = client.get_json("v1/policy_groups").await?;
    let delays = benchmark_delays(&client).await.unwrap_or_default();
    let group_order = policy_group_order(&client).await.unwrap_or_default();
    let needle = filter.trim().to_lowercase();
    let mut groups = Vec::new();
    let mut cached_groups = HashMap::new();

    for item in policy_group_items(&raw) {
        let name = item.name;
        if name.is_empty() {
            continue;
        }
        let members = policy_members(item.value, &delays);
        if members.is_empty() {
            continue;
        }
        let meta = group_meta(&client, &name).await.unwrap_or_default();
        if meta.hidden && !include_hidden {
            continue;
        }
        if !needle.is_empty()
            && !name.to_lowercase().contains(&needle)
            && !members
                .iter()
                .any(|member| member.entry.name.to_lowercase().contains(&needle))
        {
            continue;
        }
        let now = selected_policy(&client, &name).await.unwrap_or_default();
        let names: Vec<String> = members
            .iter()
            .map(|member| member.entry.name.clone())
            .collect();
        let members_hash = member_hash(&names);
        cached_groups.insert(name.clone(), members.clone());
        groups.push(ProxyGroupEntry {
            name,
            proxy_type: display_group_type(&meta.group_type, meta.selectable),
            selectable: meta.selectable,
            icon: meta.icon,
            member_count: members.len().min(u32::MAX as usize) as u32,
            members_hash,
            now,
            test_url: String::new(),
            fixed: String::new(),
        });
    }

    groups.sort_by(|a, b| {
        group_order
            .get(&a.name)
            .unwrap_or(&usize::MAX)
            .cmp(group_order.get(&b.name).unwrap_or(&usize::MAX))
            .then_with(|| a.name.cmp(&b.name))
    });
    store_catalog(&target, cached_groups);
    Ok(ProxyCatalog {
        groups,
        icon_urls: Vec::new(),
    })
}

pub async fn proxy_group_members(
    target: SurgeTarget,
    group: String,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    ensure_catalog(target.clone()).await?;
    let mut entries = cached_group_members(&target, &group)
        .into_iter()
        .map(|member| member.entry)
        .collect::<Vec<_>>();
    sort_members(&mut entries, member_sort);
    Ok(entries
        .into_iter()
        .skip(offset as usize)
        .take(limit as usize)
        .collect())
}

pub async fn select_proxy(
    target: SurgeTarget,
    group: String,
    name: String,
) -> Result<(), MihomoError> {
    target
        .client()?
        .post_json(
            "v1/policy_groups/select",
            json!({ "group_name": group, "policy": name }),
        )
        .await?;
    Ok(())
}

pub async fn unfix_proxy(_: SurgeTarget, _: String) -> Result<(), MihomoError> {
    Err(MihomoError::Other("Surge 不支持取消固定策略".into()))
}

pub async fn group_delay(
    target: SurgeTarget,
    group: String,
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    let client = target.client()?;
    ensure_catalog(target.clone()).await?;
    let delays = test_policy_group(&target, &client, &group).await?;
    Ok(cached_group_members(&target, &group)
        .into_iter()
        .map(|member| GroupDelayEntry {
            delay: delay_for_member(&member, &delays),
            name: member.entry.name,
        })
        .collect())
}

pub async fn proxy_batch_delay(
    target: SurgeTarget,
    names: Vec<String>,
    test_url: String,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    ensure_catalog(target.clone()).await?;
    let client = target.client()?;
    if !names.is_empty() && !test_url.trim().is_empty() {
        client
            .post_json(
                "v1/policies/test",
                json!({ "policy_names": names, "url": test_url }),
            )
            .await?;
    }
    let delays = benchmark_delays(&client).await?;
    update_cached_delays(&target, &delays);
    let by_name = cached_members_by_name(&target);
    Ok(names
        .into_iter()
        .map(|name| ProxyDelayEntry {
            delay: by_name
                .get(&name)
                .map(|member| delay_for_member(member, &delays))
                .unwrap_or_else(|| delays.get(&name).copied().unwrap_or(-1)),
            name,
        })
        .collect())
}

pub async fn proxy_group_batch_delay(
    target: SurgeTarget,
    group: String,
    _test_url: String,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    ensure_catalog(target.clone()).await?;
    let client = target.client()?;
    let delays = test_policy_group(&target, &client, &group).await?;
    Ok(cached_group_members(&target, &group)
        .into_iter()
        .map(|member| ProxyDelayEntry {
            delay: delay_for_member(&member, &delays),
            name: member.entry.name,
        })
        .collect())
}

#[allow(clippy::too_many_arguments)]
pub async fn proxy_delay_window(
    target: SurgeTarget,
    group: String,
    name: String,
    test_url: String,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    window_members_hash: u32,
) -> Result<ProxyDelayEvent, MihomoError> {
    ensure_catalog(target.clone()).await?;
    let delay = if test_url.trim().is_empty() {
        cached_member_delay(&target, &group, &name)
    } else {
        let client = target.client()?;
        let delays = test_policy_group(&target, &client, &group).await?;
        cached_group_members(&target, &group)
            .into_iter()
            .find(|member| member.entry.name == name)
            .map(|member| delay_for_member(&member, &delays))
            .unwrap_or_else(|| delays.get(&name).copied().unwrap_or(-1))
    };
    update_cached_delay(&target, &name, delay);
    let window_entries =
        proxy_group_members(target, group, window_offset, window_limit, member_sort).await?;
    Ok(ProxyDelayEvent {
        name,
        delay,
        window_offset,
        window_members_hash,
        window_entries,
    })
}

async fn ensure_catalog(target: SurgeTarget) -> Result<(), MihomoError> {
    if contains_catalog(&target) {
        return Ok(());
    }
    let _ = proxy_catalog(target, true, String::new()).await?;
    Ok(())
}
