use std::collections::HashSet;

use crate::MihomoError;
use crate::backend::api::{GroupDelayEntry, ProxyDelayEntry};
use crate::surge_controller::api::command_ok;
use crate::surge_controller::client::SurgeControllerTarget;

use super::catalog;

pub async fn group_delay(
    target: SurgeControllerTarget,
    group: String,
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    test_group(&target, &group).await?;
    catalog::refresh(target.clone()).await?;
    Ok(catalog::members(&target, &group)
        .into_iter()
        .map(|member| GroupDelayEntry {
            delay: member.delay,
            name: member.name,
        })
        .collect())
}

pub async fn proxy_batch_delay(
    target: SurgeControllerTarget,
    names: Vec<String>,
    _test_url: String,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    catalog::ensure(target.clone()).await?;
    let mut remaining = names.iter().cloned().collect::<HashSet<_>>();
    let mut candidates = catalog::delay_candidates(&target, &remaining);
    candidates.sort_by_key(|(_, member_count, _)| *member_count);
    for (group, _, covered) in candidates {
        if !covered.iter().any(|name| remaining.contains(name)) {
            continue;
        }
        test_group(&target, &group).await?;
        for name in covered {
            remaining.remove(&name);
        }
        if remaining.is_empty() {
            break;
        }
    }
    if !remaining.is_empty() {
        return Err(MihomoError::Other(format!(
            "Surge 控制器未提供 {} 个节点所属的可测速策略组",
            remaining.len()
        )));
    }
    catalog::refresh(target.clone()).await?;
    let cached = catalog::delays_by_name(&target);
    Ok(names
        .into_iter()
        .map(|name| ProxyDelayEntry {
            delay: cached.get(&name).copied().unwrap_or(-1),
            name,
        })
        .collect())
}

pub async fn proxy_group_batch_delay(
    target: SurgeControllerTarget,
    group: String,
    _test_url: String,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    Ok(group_delay(target, group)
        .await?
        .into_iter()
        .map(|entry| ProxyDelayEntry {
            name: entry.name,
            delay: entry.delay,
        })
        .collect())
}

async fn test_group(target: &SurgeControllerTarget, group: &str) -> Result<(), MihomoError> {
    command_ok(target, ["test-group", group]).await
}
