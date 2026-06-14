use std::sync::{Mutex, OnceLock};

use serde_json::Value;

use crate::MihomoError;
use crate::backend::api::{RuleEntry, RulesSummary};
use crate::surge::client::{SurgeTarget, target_key};

struct RulesCache {
    key: String,
    all: Vec<RuleEntry>,
    filter: String,
    filtered: Vec<u32>,
}

impl RulesCache {
    fn summary(&self) -> RulesSummary {
        RulesSummary {
            total: self.all.len() as u32,
            filtered: self.filtered.len() as u32,
        }
    }

    fn recompute(&mut self) {
        let needle = self.filter.to_lowercase();
        self.filtered = self
            .all
            .iter()
            .enumerate()
            .filter(|(_, entry)| rule_matches(entry, &needle))
            .map(|(i, _)| i as u32)
            .collect();
    }
}

fn cache() -> &'static Mutex<Option<RulesCache>> {
    static C: OnceLock<Mutex<Option<RulesCache>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(None))
}

pub async fn count(target: SurgeTarget) -> u32 {
    let Ok(client) = target.client() else {
        return 0;
    };
    match client.get_json("v1/rules").await {
        Ok(raw) => rule_values(&raw).len() as u32,
        Err(_) => 0,
    }
}

pub async fn load(target: SurgeTarget, filter: String) -> Result<RulesSummary, MihomoError> {
    let raw = target.client()?.get_json("v1/rules").await?;
    let all = rule_values(&raw)
        .into_iter()
        .enumerate()
        .map(|(index, item)| parse_rule(index, &item))
        .collect();
    let mut cache = RulesCache {
        key: target_key(&target),
        all,
        filter,
        filtered: Vec::new(),
    };
    cache.recompute();
    let summary = cache.summary();
    *self::cache().lock().expect("surge rules cache poisoned") = Some(cache);
    Ok(summary)
}

pub async fn set_filter(target: SurgeTarget, filter: String) -> RulesSummary {
    let key = target_key(&target);
    let mut guard = cache().lock().expect("surge rules cache poisoned");
    match guard.as_mut() {
        Some(c) if c.key == key => {
            c.filter = filter;
            c.recompute();
            c.summary()
        }
        _ => RulesSummary::default(),
    }
}

pub async fn window(target: SurgeTarget, offset: u32, limit: u32) -> Vec<RuleEntry> {
    let key = target_key(&target);
    let guard = cache().lock().expect("surge rules cache poisoned");
    let Some(c) = guard.as_ref().filter(|c| c.key == key) else {
        return Vec::new();
    };
    let start = (offset as usize).min(c.filtered.len());
    let end = start.saturating_add(limit as usize).min(c.filtered.len());
    c.filtered[start..end]
        .iter()
        .filter_map(|&i| c.all.get(i as usize).cloned())
        .collect()
}

fn rule_values(raw: &Value) -> Vec<Value> {
    if let Some(arr) = raw.as_array() {
        return arr.clone();
    }
    for key in ["rules", "data"] {
        if let Some(arr) = raw.get(key).and_then(Value::as_array) {
            return arr.clone();
        }
    }
    Vec::new()
}

fn parse_rule(index: usize, item: &Value) -> RuleEntry {
    if let Some(raw) = item.as_str() {
        return parse_rule_line(index, raw);
    }
    RuleEntry {
        index: item
            .get("index")
            .and_then(Value::as_u64)
            .unwrap_or(index as u64) as u32,
        rule_type: take_string(item, &["type", "ruleType"]),
        payload: take_string(item, &["payload", "value", "content"]),
        proxy: take_string(item, &["proxy", "policy", "policyName"]),
        extra_params: take_string_list(item, &["extraParams", "params", "options"]),
        has_extra: false,
        ..Default::default()
    }
}

fn parse_rule_line(index: usize, raw: &str) -> RuleEntry {
    let parts: Vec<&str> = raw.split(',').map(str::trim).collect();
    let rule_type = parts.first().copied().unwrap_or_default().to_string();
    let proxy_index = parts
        .iter()
        .enumerate()
        .rev()
        .find(|(_, part)| !part.is_empty() && !is_option_part(part))
        .map(|(index, _)| index);
    let proxy = proxy_index
        .and_then(|index| parts.get(index))
        .copied()
        .unwrap_or_default()
        .to_string();
    let extra_params = proxy_index
        .map(|index| {
            parts[index.saturating_add(1)..]
                .iter()
                .filter(|part| is_option_part(part))
                .map(|part| (*part).to_string())
                .collect()
        })
        .unwrap_or_default();
    let payload = if let Some(index) = proxy_index.filter(|index| *index > 1) {
        parts[1..index].join(",")
    } else {
        String::new()
    };
    RuleEntry {
        index: index as u32,
        rule_type,
        payload,
        proxy,
        extra_params,
        has_extra: false,
        ..Default::default()
    }
}

fn is_option_part(part: &str) -> bool {
    let part = part.to_ascii_lowercase();
    matches!(
        part.as_str(),
        "no-resolve" | "extended-matching" | "pre-matching" | "force-remote-dns" | "dns-failed"
    ) || part.contains('=')
}

fn rule_matches(entry: &RuleEntry, needle: &str) -> bool {
    needle.is_empty()
        || entry.payload.to_lowercase().contains(needle)
        || entry.rule_type.to_lowercase().contains(needle)
        || entry.proxy.to_lowercase().contains(needle)
        || entry
            .extra_params
            .iter()
            .any(|param| param.to_lowercase().contains(needle))
}

fn take_string(value: &Value, keys: &[&str]) -> String {
    keys.iter()
        .find_map(|key| {
            value.get(*key).and_then(|v| match v {
                Value::String(s) => Some(s.clone()),
                Value::Number(n) => Some(n.to_string()),
                Value::Bool(b) => Some(b.to_string()),
                _ => None,
            })
        })
        .unwrap_or_default()
}

fn take_string_list(value: &Value, keys: &[&str]) -> Vec<String> {
    keys.iter()
        .find_map(|key| value.get(*key))
        .map(|value| match value {
            Value::Array(items) => items
                .iter()
                .filter_map(|item| match item {
                    Value::String(s) => Some(s.clone()),
                    Value::Number(n) => Some(n.to_string()),
                    Value::Bool(b) => Some(b.to_string()),
                    _ => None,
                })
                .collect(),
            Value::String(s) => s
                .split(',')
                .map(str::trim)
                .filter(|part| !part.is_empty())
                .map(str::to_string)
                .collect(),
            _ => Vec::new(),
        })
        .unwrap_or_default()
}
