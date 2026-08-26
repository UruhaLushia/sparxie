//! Controller-shaped adapter over the embedded kernel's Go bridge.

use std::time::Duration;

use futures_util::StreamExt;
use reqwest::Method;
use serde_json::{Value, json};
use tokio::sync::broadcast;
use tokio_stream::wrappers::BroadcastStream;

use crate::MihomoError;
use crate::clash::client::LocalFrameStream;

#[cfg(target_os = "android")]
use crate::core::go_bridge;

#[cfg(not(target_os = "android"))]
fn unsupported() -> MihomoError {
    MihomoError::Other("本地引擎仅支持 Android".into())
}

fn strip_query(path: &str) -> &str {
    path.split('?').next().unwrap_or(path)
}

fn query_param(path: &str, key: &str) -> Option<String> {
    path.split('?').nth(1).and_then(|q| {
        q.split('&').find_map(|pair| {
            let (k, v) = pair.split_once('=')?;
            (k == key).then(|| url_unescape(v))
        })
    })
}

fn url_unescape(value: &str) -> String {
    // Percent-decode into raw bytes, then interpret as UTF-8 (proxy names are
    // arbitrary unicode; byte-at-a-time char pushes would garble them).
    let mut bytes = Vec::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        if c == '%' {
            let hex: String = chars.by_ref().take(2).collect();
            if let Ok(byte) = u8::from_str_radix(&hex, 16) {
                bytes.push(byte);
                continue;
            }
            bytes.push(b'%');
            for h in hex.bytes() {
                bytes.push(h);
            }
            continue;
        }
        let mut buf = [0u8; 4];
        bytes.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
    }
    String::from_utf8_lossy(&bytes).into_owned()
}

fn query_method(path: &str) -> Result<&'static str, MihomoError> {
    let p = strip_query(path);
    match p {
        "" | "version" => Ok("version"),
        "proxies" => Ok("proxies"),
        "connections" => Ok("connections"),
        "configs" => Ok("configs"),
        "rules" => Ok("rules"),
        "providers/proxies" => Ok("providers"),
        "providers/rules" => Ok("ruleProviders"),
        _ => Err(MihomoError::Other(format!("本地引擎不支持查询：{p}"))),
    }
}

#[cfg(target_os = "android")]
fn query(method: &str) -> Result<Value, MihomoError> {
    go_bridge::query_state(method)
}

#[cfg(not(target_os = "android"))]
fn query(_method: &str) -> Result<Value, MihomoError> {
    Err(unsupported())
}

macro_rules! local_op {
    ($body:expr) => {{
        #[cfg(target_os = "android")]
        {
            $body?;
            return Ok(Value::Null);
        }
        #[cfg(not(target_os = "android"))]
        {
            return Err(unsupported());
        }
    }};
}

pub(super) async fn request(
    method: Method,
    path: &str,
    body: Option<Value>,
) -> Result<Value, MihomoError> {
    #[cfg(target_os = "android")]
    if !matches!(strip_query(path), "" | "version") {
        crate::core::require_running()?;
    }
    match method {
        Method::GET => {
            let p = strip_query(path);
            if let Some(rest) = p.strip_prefix("proxies/") {
                if let Some(rest) = rest.strip_suffix("/delay") {
                    let name = url_unescape(rest);
                    let url = query_param(path, "url").unwrap_or_default();
                    let timeout = query_param(path, "timeout")
                        .and_then(|v| v.parse::<i32>().ok())
                        .unwrap_or(5000);
                    #[cfg(target_os = "android")]
                    {
                        let delay = go_bridge::test_delay(&name, &url, timeout)?;
                        return Ok(json!({ "delay": delay }));
                    }
                    #[cfg(not(target_os = "android"))]
                    {
                        let _ = (name, url, timeout);
                        return Err(unsupported());
                    }
                }
                let name = url_unescape(rest);
                let raw = query("proxies")?;
                let Some(proxies) = raw.get("proxies").and_then(Value::as_object) else {
                    return Ok(json!({}));
                };
                return proxies
                    .get(&name)
                    .cloned()
                    .ok_or_else(|| MihomoError::Upstream {
                        status: 404,
                        body: format!("proxy {name} not found"),
                    });
            }
            if let Some(rest) = p.strip_prefix("group/")
                && let Some(rest) = rest.strip_suffix("/delay")
            {
                #[cfg(target_os = "android")]
                {
                    let group = url_unescape(rest);
                    let url = query_param(path, "url").unwrap_or_default();
                    let timeout = query_param(path, "timeout")
                        .and_then(|v| v.parse::<i32>().ok())
                        .unwrap_or(5000);
                    let raw = query("proxies")?;
                    let members = raw
                        .get("proxies")
                        .and_then(Value::as_object)
                        .and_then(|m| m.get(&group))
                        .and_then(|g| g.get("all"))
                        .and_then(Value::as_array)
                        .map(|arr| {
                            arr.iter()
                                .filter_map(|v| v.as_str().map(String::from))
                                .collect::<Vec<_>>()
                        })
                        .unwrap_or_default();
                    let mut map = serde_json::Map::new();
                    let results = futures_util::stream::iter(members)
                        .map(|name| {
                            let url = url.clone();
                            tokio::task::spawn_blocking(move || {
                                let delay = go_bridge::test_delay(&name, &url, timeout).ok();
                                (name, delay)
                            })
                        })
                        .buffer_unordered(8)
                        .collect::<Vec<_>>()
                        .await;
                    for entry in results {
                        let Ok((name, delay)) = entry else { continue };
                        let value = match delay {
                            Some(d) => json!(d),
                            None => json!(0),
                        };
                        map.insert(name, value);
                    }
                    return Ok(Value::Object(map));
                }
                #[cfg(not(target_os = "android"))]
                {
                    let _ = rest;
                    return Err(unsupported());
                }
            }
            if let Some(rest) = p.strip_prefix("providers/proxies/") {
                if let Some(rest) = rest.strip_suffix("/healthcheck") {
                    let (_, name) = rest.rsplit_once('/').unwrap_or((rest, rest));
                    let name = url_unescape(name);
                    let url = query_param(path, "url").unwrap_or_default();
                    let timeout = query_param(path, "timeout")
                        .and_then(|v| v.parse::<i32>().ok())
                        .unwrap_or(5000);
                    #[cfg(target_os = "android")]
                    {
                        let delay = go_bridge::test_delay(&name, &url, timeout)?;
                        return Ok(json!({ "delay": delay }));
                    }
                    #[cfg(not(target_os = "android"))]
                    {
                        let _ = (name, url, timeout);
                        return Err(unsupported());
                    }
                }
                let _ = url_unescape(rest);
                return Err(MihomoError::Other("本地引擎暂不支持该操作".into()));
            }
            if p == "group" {
                let raw = query("proxies")?;
                let Some(proxies) = raw.get("proxies").and_then(Value::as_object) else {
                    return Ok(json!({}));
                };
                let groups: Value = proxies
                    .iter()
                    .filter(|(_, v)| {
                        v.get("type").and_then(|t| t.as_str()).is_some_and(|t| {
                            matches!(t, "Selector" | "URLTest" | "Fallback" | "LoadBalance")
                        })
                    })
                    .map(|(k, v)| (k.clone(), v.clone()))
                    .collect();
                return Ok(json!({ "proxies": groups }));
            }
            let method = query_method(path)?;
            let value = query(method)?;
            if let Some(error) = value.get("error").and_then(|v| v.as_str()) {
                return Err(MihomoError::Upstream {
                    status: 400,
                    body: error.to_string(),
                });
            }
            Ok(value)
        }
        Method::PUT => {
            let p = strip_query(path);
            if let Some(name) = p.strip_prefix("proxies/") {
                let group = url_unescape(name);
                let select = body
                    .and_then(|b| b.get("name").and_then(|v| v.as_str()).map(String::from))
                    .unwrap_or_default();
                #[cfg(target_os = "android")]
                {
                    go_bridge::change_proxy(&group, &select)?;
                    return Ok(Value::Null);
                }
                #[cfg(not(target_os = "android"))]
                {
                    let _ = (group, select);
                    return Err(unsupported());
                }
            }
            if p == "configs" {
                #[cfg(target_os = "android")]
                {
                    crate::core::config_reload_active().await?;
                    return Ok(Value::Null);
                }
                #[cfg(not(target_os = "android"))]
                {
                    return Err(unsupported());
                }
            }
            if let Some(name) = p.strip_prefix("providers/proxies/") {
                let name = url_unescape(name);
                #[cfg(target_os = "android")]
                {
                    go_bridge::update_provider(&name)?;
                    return Ok(Value::Null);
                }
                #[cfg(not(target_os = "android"))]
                {
                    let _ = name;
                    return Err(unsupported());
                }
            }
            if let Some(name) = p.strip_prefix("providers/rules/") {
                let name = url_unescape(name);
                #[cfg(target_os = "android")]
                {
                    go_bridge::update_rule_provider(&name)?;
                    return Ok(Value::Null);
                }
                #[cfg(not(target_os = "android"))]
                {
                    let _ = name;
                    return Err(unsupported());
                }
            }
            Err(MihomoError::Other(format!("本地引擎不支持：PUT {p}")))
        }
        Method::PATCH => {
            let p = strip_query(path);
            if p == "configs" {
                let body = body.unwrap_or_else(|| json!({}));
                let supported = body
                    .as_object()
                    .is_some_and(|value| value.keys().all(|key| key == "mode"));
                if !supported {
                    return Err(MihomoError::Other(
                        "本地引擎运行时仅支持切换出站模式".into(),
                    ));
                }
                #[cfg(target_os = "android")]
                {
                    go_bridge::patch_config(&body.to_string())?;
                    return Ok(Value::Null);
                }
                #[cfg(not(target_os = "android"))]
                {
                    let _ = body;
                    return Err(unsupported());
                }
            }
            Err(MihomoError::Other(format!("本地引擎不支持：PATCH {p}")))
        }
        Method::POST => match strip_query(path) {
            "cache/fakeip/flush" => {
                local_op!(crate::core::go_bridge::flush_fake_ip());
            }
            "cache/dns/flush" => {
                local_op!(crate::core::go_bridge::flush_dns());
            }
            _ => Err(MihomoError::Other("本地引擎不支持该操作".into())),
        },
        Method::DELETE => {
            let p = strip_query(path);
            if p == "connections" {
                local_op!(crate::core::go_bridge::close_all_connections());
            } else if let Some(raw_id) = p.strip_prefix("connections/") {
                #[cfg(target_os = "android")]
                let id = url_unescape(raw_id);
                #[cfg(not(target_os = "android"))]
                let _id = raw_id;
                local_op!(crate::core::go_bridge::close_connection(&id));
            } else if let Some(raw_name) = p.strip_prefix("proxies/") {
                #[cfg(target_os = "android")]
                let name = url_unescape(raw_name);
                #[cfg(not(target_os = "android"))]
                let _name = raw_name;
                local_op!(crate::core::go_bridge::unfix_proxy(&name));
            } else {
                Err(MihomoError::Other(format!("本地引擎不支持：DELETE {p}")))
            }
        }
        _ => Err(MihomoError::Other("本地引擎不支持该请求方法".into())),
    }
}

pub(super) fn open_stream(path: &str) -> Result<LocalFrameStream, MihomoError> {
    #[cfg(target_os = "android")]
    crate::core::require_running()?;
    let p = strip_query(path);
    match p {
        "traffic" | "memory" | "logs" => {
            let rx = crate::core::telemetry_subscribe(p);
            let stream = BroadcastStream::new(rx).filter_map(|item| async { item.ok() });
            Ok(stream.boxed())
        }
        "connections" => {
            let interval = query_param(path, "interval")
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(1000)
                .max(100);
            let (tx, rx) = broadcast::channel::<String>(8);
            tokio::spawn(async move {
                let mut ticker = tokio::time::interval(Duration::from_millis(interval));
                loop {
                    ticker.tick().await;
                    let result = query("connections");
                    match result {
                        Ok(value) => {
                            if tx.send(value.to_string()).is_err() {
                                break;
                            }
                        }
                        Err(err) => {
                            if tx
                                .send(json!({ "error": err.to_string() }).to_string())
                                .is_err()
                            {
                                break;
                            }
                        }
                    }
                }
            });
            let stream = BroadcastStream::new(rx).filter_map(|item| async { item.ok() });
            Ok(stream.boxed())
        }
        _ => Err(MihomoError::Other(format!("本地引擎不支持流：{p}"))),
    }
}
