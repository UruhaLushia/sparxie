use serde_json::{Value, json};

use crate::MihomoError;
use crate::backend::api::{
    ProxyProviderEntry, RuleEntry, RuleProviderEntry, TrafficSample, VersionInfo,
};
use crate::surge::client::SurgeTarget;

mod config;
mod connections;
mod metrics;
mod policies;
pub(crate) mod traffic;
mod value;

use config::{profile_general_config, to_surge_mode, to_ui_mode};
use traffic::parse_traffic;

pub use connections::{
    close_all_connections, close_connection, close_connections_by_chain,
    close_connections_by_group, connections,
};
pub use policies::{
    group_delay, proxy_batch_delay, proxy_catalog, proxy_delay_window, proxy_group_batch_delay,
    proxy_group_members, select_proxy, unfix_proxy,
};

pub async fn version(_: SurgeTarget) -> Result<String, MihomoError> {
    Ok("Surge".into())
}

pub async fn version_info(target: SurgeTarget) -> Result<VersionInfo, MihomoError> {
    let client = target.client()?;
    client.get_json("v1/outbound").await?;
    let supports_memory = client
        .get_text("v1/metrics")
        .await
        .and_then(|metrics| metrics::parse_memory(&metrics))
        .is_ok();
    Ok(VersionInfo {
        version: "Surge".into(),
        supports_core_config: true,
        supports_core_actions: false,
        supports_core_management: false,
        supports_cache_flush: false,
        supports_memory,
        ..Default::default()
    })
}

pub async fn configs(target: SurgeTarget) -> Result<Value, MihomoError> {
    let raw = target
        .client()?
        .get_json("v1/profiles/current?sensitive=0")
        .await?;
    let profile = raw
        .get("profile")
        .and_then(Value::as_str)
        .ok_or_else(|| MihomoError::InvalidJson("missing profile".into()))?;
    let mut config = profile_general_config(profile);
    if let Value::Object(map) = &mut config
        && let Ok(mode) = config_mode(target).await
    {
        map.insert("mode".into(), Value::String(mode));
    }
    Ok(config)
}

pub async fn config_mode(target: SurgeTarget) -> Result<String, MihomoError> {
    let raw = target.client()?.get_json("v1/outbound").await?;
    Ok(to_ui_mode(
        raw.get("mode").and_then(Value::as_str).unwrap_or("rule"),
    ))
}

pub async fn set_config_mode(target: SurgeTarget, mode: String) -> Result<(), MihomoError> {
    target
        .client()?
        .post_json("v1/outbound", json!({ "mode": to_surge_mode(&mode) }))
        .await?;
    Ok(())
}

pub async fn patch_configs(target: SurgeTarget, body_json: String) -> Result<(), MihomoError> {
    let body: Value = serde_json::from_str(&body_json)?;
    let Some(map) = body.as_object() else {
        return Err(MihomoError::Other("Surge 配置更新需要 JSON 对象".into()));
    };
    if map.contains_key("mode") {
        return Err(MihomoError::Other(
            "Surge 出站模式不通过配置更新修改".into(),
        ));
    }
    let client = target.client()?;
    let mut handled = false;
    if let Some(level) = map.get("log-level").and_then(Value::as_str) {
        client
            .post_json("v1/log/level", json!({ "level": level }))
            .await?;
        handled = true;
    }
    if handled {
        Ok(())
    } else {
        Err(MihomoError::Other("Surge 不支持修改这些配置项".into()))
    }
}

pub async fn reload_configs(target: SurgeTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .post_json("v1/profiles/reload", json!({}))
        .await?;
    Ok(())
}

pub async fn flush_dns(target: SurgeTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .post_json("v1/dns/flush", json!({}))
        .await?;
    Ok(())
}

pub async fn traffic_sample(target: SurgeTarget) -> Result<TrafficSample, MihomoError> {
    let raw = target.client()?.get_json("v1/traffic").await?;
    Ok(parse_traffic(&raw))
}

pub async fn memory_sample(
    target: SurgeTarget,
) -> Result<crate::backend::api::MemorySample, MihomoError> {
    metrics::memory_sample(target).await
}

pub async fn proxy_provider_catalog(
    _: SurgeTarget,
) -> Result<Vec<ProxyProviderEntry>, MihomoError> {
    Ok(Vec::new())
}

pub async fn rule_provider_catalog(_: SurgeTarget) -> Result<Vec<RuleProviderEntry>, MihomoError> {
    Ok(Vec::new())
}

pub async fn fetch_rules(target: SurgeTarget) -> Result<Vec<RuleEntry>, MihomoError> {
    crate::surge::state::rules::load(target).await
}

pub async fn unsupported<T>(message: &str) -> Result<T, MihomoError> {
    Err(MihomoError::Other(format!("Surge 不支持{message}")))
}
