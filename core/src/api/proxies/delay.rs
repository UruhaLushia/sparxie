use futures_util::{StreamExt, stream};

use crate::MihomoError;
use crate::api::{MihomoTarget, urlencode};
use crate::client::MihomoClient;

use super::catalog::cached_group_member_names;
use super::value::value_to_i32;

#[derive(Clone, Debug, Default)]
pub struct ProxyDelayEntry {
    pub name: String,
    pub delay: i32,
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
    Ok(proxy_delay_with_client(
        &client,
        &name,
        &test_url,
        timeout_ms,
        expected_status.as_deref(),
    )
    .await? as i64)
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
    let names = cached_group_member_names(target.clone(), group).await?;
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
