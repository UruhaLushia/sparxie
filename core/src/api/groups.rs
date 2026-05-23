use crate::error::MihomoError;

use super::{MihomoTarget, urlencode};

/// `GET /group` — only proxy groups, in stable order.
pub async fn groups(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target.client()?.get_json("group").await?.to_string())
}

/// `GET /group/{name}/delay` — runs a parallel URL test for every node in the
/// group and returns the resulting `{node: delay_ms}` map as a JSON string.
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
) -> Result<String, MihomoError> {
    let mut path = format!(
        "group/{}/delay?url={}&timeout={}",
        urlencode(&group),
        urlencode(&test_url),
        timeout_ms,
    );
    if let Some(expected) = expected_status {
        if !expected.is_empty() {
            path.push_str(&format!("&expected={}", urlencode(&expected)));
        }
    }
    Ok(target.client()?.get_json(&path).await?.to_string())
}
