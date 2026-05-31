use reqwest::Method;
use serde_json::{Value, json};

use crate::error::MihomoError;

use super::MihomoTarget;

/// `GET /configs` — full general config snapshot.
pub async fn configs(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target.client()?.get_json("configs").await?.to_string())
}

/// `PATCH /configs` — pass-through. The full schema lives in mihomo's
/// [`hub/route/configs.go`](https://github.com/MetaCubeX/mihomo/blob/Alpha/hub/route/configs.go);
/// callers send any subset of those keys (`mode`, `log-level`, `allow-lan`,
/// `port`, `socks-port`, `mixed-port`, `redir-port`, `tproxy-port`,
/// `bind-address`, `ipv6`, `sniffing`, `tcp-concurrent`, `interface-name`,
/// `find-process-mode`, `skip-auth-prefixes`, `lan-allowed-ips`,
/// `lan-disallowed-ips`, `tun`, `tuic-server`, `ss-config`, `vmess-config`,
/// `tcptun-config`, `udptun-config`).
pub async fn patch_configs(target: MihomoTarget, body_json: String) -> Result<(), MihomoError> {
    let body: Value = serde_json::from_str(&body_json)?;
    target
        .client()?
        .forward(Method::PATCH, "configs", Some(body))
        .await?;
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
