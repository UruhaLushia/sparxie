use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use tokio::time::timeout;

use crate::MihomoError;
use crate::backend::api::{
    GroupDelayEntry, ProxyCatalog, ProxyDelayEntry, ProxyDelayEvent, ProxyGroupEntry,
    ProxyMemberEntry, ProxyMemberSort,
};
use crate::sing_box::client::{SingBoxTarget, target_key};
use crate::sing_box::proto::daemon::{Groups, SelectOutboundRequest, UrlTestRequest};

type MemberCache = HashMap<String, Vec<ProxyMemberEntry>>;

fn cache() -> &'static Mutex<HashMap<String, (String, MemberCache)>> {
    static C: OnceLock<Mutex<HashMap<String, (String, MemberCache)>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(HashMap::new()))
}

pub async fn proxy_catalog(
    target: SingBoxTarget,
    _include_hidden: bool,
    filter: String,
) -> Result<ProxyCatalog, MihomoError> {
    let groups = fetch_groups(&target).await?;
    Ok(catalog_from_groups(&target, groups, filter))
}

pub async fn proxy_group_members(
    target: SingBoxTarget,
    group: String,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    ensure_catalog(target.clone()).await?;
    let mut entries = cached_group_members(&target, &group);
    sort_members(&mut entries, member_sort);
    Ok(entries
        .into_iter()
        .skip(offset as usize)
        .take(limit as usize)
        .collect())
}

pub async fn select_proxy(
    target: SingBoxTarget,
    group: String,
    name: String,
) -> Result<(), MihomoError> {
    target
        .client()
        .await?
        .select_outbound(SelectOutboundRequest {
            group_tag: group,
            outbound_tag: name,
        })
        .await?;
    Ok(())
}

pub async fn unfix_proxy(_: SingBoxTarget, _: String) -> Result<(), MihomoError> {
    Err(MihomoError::Other("sing-box 不支持取消固定出站".into()))
}

pub async fn group_delay(
    target: SingBoxTarget,
    group: String,
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    let groups = url_test_group(&target, &group).await?;
    let _ = catalog_from_groups(&target, groups, cached_filter(&target));
    Ok(cached_group_members(&target, &group)
        .into_iter()
        .map(|entry| GroupDelayEntry {
            name: entry.name,
            delay: entry.delay,
        })
        .collect())
}

pub async fn proxy_batch_delay(
    target: SingBoxTarget,
    names: Vec<String>,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    ensure_catalog(target.clone()).await?;
    let by_name = cached_members_by_name(&target);
    Ok(names
        .into_iter()
        .map(|name| ProxyDelayEntry {
            delay: by_name.get(&name).copied().unwrap_or(-1),
            name,
        })
        .collect())
}

pub async fn proxy_group_batch_delay(
    target: SingBoxTarget,
    group: String,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    let _ = group_delay(target.clone(), group.clone()).await?;
    Ok(cached_group_members(&target, &group)
        .into_iter()
        .map(|entry| ProxyDelayEntry {
            name: entry.name,
            delay: entry.delay,
        })
        .collect())
}

#[allow(clippy::too_many_arguments)]
pub async fn proxy_delay_window(
    target: SingBoxTarget,
    group: String,
    name: String,
    run_test: bool,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    window_members_hash: u32,
) -> Result<ProxyDelayEvent, MihomoError> {
    if run_test {
        let _ = group_delay(target.clone(), group.clone()).await?;
    } else {
        ensure_catalog(target.clone()).await?;
    }
    let delay = cached_group_members(&target, &group)
        .into_iter()
        .find(|entry| entry.name == name)
        .map(|entry| entry.delay)
        .unwrap_or(-1);
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

async fn fetch_groups(target: &SingBoxTarget) -> Result<Groups, MihomoError> {
    let mut stream = target
        .client()
        .await?
        .subscribe_groups(())
        .await?
        .into_inner();
    stream
        .message()
        .await?
        .ok_or_else(|| MihomoError::Other("sing-box groups stream ended".into()))
}

async fn url_test_group(target: &SingBoxTarget, group: &str) -> Result<Groups, MihomoError> {
    let mut client = target.client().await?;
    let mut stream = client.subscribe_groups(()).await?.into_inner();
    let initial = stream.message().await?.unwrap_or_default();
    client
        .url_test(UrlTestRequest {
            outbound_tag: group.to_string(),
        })
        .await?;
    match timeout(Duration::from_secs(30), stream.message()).await {
        Ok(Ok(Some(groups))) => Ok(groups),
        _ => Ok(initial),
    }
}

fn catalog_from_groups(target: &SingBoxTarget, groups: Groups, filter: String) -> ProxyCatalog {
    let needle = filter.trim().to_lowercase();
    let mut out = Vec::new();
    let mut cached = HashMap::new();
    for group in groups.group {
        let name_matches = needle.is_empty() || group.tag.to_lowercase().contains(&needle);
        let now = group.selected.clone();
        let now_delay = group
            .items
            .iter()
            .find(|item| item.tag.as_str() == now.as_str())
            .map(|item| {
                if item.url_test_delay <= 0 {
                    -1
                } else {
                    item.url_test_delay
                }
            })
            .unwrap_or(-1);
        let members = group
            .items
            .into_iter()
            .filter(|item| name_matches || item.tag.to_lowercase().contains(&needle))
            .map(|item| ProxyMemberEntry {
                name: item.tag,
                proxy_type: item.r#type,
                delay: if item.url_test_delay <= 0 {
                    -1
                } else {
                    item.url_test_delay
                },
            })
            .collect::<Vec<_>>();
        if !needle.is_empty() && members.is_empty() {
            continue;
        }
        let names = members
            .iter()
            .map(|member| member.name.clone())
            .collect::<Vec<_>>();
        cached.insert(group.tag.clone(), members);
        out.push(ProxyGroupEntry {
            name: group.tag,
            proxy_type: if group.selectable {
                "Selector".into()
            } else {
                group.r#type
            },
            selectable: group.selectable,
            member_count: names.len().min(u32::MAX as usize) as u32,
            members_hash: member_hash(&names),
            now,
            now_delay,
            ..Default::default()
        });
    }
    cache()
        .lock()
        .expect("sing-box proxy cache poisoned")
        .insert(target_key(target), (needle, cached));
    ProxyCatalog {
        groups: out,
        icon_urls: Vec::new(),
    }
}

async fn ensure_catalog(target: SingBoxTarget) -> Result<(), MihomoError> {
    if cache()
        .lock()
        .expect("sing-box proxy cache poisoned")
        .contains_key(&target_key(&target))
    {
        return Ok(());
    }
    let _ = proxy_catalog(target, true, String::new()).await?;
    Ok(())
}

fn cached_filter(target: &SingBoxTarget) -> String {
    cache()
        .lock()
        .expect("sing-box proxy cache poisoned")
        .get(&target_key(target))
        .map(|(filter, _)| filter.clone())
        .unwrap_or_default()
}

fn cached_group_members(target: &SingBoxTarget, group: &str) -> Vec<ProxyMemberEntry> {
    cache()
        .lock()
        .expect("sing-box proxy cache poisoned")
        .get(&target_key(target))
        .and_then(|(_, groups)| groups.get(group).cloned())
        .unwrap_or_default()
}

fn cached_members_by_name(target: &SingBoxTarget) -> HashMap<String, i32> {
    cache()
        .lock()
        .expect("sing-box proxy cache poisoned")
        .get(&target_key(target))
        .map(|(_, groups)| {
            groups
                .values()
                .flatten()
                .map(|entry| (entry.name.clone(), entry.delay))
                .collect()
        })
        .unwrap_or_default()
}

fn sort_members(entries: &mut [ProxyMemberEntry], sort: ProxyMemberSort) {
    match sort {
        ProxyMemberSort::Original => {}
        ProxyMemberSort::Name => entries.sort_by(|a, b| a.name.cmp(&b.name)),
        ProxyMemberSort::Delay => entries.sort_by(|a, b| {
            let ad = if a.delay < 0 { i32::MAX } else { a.delay };
            let bd = if b.delay < 0 { i32::MAX } else { b.delay };
            ad.cmp(&bd).then_with(|| a.name.cmp(&b.name))
        }),
    }
}

fn member_hash(names: &[String]) -> u32 {
    let mut hash: u32 = 2166136261;
    for name in names {
        for byte in name.as_bytes() {
            hash ^= *byte as u32;
            hash = hash.wrapping_mul(16777619);
        }
        hash ^= 0xff;
        hash = hash.wrapping_mul(16777619);
    }
    hash
}
