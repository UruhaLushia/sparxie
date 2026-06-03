use crate::MihomoError;

use super::backend::{BackendKind, probe_with_client};
use super::proxies::delay::proxy_group_batch_delay;
use super::{MihomoTarget, urlencode};

#[derive(Clone, Debug, Default)]
pub struct GroupDelayEntry {
    pub name: String,
    pub delay: i32,
}

/// `GET /group` — only proxy groups, in stable order.
pub async fn groups(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target.client()?.get_json("group").await?.to_string())
}

/// Test every node in a group. Mihomo uses `/group/{name}/delay`; Stash falls
/// back to concurrent `/proxies/{node}/delay` calls because it has no `/group`.
///
/// **Side effect (mihomo behavior):** for non-Selector groups (URLTest,
/// Fallback, etc.) the call clears the persisted "fixed" selection before
/// running the test.
pub async fn group_delay(
    target: MihomoTarget,
    group: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: Option<u32>,
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    let client = target.client()?;
    if probe_with_client(&client).await?.kind == BackendKind::Stash {
        return concurrent_group_delay(
            target,
            group,
            test_url,
            timeout_ms,
            expected_status,
            concurrency,
        )
        .await;
    }

    let mut path = format!(
        "group/{}/delay?url={}&timeout={}",
        urlencode(&group),
        urlencode(&test_url),
        timeout_ms,
    );
    if let Some(expected) = expected_status.as_deref()
        && !expected.is_empty()
    {
        path.push_str(&format!("&expected={}", urlencode(expected)));
    }
    let raw = match client.get_json(&path).await {
        Ok(raw) => raw,
        Err(MihomoError::Upstream { status: 404, .. }) => {
            return concurrent_group_delay(
                target,
                group,
                test_url,
                timeout_ms,
                expected_status,
                concurrency,
            )
            .await;
        }
        Err(err) => return Err(err),
    };
    let Some(map) = raw.as_object() else {
        return Ok(Vec::new());
    };
    let mut out = Vec::with_capacity(map.len());
    for (name, value) in map {
        out.push(GroupDelayEntry {
            name: name.clone(),
            delay: value_to_i32(value),
        });
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}

async fn concurrent_group_delay(
    target: MihomoTarget,
    group: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: Option<u32>,
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    let delays = proxy_group_batch_delay(
        target,
        group,
        test_url,
        timeout_ms,
        expected_status,
        concurrency.unwrap_or(64),
    )
    .await?;
    Ok(delays
        .into_iter()
        .map(|entry| GroupDelayEntry {
            name: entry.name,
            delay: entry.delay,
        })
        .collect())
}

fn value_to_i32(value: &serde_json::Value) -> i32 {
    if let Some(n) = value.as_i64() {
        return n as i32;
    }
    if let Some(n) = value.as_f64() {
        return n.round() as i32;
    }
    if let Some(s) = value.as_str() {
        return s.parse::<i32>().unwrap_or_default();
    }
    0
}
