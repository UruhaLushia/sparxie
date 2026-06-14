use crate::MihomoError;

use super::MihomoTarget;
use super::backend::{BackendKind, probe_with_client};

#[derive(Clone, Debug, Default)]
pub struct VersionInfo {
    pub version: String,
    pub is_cmfa: bool,
    pub is_stash: bool,
    pub supports_core_config: bool,
    pub supports_core_actions: bool,
    pub supports_core_management: bool,
    pub supports_cache_flush: bool,
    pub supports_memory: bool,
}

/// Raw version endpoint, with Stash falling back to `/`.
pub async fn version(target: MihomoTarget) -> Result<String, MihomoError> {
    let client = target.client()?;
    match client.get_json("version").await {
        Ok(raw) => Ok(raw.to_string()),
        Err(MihomoError::Upstream { status: 404, .. }) => {
            Ok(client.get_json("").await?.to_string())
        }
        Err(err) => Err(err),
    }
}

pub async fn version_info(target: MihomoTarget) -> Result<VersionInfo, MihomoError> {
    let client = target.client()?;
    let probe = probe_with_client(&client).await?;
    Ok(info_from_probe(probe.kind, probe.version, probe.is_cmfa))
}

fn info_from_probe(kind: BackendKind, version: String, is_cmfa: bool) -> VersionInfo {
    let is_stash = kind == BackendKind::Stash;
    let is_mihomo = kind == BackendKind::Mihomo;
    let supports_core_management = is_mihomo && !is_cmfa;
    let supports_cache_flush = is_mihomo;
    VersionInfo {
        version,
        is_cmfa,
        is_stash,
        supports_core_config: (is_mihomo && !is_cmfa) || is_stash,
        supports_core_actions: supports_core_management || supports_cache_flush,
        supports_core_management,
        supports_cache_flush,
        supports_memory: is_mihomo,
    }
}
