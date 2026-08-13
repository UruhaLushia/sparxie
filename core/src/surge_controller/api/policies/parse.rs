use std::collections::HashMap;

use serde_json::Value;

use crate::surge_controller::api::{value_i32, value_string};

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

pub(super) fn source_members(items: &[Value]) -> Vec<SourceMember> {
    items
        .iter()
        .filter(|item| item.get("enabled").and_then(Value::as_bool).unwrap_or(true))
        .filter_map(|item| {
            let name = value_string(Some(item)).or_else(|| {
                ["name", "policy", "policyName"]
                    .iter()
                    .find_map(|key| value_string(item.get(*key)))
            })?;
            Some(SourceMember {
                proxy_type: ["typeDescription", "type", "policyType"]
                    .iter()
                    .find_map(|key| value_string(item.get(*key)))
                    .unwrap_or_else(|| {
                        if item.get("isGroup").and_then(Value::as_bool) == Some(true) {
                            "PolicyGroup".into()
                        } else {
                            "Policy".into()
                        }
                    }),
                delay_key: ["lineHash", "line_hash", "hash"]
                    .iter()
                    .find_map(|key| value_string(item.get(*key))),
                name,
            })
        })
        .collect()
}

pub(super) fn delay_map(raw: &Value) -> HashMap<String, i32> {
    let mut output = HashMap::new();
    collect_delays(raw, None, &mut output);
    output
}

fn collect_delays(raw: &Value, key: Option<&str>, output: &mut HashMap<String, i32>) {
    if let (Some(key), Some(delay)) = (key, value_i32(Some(raw))) {
        output.insert(key.to_string(), delay);
    }
    match raw {
        Value::Object(map) => {
            let name = ["name", "policy", "policyName", "lineHash"]
                .iter()
                .find_map(|key| value_string(map.get(*key)));
            if let (Some(name), Some(delay)) = (name, value_i32(Some(raw))) {
                output.insert(name, delay);
            }
            for (key, value) in map {
                collect_delays(value, Some(key), output);
            }
        }
        Value::Array(items) => {
            for item in items {
                collect_delays(item, None, output);
            }
        }
        _ => {}
    }
}

pub(super) fn selected_from_delays(raw: &Value, group: &str) -> Option<String> {
    let value = group_result(raw, group)?;
    if let Some(value) = value.as_str() {
        return Some(value.to_string());
    }
    ["policy", "policyName", "selected", "name"]
        .iter()
        .find_map(|key| value_string(value.get(*key)))
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
