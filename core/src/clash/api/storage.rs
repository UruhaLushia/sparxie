use reqwest::Method;
use serde_json::Value;

use crate::MihomoError;

use super::{MihomoTarget, urlencode};

/// `GET /storage/{key}` — returns a JSON value, or the literal string
/// `"null"` when the key has never been written.
pub async fn storage_get(target: MihomoTarget, key: String) -> Result<String, MihomoError> {
    Ok(target
        .client()?
        .get_json(&format!("storage/{}", urlencode(&key)))
        .await?
        .to_string())
}

/// `PUT /storage/{key}` — store a JSON value. mihomo enforces a 1 MiB cap and
/// rejects bodies that aren't valid JSON.
pub async fn storage_set(
    target: MihomoTarget,
    key: String,
    value_json: String,
) -> Result<(), MihomoError> {
    let value: Value = serde_json::from_str(&value_json)?;
    target
        .client()?
        .forward(
            Method::PUT,
            &format!("storage/{}", urlencode(&key)),
            Some(value),
        )
        .await?;
    Ok(())
}

/// `DELETE /storage/{key}` — remove a key (always 204 even if absent).
pub async fn storage_delete(target: MihomoTarget, key: String) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::DELETE,
            &format!("storage/{}", urlencode(&key)),
            None,
        )
        .await?;
    Ok(())
}
