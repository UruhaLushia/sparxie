use crate::MihomoError;

use super::MihomoTarget;

#[derive(Clone, Debug, Default)]
pub struct VersionInfo {
    pub version: String,
    pub is_cmfa: bool,
}

/// `GET /version` → `{version, meta}`.
pub async fn version(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target.client()?.get_json("version").await?.to_string())
}

pub async fn version_info(target: MihomoTarget) -> Result<VersionInfo, MihomoError> {
    let raw = target.client()?.get_json("version").await?;
    let version = raw
        .get("version")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string();
    Ok(VersionInfo {
        is_cmfa: version.to_lowercase().contains("cmfa"),
        version,
    })
}
