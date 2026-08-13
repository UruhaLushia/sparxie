use std::collections::HashSet;

use serde_json::Value;

use crate::surge_controller::api::value_string;

use super::source::{GroupMeta, SourceMember};

pub(super) fn policy_group_names(raw: &Value) -> Vec<String> {
    ["policy-groups", "policyGroups", "groups"]
        .iter()
        .find_map(|key| raw.get(*key).and_then(Value::as_array))
        .map(|items| {
            items
                .iter()
                .filter_map(|item| value_string(Some(item)))
                .collect()
        })
        .unwrap_or_default()
}

pub(super) fn proxy_names(raw: &Value) -> HashSet<String> {
    raw.get("proxies")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|item| value_string(Some(item)))
        .collect()
}

pub(super) fn source_members(
    items: &[Value],
    local_proxies: &HashSet<String>,
    smart_info: Option<&Value>,
) -> Vec<SourceMember> {
    items
        .iter()
        .filter(|item| item.get("enabled").and_then(Value::as_bool).unwrap_or(true))
        .filter_map(|item| {
            let name = value_string(Some(item)).or_else(|| {
                ["name", "policy", "policyName"]
                    .iter()
                    .find_map(|key| value_string(item.get(*key)))
            })?;
            let delay_key = ["lineHash", "line_hash", "hash"]
                .iter()
                .find_map(|key| value_string(item.get(*key)));
            let is_group = item.get("isGroup").and_then(Value::as_bool) == Some(true);
            Some(SourceMember {
                proxy_type: ["typeDescription", "type", "policyType"]
                    .iter()
                    .find_map(|key| value_string(item.get(*key)))
                    .unwrap_or_else(|| {
                        if is_group {
                            "PolicyGroup".into()
                        } else {
                            "Policy".into()
                        }
                    }),
                test_key: if is_group || local_proxies.contains(&name) {
                    name.clone()
                } else {
                    delay_key.clone().unwrap_or_else(|| name.clone())
                },
                usage: delay_key
                    .as_ref()
                    .and_then(|key| smart_info?.get(key))
                    .and_then(|value| value.get("usage"))
                    .and_then(Value::as_i64)
                    .and_then(|usage| i32::try_from(usage).ok()),
                delay_key,
                name,
            })
        })
        .collect()
}

pub(super) fn auto_group_selection(raw: &Value, group: &str) -> Option<String> {
    let value = group_result(raw, group)?;
    if let Some(value) = value
        .as_array()
        .and_then(|values| values.first())
        .and_then(|value| value_string(Some(value)))
    {
        return Some(value);
    }
    value_string(Some(value)).or_else(|| {
        ["policy", "policyName", "selected", "name"]
            .iter()
            .find_map(|key| value_string(value.get(*key)))
    })
}

pub(super) fn is_auto_group(raw: &Value, group: &str) -> bool {
    group_result(raw, group).is_some()
}

fn group_result<'a>(raw: &'a Value, group: &str) -> Option<&'a Value> {
    match raw {
        Value::Object(map) => {
            if let Some(value) = map.get(group) {
                return Some(value);
            }
            if ["group", "groupName"]
                .iter()
                .any(|key| value_string(map.get(*key)).as_deref() == Some(group))
            {
                return Some(raw);
            }
            map.values().find_map(|value| group_result(value, group))
        }
        Value::Array(items) => items.iter().find_map(|value| group_result(value, group)),
        _ => None,
    }
}

pub(super) fn group_meta(detail: String) -> GroupMeta {
    let mut meta = GroupMeta {
        detail: detail.clone(),
        ..Default::default()
    };
    let Some((_, definition)) = detail.split_once('=') else {
        return meta;
    };
    let mut parts = definition.split(',').map(str::trim);
    let group_type = parts.next().unwrap_or_default().to_ascii_lowercase();
    meta.selectable = group_type == "select";
    meta.auto = matches!(
        group_type.as_str(),
        "smart" | "url-test" | "fallback" | "load-balance" | "subnet" | "ssid"
    );
    meta.proxy_type = group_type;
    for part in parts {
        let Some((key, value)) = part.split_once('=') else {
            continue;
        };
        match key.trim().to_ascii_lowercase().as_str() {
            "hidden" => {
                meta.hidden = value.trim() == "1" || value.trim().eq_ignore_ascii_case("true")
            }
            "icon-url" | "icon" => meta.icon = value.trim().to_string(),
            _ => {}
        }
    }
    meta
}

pub(super) fn group_type(group_type: &str) -> String {
    match group_type.to_ascii_lowercase().as_str() {
        "select" => "Selector".into(),
        "url-test" => "URLTest".into(),
        "load-balance" => "LoadBalance".into(),
        "fallback" => "Fallback".into(),
        "smart" => "Smart".into(),
        "subnet" => "Subnet".into(),
        "ssid" => "SSID".into(),
        "" => "Auto".into(),
        _ => group_type.to_string(),
    }
}

pub(super) fn member_hash<'a>(names: impl IntoIterator<Item = &'a str>) -> u32 {
    let mut hash: u32 = 2166136261;
    for name in names {
        for byte in name.as_bytes() {
            hash ^= u32::from(*byte);
            hash = hash.wrapping_mul(16777619);
        }
        hash ^= 0xff;
        hash = hash.wrapping_mul(16777619);
    }
    hash
}
