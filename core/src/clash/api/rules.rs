use reqwest::Method;
use serde_json::Value;

use crate::MihomoError;

use super::MihomoTarget;

#[derive(Clone, Debug, Default)]
pub struct RuleEntry {
    pub index: u32,
    pub rule_type: String,
    pub payload: String,
    pub proxy: String,
    pub extra_params: Vec<String>,
    pub disabled: bool,
    pub hit_count: u64,
    pub hit_at: String,
    pub miss_count: u64,
    pub miss_at: String,
    pub has_extra: bool,
}

pub async fn fetch_rules(target: MihomoTarget) -> Result<Vec<RuleEntry>, MihomoError> {
    let raw = target.client()?.get_json("rules").await?;
    Ok(raw
        .get("rules")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(parse_rule)
        .collect())
}

pub async fn rules_disable(
    target: MihomoTarget,
    index: u32,
    disabled: bool,
) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::PATCH,
            "rules/disable",
            Some(serde_json::json!({ index.to_string(): disabled })),
        )
        .await?;
    Ok(())
}

fn parse_rule(item: &Value) -> RuleEntry {
    let extra = item.get("extra").filter(|value| value.is_object());
    let extra_field = |key| extra.and_then(|value| value.get(key));
    let extra_string = |key| {
        extra
            .map(|value| take_string(value, key))
            .unwrap_or_default()
    };
    RuleEntry {
        index: item.get("index").and_then(Value::as_u64).unwrap_or(0) as u32,
        rule_type: take_string(item, "type"),
        payload: take_string(item, "payload"),
        proxy: take_string(item, "proxy"),
        extra_params: Vec::new(),
        disabled: extra_field("disabled")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        hit_count: extra_field("hitCount").and_then(Value::as_u64).unwrap_or(0),
        hit_at: extra_string("hitAt"),
        miss_count: extra_field("missCount")
            .and_then(Value::as_u64)
            .unwrap_or(0),
        miss_at: extra_string("missAt"),
        has_extra: extra.is_some(),
    }
}

fn take_string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}
