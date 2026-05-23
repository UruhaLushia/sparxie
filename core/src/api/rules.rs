use reqwest::Method;
use serde_json::{Value, json};

use crate::error::MihomoError;
use crate::regex_util;

use super::MihomoTarget;

/// `GET /rules` — full ruleset. Optional regex filters apply to `payload`,
/// `proxy`, and `type`. `limit` truncates the resulting array.
pub async fn rules(
    target: MihomoTarget,
    payload_pattern: Option<String>,
    proxy_pattern: Option<String>,
    type_pattern: Option<String>,
    limit: Option<u32>,
) -> Result<String, MihomoError> {
    let mut raw = target.client()?.get_json("rules").await?;
    let payload = regex_util::compile(payload_pattern.as_deref())?;
    let proxy = regex_util::compile(proxy_pattern.as_deref())?;
    let ty = regex_util::compile(type_pattern.as_deref())?;
    let limit = limit.unwrap_or(0) as usize;

    let mut total_after = 0;
    if let Some(arr) = raw.get_mut("rules").and_then(|v| v.as_array_mut()) {
        arr.retain(|item| {
            let p = item.get("payload").and_then(|v| v.as_str()).unwrap_or("");
            let pr = item.get("proxy").and_then(|v| v.as_str()).unwrap_or("");
            let t = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
            payload.as_ref().is_none_or(|re| re.is_match(p))
                && proxy.as_ref().is_none_or(|re| re.is_match(pr))
                && ty.as_ref().is_none_or(|re| re.is_match(t))
        });
        if limit > 0 && arr.len() > limit {
            arr.truncate(limit);
        }
        total_after = arr.len();
    }
    if let Some(obj) = raw.as_object_mut() {
        obj.insert("count".into(), json!(total_after));
    }
    Ok(raw.to_string())
}

/// `PATCH /rules/disable` — toggle individual rules by their index. Body is
/// `{<index>: bool}`. The mihomo upstream rejects this when started with
/// `--embed`; callers should treat 404 as a feature gate, not a bug.
pub async fn rules_disable(
    target: MihomoTarget,
    indices_json: String,
) -> Result<(), MihomoError> {
    let body: Value = serde_json::from_str(&indices_json)?;
    target
        .client()?
        .forward(Method::PATCH, "rules/disable", Some(body))
        .await?;
    Ok(())
}
