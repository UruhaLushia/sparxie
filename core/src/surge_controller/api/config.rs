use serde_json::Value;

use crate::MihomoError;
use crate::surge_controller::client::SurgeControllerTarget;

use super::command_ok;

pub async fn configs(target: SurgeControllerTarget) -> Result<Value, MihomoError> {
    let raw = target.request(["environment"]).await?;
    let environment = raw.get("environment").unwrap_or(&raw);
    let mode = environment
        .get("ProxyMode")
        .and_then(value_i64)
        .map(mode_from_number)
        .unwrap_or("rule");
    Ok(serde_json::json!({
        "mode": mode,
        "mode-options": ["rule", "global", "direct"],
    }))
}

pub async fn set_config_mode(
    target: SurgeControllerTarget,
    mode: String,
) -> Result<(), MihomoError> {
    command_ok(
        &target,
        ["set".into(), format!("ProxyMode={}", mode_to_number(&mode))],
    )
    .await
}

pub async fn patch_configs(
    target: SurgeControllerTarget,
    body_json: String,
) -> Result<(), MihomoError> {
    let body: Value = serde_json::from_str(&body_json)?;
    let Some(map) = body.as_object() else {
        return Err(MihomoError::Other(
            "Surge 控制器配置更新需要 JSON 对象".into(),
        ));
    };
    if let Some(level) = map.get("log-level").and_then(Value::as_str) {
        return command_ok(&target, ["set-log-level", level]).await;
    }
    Err(MihomoError::Other(
        "Surge 控制器不支持修改这些配置项".into(),
    ))
}

pub async fn reload_configs(target: SurgeControllerTarget) -> Result<(), MihomoError> {
    command_ok(&target, ["reload"]).await
}

pub async fn flush_dns(target: SurgeControllerTarget) -> Result<(), MihomoError> {
    command_ok(&target, ["flush", "dns"]).await
}

fn value_i64(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
}

fn mode_from_number(mode: i64) -> &'static str {
    match mode {
        0 => "direct",
        1 => "global",
        _ => "rule",
    }
}

fn mode_to_number(mode: &str) -> u8 {
    match mode.to_ascii_lowercase().as_str() {
        "direct" => 0,
        "global" | "proxy" => 1,
        _ => 2,
    }
}
