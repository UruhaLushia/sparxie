use reqwest::Method;
use serde_json::{Value, json};

use crate::MihomoError;

use super::MihomoTarget;
use super::backend::{BackendKind, probe_with_client};

const STASH_CONFIG_KEYS: [&str; 3] = ["mode", "log-level", "mixed-port"];

/// `GET /configs` — full general config snapshot.
pub async fn configs(target: MihomoTarget) -> Result<Value, MihomoError> {
    target.client()?.get_json("configs").await
}

/// `GET /configs` — return only outbound mode, normalized for the launcher.
pub async fn config_mode(target: MihomoTarget) -> Result<String, MihomoError> {
    let raw = target.client()?.get_json("configs").await?;
    Ok(raw
        .get("mode")
        .map(value_to_string)
        .unwrap_or_else(|| "rule".to_string())
        .to_lowercase())
}

/// `PATCH /configs` — pass-through. The full schema lives in mihomo's
/// [`hub/route/configs.go`](https://github.com/MetaCubeX/mihomo/blob/Alpha/hub/route/configs.go);
/// callers can send any subset of those keys (`mode`, `log-level`, `allow-lan`,
/// `port`, `socks-port`, `mixed-port`, `redir-port`, `tproxy-port`,
/// `bind-address`, `ipv6`, `sniffing`, `tcp-concurrent`, `interface-name`,
/// `find-process-mode`, `skip-auth-prefixes`, `lan-allowed-ips`,
/// `lan-disallowed-ips`, `tun`, `tuic-server`, `ss-config`, `vmess-config`,
/// `tcptun-config`, `udptun-config`). Stash is filtered to its supported
/// subset: `mode`, `log-level`, `mixed-port`.
pub async fn patch_configs(target: MihomoTarget, body_json: String) -> Result<(), MihomoError> {
    let mut body: Value = serde_json::from_str(&body_json)?;
    let client = target.client()?;
    if probe_with_client(&client).await?.kind == BackendKind::Stash {
        body = stash_patch_body(body)?;
    }
    client.forward(Method::PATCH, "configs", Some(body)).await?;
    Ok(())
}

/// `PUT /configs` — reload. `path` must be absolute on the mihomo host (and
/// pass mihomo's `IsSafePath` whitelist), or pass `payload` for inline YAML.
pub async fn reload_configs(
    target: MihomoTarget,
    path: Option<String>,
    payload: Option<String>,
    force: bool,
) -> Result<(), MihomoError> {
    let mut body = json!({});
    if let Some(p) = path {
        body["path"] = Value::String(p);
    }
    if let Some(p) = payload {
        body["payload"] = Value::String(p);
    }
    let p = if force {
        "configs?force=true"
    } else {
        "configs"
    };
    target.client()?.forward(Method::PUT, p, Some(body)).await?;
    Ok(())
}

/// `POST /configs/geo` — refresh geo databases (forbidden on `--embed`).
pub async fn update_geo(target: MihomoTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(Method::POST, "configs/geo", None)
        .await?;
    Ok(())
}

fn value_to_string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

fn stash_patch_body(body: Value) -> Result<Value, MihomoError> {
    let Some(map) = body.as_object() else {
        return Err(MihomoError::Other("Stash 配置更新需要 JSON 对象".into()));
    };
    let filtered: serde_json::Map<String, Value> = map
        .iter()
        .filter(|(key, _)| STASH_CONFIG_KEYS.contains(&key.as_str()))
        .map(|(key, value)| (key.clone(), value.clone()))
        .collect();
    if filtered.is_empty() {
        return Err(MihomoError::Other(
            "Stash 仅支持修改 mode、log-level、mixed-port".into(),
        ));
    }
    Ok(Value::Object(filtered))
}
