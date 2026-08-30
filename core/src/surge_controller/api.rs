use crate::MihomoError;
use crate::backend::api::{RuleEntry, VersionInfo};

use super::client::SurgeControllerTarget;

mod config;
mod connections;
mod performance;
mod policies;
mod resources;
mod value;

pub use config::{configs, flush_dns, patch_configs, reload_configs, set_config_mode};
pub use connections::{
    close_all_connections, close_connection, close_connections_by_chain,
    close_connections_by_group, connections,
};
pub use policies::{
    group_delay, proxy_batch_delay, proxy_catalog, proxy_delay, proxy_group_batch_delay,
    proxy_group_members, select_proxy, unfix_proxy,
};
pub use resources::{
    proxy_provider_catalog, proxy_provider_nodes, proxy_provider_update, rule_provider_catalog,
    rule_provider_update,
};
pub(crate) use value::{string_map, value_string};

pub async fn version(target: SurgeControllerTarget) -> Result<String, MihomoError> {
    Ok(version_label(&target.welcome().await?))
}

pub async fn version_info(target: SurgeControllerTarget) -> Result<VersionInfo, MihomoError> {
    let welcome = target.welcome().await?;
    let supports_memory = performance::memory_sample(target).await.is_ok();
    Ok(VersionInfo {
        version: version_label(&welcome),
        supports_core_config: true,
        supports_core_actions: false,
        supports_core_management: true,
        supports_cache_flush: false,
        supports_memory,
        ..Default::default()
    })
}

pub async fn memory_sample(
    target: SurgeControllerTarget,
) -> Result<crate::backend::api::MemorySample, MihomoError> {
    performance::memory_sample(target).await
}

pub async fn proxy_detail(
    target: SurgeControllerTarget,
    name: String,
) -> Result<String, MihomoError> {
    let runtime_key = policies::member_runtime_key(target.clone(), &name).await?;
    let usage = policies::member_usage(target.clone(), &name).await?;
    let test_error = super::state::benchmark::error(&target, &runtime_key);
    let runtime = target
        .request(["proxy-runtime-status", runtime_key.as_str()])
        .await
        .unwrap_or_default();
    let traffic = runtime.get("traffic").cloned().unwrap_or_default();
    Ok(serde_json::json!({
        "name": name,
        "traffic": traffic,
        "errors": runtime.get("errors").cloned().unwrap_or_default(),
        "test-capability": value_string(runtime.get("testCapability")).unwrap_or_default(),
        "type": value_string(runtime.get("type")).unwrap_or_default(),
        "usage": usage,
        "usage-label": usage_label(usage),
        "test-error": test_error,
    })
    .to_string())
}

fn usage_label(usage: Option<i32>) -> &'static str {
    match usage {
        Some(1) => "最常使用",
        Some(2) => "经常使用",
        Some(3) => "偶尔使用",
        Some(0) => "未使用",
        Some(-1) => "已排除",
        _ => "",
    }
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
    super::state::benchmark::release_target(target);
    super::state::traffic::release_target(target);
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
