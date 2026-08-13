use crate::MihomoError;
use crate::backend::api::{RuleEntry, VersionInfo};

use super::client::SurgeControllerTarget;

mod config;
mod connections;
mod policies;
mod resources;
mod value;

pub use config::{configs, flush_dns, patch_configs, reload_configs, set_config_mode};
pub use connections::{
    close_all_connections, close_connection, close_connections_by_chain,
    close_connections_by_group, connections,
};
pub use policies::{
    group_delay, proxy_batch_delay, proxy_catalog, proxy_group_batch_delay, proxy_group_members,
    select_proxy, unfix_proxy,
};
pub use resources::{
    proxy_provider_catalog, proxy_provider_nodes, proxy_provider_update, rule_provider_catalog,
    rule_provider_update,
};
pub(crate) use value::{string_map, value_i32, value_string};

pub async fn version(target: SurgeControllerTarget) -> Result<String, MihomoError> {
    Ok(version_label(&target.welcome().await?))
}

pub async fn version_info(target: SurgeControllerTarget) -> Result<VersionInfo, MihomoError> {
    let welcome = target.welcome().await?;
    Ok(VersionInfo {
        version: version_label(&welcome),
        supports_core_config: true,
        supports_core_actions: false,
        supports_core_management: true,
        supports_cache_flush: false,
        supports_memory: false,
        ..Default::default()
    })
}

pub async fn proxy_detail(
    target: SurgeControllerTarget,
    name: String,
) -> Result<String, MihomoError> {
    let raw = target.request(["show-policy", name.as_str()]).await?;
    Ok(serde_json::json!({
        "name": name,
        "raw": value_string(raw.get("result")).unwrap_or_else(|| raw.to_string()),
    })
    .to_string())
}

pub async fn fetch_rules(target: SurgeControllerTarget) -> Result<Vec<RuleEntry>, MihomoError> {
    let raw = target.request(["dump", "rule"]).await?;
    Ok(crate::surge::state::rules::parse_rules(&raw))
}

pub async fn unsupported<T>(message: &str) -> Result<T, MihomoError> {
    Err(MihomoError::Other(format!("Surge 控制器不支持{message}")))
}

pub fn release_target(target: &SurgeControllerTarget) {
    policies::clear_cache(target);
    resources::clear_cache(target);
    super::client::release_target(target);
}

pub(crate) async fn command_ok<I, S>(
    target: &SurgeControllerTarget,
    argv: I,
) -> Result<(), MihomoError>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    target.request(argv).await?;
    Ok(())
}

fn version_label(welcome: &super::client::Welcome) -> String {
    if welcome.build.is_empty() {
        format!("Surge {} Controller", welcome.system)
    } else {
        format!("Surge {} ({})", welcome.system, welcome.build)
    }
}
