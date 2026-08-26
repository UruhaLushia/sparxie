use crate::MihomoError;
use serde_json::{Value, json};

use super::{BackendTarget, BackendType, ControllerConfig, VersionInfo};

pub async fn controller_configs(target: BackendTarget) -> Result<ControllerConfig, MihomoError> {
    let load_target = target.clone();
    super::session::configs(&target, move || async move {
        let raw = match load_target.backend_type {
            BackendType::Clash => crate::clash::api::configs(load_target.clash()).await,
            BackendType::Surge => crate::surge::api::configs(load_target.surge()).await,
            BackendType::SurgeController => {
                crate::surge_controller::api::configs(load_target.surge_controller()).await
            }
            BackendType::SingBox => crate::sing_box::api::configs(load_target.sing_box()).await,
        }?;
        Ok(core_config_from_value(&raw))
    })
    .await
}

pub async fn controller_set_config_mode(
    target: BackendTarget,
    mode: String,
) -> Result<(), MihomoError> {
    let cache_target = target.clone();
    let result = match target.backend_type {
        BackendType::Clash => patch_config_value(target, json!({ "mode": mode })).await,
        BackendType::Surge => crate::surge::api::set_config_mode(target.surge(), mode).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::set_config_mode(target.surge_controller(), mode).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::set_config_mode(target.sing_box(), mode).await
        }
    };
    if result.is_ok() {
        super::session::invalidate_configs(&cache_target);
    }
    result
}

pub async fn controller_set_config_log_level(
    target: BackendTarget,
    level: String,
) -> Result<(), MihomoError> {
    update_config(target, json!({ "log-level": level })).await
}

pub async fn controller_set_config_tun_enabled(
    target: BackendTarget,
    enabled: bool,
) -> Result<(), MihomoError> {
    update_config(target, json!({ "tun": { "enable": enabled } })).await
}

pub async fn controller_set_config_bool(
    target: BackendTarget,
    key: String,
    value: bool,
) -> Result<(), MihomoError> {
    match key.as_str() {
        "allow-lan" | "ipv6" | "tcp-concurrent" => {
            update_config(target, json!({ key: value })).await
        }
        _ => Err(MihomoError::Other("不支持的布尔配置项".into())),
    }
}

pub async fn controller_set_config_port(
    target: BackendTarget,
    key: String,
    value: u32,
) -> Result<(), MihomoError> {
    match key.as_str() {
        "port" | "socks-port" | "mixed-port" => update_config(target, json!({ key: value })).await,
        _ => Err(MihomoError::Other("不支持的端口配置项".into())),
    }
}

async fn update_config(target: BackendTarget, body: Value) -> Result<(), MihomoError> {
    let cache_target = target.clone();
    patch_config_value(target, body).await?;
    super::session::invalidate_configs(&cache_target);
    Ok(())
}

async fn patch_config_value(target: BackendTarget, body: Value) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::patch_configs(target.clash(), body.to_string()).await
        }
        BackendType::Surge => {
            crate::surge::api::patch_configs(target.surge(), body.to_string()).await
        }
        BackendType::SurgeController => {
            crate::surge_controller::api::patch_configs(target.surge_controller(), body.to_string())
                .await
        }
        BackendType::SingBox => {
            crate::sing_box::api::patch_configs(target.sing_box(), body.to_string()).await
        }
    }
}

pub async fn controller_reload_configs(
    target: BackendTarget,
    path: Option<String>,
    payload: Option<String>,
    force: bool,
) -> Result<(), MihomoError> {
    let cache_target = target.clone();
    let result = match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::reload_configs(target.clash(), path, payload, force).await
        }
        BackendType::Surge => {
            if path.is_some() || payload.is_some() || force {
                return Err(MihomoError::Other("Surge 仅支持重载当前配置文件".into()));
            }
            crate::surge::api::reload_configs(target.surge()).await
        }
        BackendType::SurgeController => {
            if path.is_some() || payload.is_some() || force {
                return Err(MihomoError::Other(
                    "Surge 控制器仅支持重载当前配置文件".into(),
                ));
            }
            crate::surge_controller::api::reload_configs(target.surge_controller()).await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("重载配置").await,
    };
    if result.is_ok() {
        super::session::release_target(&cache_target);
    }
    result
}

pub async fn controller_update_geo(target: BackendTarget) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::update_geo(target.clash()).await,
        BackendType::Surge => crate::surge::api::unsupported("更新 GeoData").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::unsupported("更新 GeoData").await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("更新 GeoData").await,
    }
}

pub async fn controller_flush_fakeip(target: BackendTarget) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::flush_fakeip(target.clash()).await,
        BackendType::Surge => crate::surge::api::unsupported("清空 FakeIP").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::unsupported("清空 FakeIP").await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("清空 FakeIP").await,
    }
}

pub async fn controller_flush_dns(target: BackendTarget) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::flush_dns(target.clash()).await,
        BackendType::Surge => crate::surge::api::flush_dns(target.surge()).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::flush_dns(target.surge_controller()).await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("清理 DNS 缓存").await,
    }
}

pub async fn controller_dns_query(
    target: BackendTarget,
    name: String,
    qtype: Option<String>,
) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::dns_query(target.clash(), name, qtype).await,
        BackendType::Surge => crate::surge::api::unsupported("DNS 查询").await,
        BackendType::SurgeController => crate::surge_controller::api::unsupported("DNS 查询").await,
        BackendType::SingBox => crate::sing_box::api::unsupported("DNS 查询").await,
    }
}

pub async fn controller_upgrade_core(
    target: BackendTarget,
    force: bool,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::upgrade_core(target.clash(), None, force).await,
        BackendType::Surge => crate::surge::api::unsupported("升级核心").await,
        BackendType::SurgeController => crate::surge_controller::api::unsupported("升级核心").await,
        BackendType::SingBox => crate::sing_box::api::unsupported("升级核心").await,
    }
}

pub async fn controller_upgrade_ui(target: BackendTarget) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::upgrade_ui(target.clash()).await,
        BackendType::Surge => crate::surge::api::unsupported("升级 UI").await,
        BackendType::SurgeController => crate::surge_controller::api::unsupported("升级 UI").await,
        BackendType::SingBox => crate::sing_box::api::unsupported("升级 UI").await,
    }
}

pub async fn controller_upgrade_geo(target: BackendTarget) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::upgrade_geo(target.clash()).await,
        BackendType::Surge => crate::surge::api::unsupported("升级 GeoData").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::unsupported("升级 GeoData").await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("升级 GeoData").await,
    }
}

pub async fn controller_restart_core(target: BackendTarget) -> Result<(), MihomoError> {
    let cache_target = target.clone();
    let result = match target.backend_type {
        BackendType::Clash => crate::clash::api::restart_core(target.clash()).await,
        BackendType::Surge => crate::surge::api::unsupported("重启核心").await,
        BackendType::SurgeController => crate::surge_controller::api::unsupported("重启核心").await,
        BackendType::SingBox => crate::sing_box::api::unsupported("重启核心").await,
    };
    if result.is_ok() {
        super::session::release_target(&cache_target);
    }
    result
}

fn core_config_from_value(raw: &Value) -> ControllerConfig {
    let tun = raw.get("tun");
    ControllerConfig {
        mode: string_value(raw.get("mode")),
        mode_options: string_list_value(raw.get("mode-options")),
        log_level: string_value(raw.get("log-level")).map(|s| s.to_ascii_lowercase()),
        tun_enabled: tun.and_then(|v| v.get("enable")).and_then(bool_value),
        allow_lan: raw.get("allow-lan").and_then(bool_value),
        ipv6: raw.get("ipv6").and_then(bool_value),
        tcp_concurrent: raw.get("tcp-concurrent").and_then(bool_value),
        port: raw.get("port").and_then(u32_value),
        socks_port: raw.get("socks-port").and_then(u32_value),
        mixed_port: raw.get("mixed-port").and_then(u32_value),
    }
}

fn string_value(value: Option<&Value>) -> Option<String> {
    value.and_then(|value| match value {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    })
}

fn string_list_value(value: Option<&Value>) -> Vec<String> {
    let Some(Value::Array(items)) = value else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| string_value(Some(item)))
        .collect()
}

fn bool_value(value: &Value) -> Option<bool> {
    match value {
        Value::Bool(b) => Some(*b),
        Value::String(s) => match s.to_ascii_lowercase().as_str() {
            "true" | "1" | "yes" | "on" => Some(true),
            "false" | "0" | "no" | "off" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

fn u32_value(value: &Value) -> Option<u32> {
    match value {
        Value::Number(n) => n.as_u64().and_then(|v| u32::try_from(v).ok()),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

pub async fn controller_version(target: BackendTarget) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::version(target.clash()).await,
        BackendType::Surge => crate::surge::api::version(target.surge()).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::version(target.surge_controller()).await
        }
        BackendType::SingBox => crate::sing_box::api::version(target.sing_box()).await,
    }
}

pub async fn controller_version_info(target: BackendTarget) -> Result<VersionInfo, MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            let local = target.is_local();
            let mut info: VersionInfo = crate::clash::api::version_info(target.clash())
                .await?
                .into();
            if local {
                info.is_cmfa = true;
                info.supports_core_config = false;
                info.supports_core_management = false;
                info.supports_core_actions = info.supports_cache_flush;
            }
            Ok(info)
        }
        BackendType::Surge => crate::surge::api::version_info(target.surge()).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::version_info(target.surge_controller()).await
        }
        BackendType::SingBox => crate::sing_box::api::version_info(target.sing_box()).await,
    }
}
