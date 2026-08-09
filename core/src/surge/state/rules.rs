use serde_json::Value;

use crate::MihomoError;
use crate::backend::api::RuleEntry;
use crate::surge::client::SurgeTarget;

pub async fn load(target: SurgeTarget) -> Result<Vec<RuleEntry>, MihomoError> {
    let raw = target.client()?.get_json("v1/rules").await?;
    Ok(rule_values(&raw)
        .into_iter()
        .enumerate()
        .map(|(index, item)| parse_rule(index, &item))
        .collect())
}

fn rule_values(raw: &Value) -> Vec<Value> {
    if let Some(entries) = raw.as_array() {
        return entries.clone();
    }
    for key in ["rules", "data"] {
        if let Some(entries) = raw.get(key).and_then(Value::as_array) {
            return entries.clone();
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
        ..Default::default()
    }
}

fn parse_rule_line(index: usize, raw: &str) -> RuleEntry {
    let parts: Vec<&str> = raw.split(',').map(str::trim).collect();
    let proxy_index = parts
        .iter()
        .enumerate()
        .rev()
        .find(|(_, part)| !part.is_empty() && !is_option_part(part))
        .map(|(index, _)| index);
    RuleEntry {
        index: index as u32,
        rule_type: parts.first().copied().unwrap_or_default().to_string(),
        payload: proxy_index
            .filter(|index| *index > 1)
            .map(|index| parts[1..index].join(","))
            .unwrap_or_default(),
        proxy: proxy_index
            .and_then(|index| parts.get(index))
            .copied()
            .unwrap_or_default()
            .to_string(),
        extra_params: proxy_index
            .map(|index| {
                parts[index.saturating_add(1)..]
                    .iter()
                    .filter(|part| is_option_part(part))
                    .map(|part| (*part).to_string())
                    .collect()
            })
            .unwrap_or_default(),
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

fn take_string(value: &Value, keys: &[&str]) -> String {
    keys.iter()
        .find_map(|key| {
            value.get(*key).and_then(|value| match value {
                Value::String(value) => Some(value.clone()),
                Value::Number(value) => Some(value.to_string()),
                Value::Bool(value) => Some(value.to_string()),
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
                    Value::String(value) => Some(value.clone()),
                    Value::Number(value) => Some(value.to_string()),
                    Value::Bool(value) => Some(value.to_string()),
                    _ => None,
                })
                .collect(),
            Value::String(value) => value
                .split(',')
                .map(str::trim)
                .filter(|part| !part.is_empty())
                .map(str::to_string)
                .collect(),
            _ => Vec::new(),
        })
        .unwrap_or_default()
}
