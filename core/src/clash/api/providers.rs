use reqwest::Method;
use serde_json::Value;

use crate::MihomoError;

use super::proxies::value::proxy_delay;
use super::{MihomoTarget, ProxyMemberEntry, urlencode};

// ---------- proxy providers ----------------------------------------------

#[derive(Clone, Debug, Default)]
pub struct ProxyProviderEntry {
    pub name: String,
    pub vehicle_type: String,
    pub proxies: u32,
    pub updated_at: String,
    pub updatable: bool,
    pub has_subscription_info: bool,
    pub subscription_upload: u64,
    pub subscription_download: u64,
    pub subscription_total: u64,
    pub subscription_expire: u64,
}

#[derive(Clone, Debug, Default)]
pub struct RuleProviderEntry {
    pub name: String,
    pub vehicle_type: String,
    pub behavior: String,
    pub format: String,
    pub rule_count: u32,
    pub updated_at: String,
    pub updatable: bool,
}

pub async fn proxy_providers(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target
        .client()?
        .get_json("providers/proxies")
        .await?
        .to_string())
}

pub async fn proxy_provider_catalog(
    target: MihomoTarget,
) -> Result<Vec<ProxyProviderEntry>, MihomoError> {
    let raw = target.client()?.get_json("providers/proxies").await?;
    let Some(providers) = raw.get("providers").and_then(Value::as_object) else {
        return Ok(Vec::new());
    };
    let mut list = Vec::with_capacity(providers.len());
    for (name, data) in providers {
        let vehicle_type = field_or(data, "vehicleType", "");
        if vehicle_type.eq_ignore_ascii_case("compatible") {
            continue;
        }
        let subscription_info = data.get("subscriptionInfo").and_then(Value::as_object);
        let subscription_value = |key| {
            subscription_info
                .and_then(|info| info.get(key))
                .map(value_to_u64)
                .unwrap_or_default()
        };
        list.push(ProxyProviderEntry {
            name: name.clone(),
            proxies: data
                .get("proxies")
                .and_then(Value::as_array)
                .map(|items| items.len() as u32)
                .unwrap_or_default(),
            updatable: vehicle_type.eq_ignore_ascii_case("http"),
            vehicle_type,
            updated_at: field_or(data, "updatedAt", ""),
            has_subscription_info: subscription_info.is_some(),
            subscription_upload: subscription_value("Upload"),
            subscription_download: subscription_value("Download"),
            subscription_total: subscription_value("Total"),
            subscription_expire: subscription_value("Expire"),
        });
    }
    list.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(list)
}

pub async fn proxy_provider_nodes(
    target: MihomoTarget,
    name: String,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    let raw = target.client()?.get_json("providers/proxies").await?;
    let nodes = raw
        .get("providers")
        .and_then(Value::as_object)
        .and_then(|providers| providers.get(&name))
        .and_then(|provider| provider.get("proxies"))
        .and_then(Value::as_array);
    let Some(nodes) = nodes else {
        return Ok(Vec::new());
    };
    Ok(nodes
        .iter()
        .filter_map(|node| {
            let name = field_or(node, "name", "");
            (!name.is_empty()).then(|| ProxyMemberEntry {
                name,
                proxy_type: field_or(node, "type", "Proxy"),
                delay: proxy_delay(node),
            })
        })
        .collect())
}

pub async fn proxy_provider_update(target: MihomoTarget, name: String) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::PUT,
            &format!("providers/proxies/{}", urlencode(&name)),
            None,
        )
        .await?;
    Ok(())
}

pub async fn proxy_provider_healthcheck(
    target: MihomoTarget,
    name: String,
) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::GET,
            &format!("providers/proxies/{}/healthcheck", urlencode(&name)),
            None,
        )
        .await?;
    Ok(())
}

// ---------- rule providers -----------------------------------------------

pub async fn rule_providers(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target
        .client()?
        .get_json("providers/rules")
        .await?
        .to_string())
}

pub async fn rule_provider_catalog(
    target: MihomoTarget,
) -> Result<Vec<RuleProviderEntry>, MihomoError> {
    let raw = target.client()?.get_json("providers/rules").await?;
    let Some(providers) = raw.get("providers").and_then(Value::as_object) else {
        return Ok(Vec::new());
    };
    let mut list = Vec::with_capacity(providers.len());
    for (name, data) in providers {
        let vehicle_type = field_or(data, "vehicleType", "");
        list.push(RuleProviderEntry {
            name: name.clone(),
            behavior: field_or(data, "behavior", ""),
            format: field_or(data, "format", ""),
            rule_count: data.get("ruleCount").map(value_to_u32).unwrap_or_default(),
            updatable: vehicle_type.eq_ignore_ascii_case("http"),
            vehicle_type,
            updated_at: field_or(data, "updatedAt", ""),
        });
    }
    list.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(list)
}

pub async fn rule_provider_update(target: MihomoTarget, name: String) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::PUT,
            &format!("providers/rules/{}", urlencode(&name)),
            None,
        )
        .await?;
    Ok(())
}

fn field_or(value: &Value, key: &str, default: &str) -> String {
    value
        .get(key)
        .filter(|v| !v.is_null())
        .map(value_to_string)
        .unwrap_or_else(|| default.to_string())
}

fn value_to_u32(value: &Value) -> u32 {
    if let Some(n) = value.as_u64() {
        return n as u32;
    }
    if let Some(n) = value.as_i64() {
        return n.max(0) as u32;
    }
    if let Some(n) = value.as_f64() {
        return n.max(0.0).round() as u32;
    }
    if let Some(s) = value.as_str() {
        return s.parse::<u32>().unwrap_or_default();
    }
    0
}

fn value_to_u64(value: &Value) -> u64 {
    if let Some(n) = value.as_u64() {
        return n;
    }
    if let Some(n) = value.as_i64() {
        return n.max(0) as u64;
    }
    if let Some(n) = value.as_f64() {
        return n.max(0.0).round() as u64;
    }
    if let Some(s) = value.as_str() {
        return s.parse::<u64>().unwrap_or_default();
    }
    0
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
