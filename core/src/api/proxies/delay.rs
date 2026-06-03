use futures_util::{StreamExt, stream};

use crate::MihomoError;
use crate::api::{MihomoTarget, urlencode};
use crate::client::MihomoClient;
use crate::frb_generated::StreamSink;

use super::catalog::{ProxyMemberEntry, ProxyMemberSort};
use super::catalog::{
    cached_group_member_names, update_cached_node_delay, update_cached_node_delay_window,
    update_cached_node_delays,
};
use super::value::value_to_i32;

#[derive(Clone, Debug, Default)]
pub struct ProxyDelayEntry {
    pub name: String,
    pub delay: i32,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyDelayEvent {
    pub name: String,
    pub delay: i32,
    pub window_offset: u32,
    pub window_members_hash: u32,
    pub window_entries: Vec<ProxyMemberEntry>,
}

/// `GET /proxies/{name}/delay` — returns the measured delay in ms, or `0` if
/// upstream returned non-success without an HTTP body. `expected_status`
/// follows mihomo's range syntax, e.g. `"200/204/301-302"`.
pub async fn proxy_delay(
    target: MihomoTarget,
    name: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
) -> Result<i64, MihomoError> {
    let client = target.client()?;
    let result = proxy_delay_with_client(
        &client,
        &name,
        &test_url,
        timeout_ms,
        expected_status.as_deref(),
    )
    .await;
    match result {
        Ok(delay) => {
            update_cached_node_delay(&target, &name, delay);
            Ok(delay as i64)
        }
        Err(err) => {
            update_cached_node_delay(&target, &name, 0);
            Err(err)
        }
    }
}

/// Batch variant of [`proxy_delay`]. Individual node failures are reported as
/// `0` (timeout), matching the existing UI behavior for one-off node tests.
pub async fn proxy_batch_delay(
    target: MihomoTarget,
    names: Vec<String>,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: u32,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    let client = target.client()?;
    let concurrency = concurrency.clamp(1, 512) as usize;
    let expected_status = expected_status.filter(|s| !s.is_empty());
    let mut out = stream::iter(names)
        .map(|name| {
            let client = &client;
            let test_url = test_url.as_str();
            let expected_status = expected_status.as_deref();
            async move {
                let delay =
                    proxy_delay_with_client(client, &name, test_url, timeout_ms, expected_status)
                        .await
                        .unwrap_or_default();
                ProxyDelayEntry { name, delay }
            }
        })
        .buffer_unordered(concurrency)
        .collect::<Vec<_>>()
        .await;
    out.sort_by(|a, b| a.name.cmp(&b.name));
    update_cached_node_delays(
        &target,
        out.iter().map(|entry| (entry.name.as_str(), entry.delay)),
    );
    Ok(out)
}

/// Batch delay test for every cached member of one group. The member list stays
/// in Rust; Dart only receives the delay results.
pub async fn proxy_group_batch_delay(
    target: MihomoTarget,
    group: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: u32,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    let names = cached_group_member_names(target.clone(), &group).await?;
    proxy_batch_delay(
        target,
        names,
        test_url,
        timeout_ms,
        expected_status,
        concurrency,
    )
    .await
}

/// Concurrent group delay test that emits each node as soon as it finishes.
#[allow(clippy::too_many_arguments)]
pub async fn proxy_group_delay_stream(
    target: MihomoTarget,
    group: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: u32,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    window_members_hash: u32,
    sink: StreamSink<ProxyDelayEvent>,
) -> Result<(), MihomoError> {
    let names = cached_group_member_names(target.clone(), &group).await?;
    let client = target.client()?;
    let concurrency = concurrency.clamp(1, 512) as usize;
    let expected_status = expected_status.filter(|s| !s.is_empty());
    let mut stream = stream::iter(names)
        .map(|name| {
            let client = &client;
            let test_url = test_url.as_str();
            let expected_status = expected_status.as_deref();
            async move {
                let delay =
                    proxy_delay_with_client(client, &name, test_url, timeout_ms, expected_status)
                        .await
                        .unwrap_or_default();
                ProxyDelayEntry { name, delay }
            }
        })
        .buffer_unordered(concurrency);

    while let Some(entry) = stream.next().await {
        let Some((visible_delay, window_entries)) = update_cached_node_delay_window(
            &target,
            &group,
            member_sort,
            window_offset,
            window_limit,
            window_members_hash,
            &entry.name,
            entry.delay,
        ) else {
            continue;
        };
        if sink
            .add(ProxyDelayEvent {
                name: if visible_delay {
                    entry.name
                } else {
                    String::new()
                },
                delay: if visible_delay { entry.delay } else { -1 },
                window_offset,
                window_members_hash,
                window_entries,
            })
            .is_err()
        {
            break;
        }
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub async fn proxy_delay_window(
    target: MihomoTarget,
    group: String,
    name: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    window_members_hash: u32,
) -> Result<ProxyDelayEvent, MihomoError> {
    let client = target.client()?;
    let delay = proxy_delay_with_client(
        &client,
        &name,
        &test_url,
        timeout_ms,
        expected_status.as_deref(),
    )
    .await
    .unwrap_or_default();
    let Some((visible_delay, window_entries)) = update_cached_node_delay_window(
        &target,
        &group,
        member_sort,
        window_offset,
        window_limit,
        window_members_hash,
        &name,
        delay,
    ) else {
        return Ok(ProxyDelayEvent::default());
    };
    Ok(ProxyDelayEvent {
        name: if visible_delay { name } else { String::new() },
        delay: if visible_delay { delay } else { -1 },
        window_offset,
        window_members_hash,
        window_entries,
    })
}

async fn proxy_delay_with_client(
    client: &MihomoClient,
    name: &str,
    test_url: &str,
    timeout_ms: u32,
    expected_status: Option<&str>,
) -> Result<i32, MihomoError> {
    let mut path = format!(
        "proxies/{}/delay?url={}&timeout={}",
        urlencode(name),
        urlencode(test_url),
        timeout_ms,
    );
    if let Some(expected) = expected_status
        && !expected.is_empty()
    {
        path.push_str(&format!("&expected={}", urlencode(expected)));
    }
    let v = client.get_json(&path).await?;
    Ok(v.get("delay").map(value_to_i32).unwrap_or_default())
}
