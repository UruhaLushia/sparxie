use crate::MihomoError;

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

/// `GET /group/{name}/delay` — runs a parallel URL test for every node in the
/// group and returns the resulting per-node delays.
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
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    let mut path = format!(
        "group/{}/delay?url={}&timeout={}",
        urlencode(&group),
        urlencode(&test_url),
        timeout_ms,
    );
    if let Some(expected) = expected_status
        && !expected.is_empty()
    {
        path.push_str(&format!("&expected={}", urlencode(&expected)));
    }
    let raw = target.client()?.get_json(&path).await?;
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
