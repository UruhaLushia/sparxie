use std::sync::Arc;

use reqwest::Method;
use serde_json::Value;

use crate::MihomoError;

use super::{MihomoTarget, ProxyMemberEntry, urlencode};

mod state;

pub(crate) use state::ProxyProviderData;
use state::{
    clear_proxy_cache, clear_rule_cache, invalidate_rule_cache, provider_node_detail,
    provider_node_entry, proxy_cache, rule_cache,
};

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

#[derive(Clone, Debug, Default)]
pub struct ProxyProviderNodeWindow {
    pub total: u32,
    pub filtered: u32,
    pub offset: u32,
    pub entries: Vec<ProxyMemberEntry>,
}

pub async fn proxy_provider_catalog(
    target: MihomoTarget,
    force: bool,
) -> Result<Vec<ProxyProviderEntry>, MihomoError> {
    let data = proxy_provider_data(target.clone(), force).await?;
    if force {
        super::proxies::clear_proxy_catalog_cache(&target);
    }
    Ok(data
        .snapshot
        .read()
        .expect("proxy provider snapshot poisoned")
        .catalog
        .clone())
}

pub(crate) async fn proxy_provider_data(
    target: MihomoTarget,
    force: bool,
) -> Result<Arc<ProxyProviderData>, MihomoError> {
    let key = target.identity_key();
    let previous = proxy_cache().get(&key);
    proxy_cache()
        .load(&key, force, || async move {
            let raw = target.client()?.get_json("providers/proxies").await?;
            let data = previous.unwrap_or_else(|| Arc::new(ProxyProviderData::default()));
            data.apply(&raw);
            Ok(data)
        })
        .await
}

pub(crate) async fn proxy_provider_detail(
    target: &MihomoTarget,
    name: &str,
    force: bool,
) -> Result<Option<String>, MihomoError> {
    let data = proxy_provider_data(target.clone(), false).await?;
    let provider = {
        let snapshot = data
            .snapshot
            .read()
            .expect("proxy provider snapshot poisoned");
        snapshot.nodes.iter().find_map(|(provider, nodes)| {
            nodes
                .iter()
                .any(|node| node.name.as_ref() == name)
                .then(|| provider.clone())
        })
    };
    let Some(provider) = provider else {
        return Ok(None);
    };
    if !force
        && let Some(detail) = data
            .details
            .lock()
            .expect("provider detail cache poisoned")
            .get(&provider, name)
    {
        return Ok(Some(detail));
    }

    let path = format!(
        "providers/proxies/{}/{}",
        urlencode(&provider),
        urlencode(name),
    );
    let client = target.client()?;
    let raw = match client.get_json(&path).await {
        Ok(raw) => raw,
        Err(individual_error) => {
            let all = match client.get_json("providers/proxies").await {
                Ok(all) => all,
                Err(_) => return Err(individual_error),
            };
            let Some(raw) = all
                .get("providers")
                .and_then(Value::as_object)
                .and_then(|providers| providers.get(&provider))
                .and_then(|provider| provider.get("proxies"))
                .and_then(Value::as_array)
                .and_then(|nodes| nodes.iter().find(|node| field_or(node, "name", "") == name))
                .cloned()
            else {
                return Err(individual_error);
            };
            raw
        }
    };
    let detail = provider_node_detail(raw, &provider);
    data.details
        .lock()
        .expect("provider detail cache poisoned")
        .insert(provider, name.to_string(), detail.clone());
    Ok(Some(detail))
}

pub(crate) fn update_proxy_provider_delays<'a>(
    target: &MihomoTarget,
    delays: impl IntoIterator<Item = (&'a str, i32)>,
) {
    if let Some(data) = proxy_cache().get(&target.identity_key()) {
        data.update_delays(delays);
    }
}

pub async fn proxy_provider_nodes(
    target: MihomoTarget,
    name: String,
    filter: String,
    offset: u32,
    limit: u32,
) -> Result<ProxyProviderNodeWindow, MihomoError> {
    let data = proxy_provider_data(target, false).await?;
    let snapshot = data
        .snapshot
        .read()
        .expect("proxy provider snapshot poisoned");
    let nodes = snapshot
        .nodes
        .get(&name)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let needle = filter.trim().to_lowercase();
    let limit = limit.clamp(1, 512);
    let total = nodes.len();
    let (filtered, entries) = if needle.is_empty() {
        let start = (offset as usize).min(total);
        let end = start.saturating_add(limit as usize).min(total);
        (
            total,
            nodes[start..end].iter().map(provider_node_entry).collect(),
        )
    } else {
        let mut filter = data.filter.lock().expect("provider filter cache poisoned");
        filter.update(&name, needle, nodes);
        let filtered = filter.indices.len();
        let start = (offset as usize).min(filtered);
        let end = start.saturating_add(limit as usize).min(filtered);
        let entries = filter.indices[start..end]
            .iter()
            .filter_map(|index| nodes.get(*index as usize))
            .map(provider_node_entry)
            .collect();
        (filtered, entries)
    };
    Ok(ProxyProviderNodeWindow {
        total: total.min(u32::MAX as usize) as u32,
        filtered: filtered.min(u32::MAX as usize) as u32,
        offset: offset.min(filtered.min(u32::MAX as usize) as u32),
        entries,
    })
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
    clear_proxy_cache(&target);
    super::proxies::clear_proxy_catalog_cache(&target);
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

pub async fn rule_provider_catalog(
    target: MihomoTarget,
    force: bool,
) -> Result<Vec<RuleProviderEntry>, MihomoError> {
    let key = target.identity_key();
    let list = rule_cache()
        .load(&key, force, || async move {
            let raw = target.client()?.get_json("providers/rules").await?;
            Ok(Arc::new(parse_rule_provider_catalog(&raw)))
        })
        .await?;
    Ok(list.as_ref().clone())
}

fn parse_rule_provider_catalog(raw: &Value) -> Vec<RuleProviderEntry> {
    let providers = raw.get("providers").and_then(Value::as_object);
    let mut list = Vec::with_capacity(providers.map_or(0, |providers| providers.len()));
    if let Some(providers) = providers {
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
    }
    list.sort_by(|a, b| a.name.cmp(&b.name));
    list
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
    invalidate_rule_cache(&target);
    Ok(())
}

pub fn clear_provider_cache(target: &MihomoTarget) {
    clear_proxy_cache(target);
    clear_rule_cache(target);
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
