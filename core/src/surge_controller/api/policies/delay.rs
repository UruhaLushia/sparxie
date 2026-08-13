use std::collections::HashSet;

use serde_json::Value;

use crate::MihomoError;
use crate::backend::api::{GroupDelayEntry, ProxyDelayEntry};
use crate::surge_controller::client::SurgeControllerTarget;
use crate::surge_controller::state::benchmark;

use super::catalog;

pub async fn group_delay(
    target: SurgeControllerTarget,
    group: String,
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    let keys = catalog::group_test_keys(target.clone(), &group).await?;
    benchmark::test_group(&target, &group, &keys).await?;
    catalog::refresh(target.clone()).await?;
    Ok(catalog::members(&target, &group)
        .into_iter()
        .map(|member| GroupDelayEntry {
            delay: member.delay,
            name: member.name,
        })
        .collect())
}

pub async fn proxy_delay(target: SurgeControllerTarget, name: String) -> Result<i32, MihomoError> {
    let key = catalog::member_test_key(target.clone(), &name).await?;
    let mut connection = target.connect().await?;
    let raw = connection.request(["test-policy", key.as_str()]).await?;
    let delay = policy_delay(&raw, &name, &key).unwrap_or(-1);
    benchmark::update_policy(&target, key.clone(), delay);
    catalog::update_delay(&target, key, delay);
    Ok(delay)
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
        let keys = catalog::group_test_keys(target.clone(), &group).await?;
        benchmark::test_group(&target, &group, &keys).await?;
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

fn policy_delay(raw: &Value, name: &str, key: &str) -> Option<i32> {
    let result = raw
        .get(name)
        .or_else(|| raw.get(key))
        .or_else(|| raw.as_object()?.values().next())?;
    result
        .get("receive")
        .and_then(Value::as_i64)
        .and_then(|delay| i32::try_from(delay).ok())
        .map(|delay| if delay > 0 { delay } else { 0 })
}
