use serde_json::Value;

pub(super) fn first_string(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| value_to_string(value.get(*key)))
        .filter(|s| !s.is_empty())
}

pub(super) fn first_u32(value: &Value, keys: &[&str]) -> u32 {
    first_u64(value, keys).min(u32::MAX as u64) as u32
}

pub(super) fn first_u64(value: &Value, keys: &[&str]) -> u64 {
    keys.iter()
        .find_map(|key| value_to_u64(value.get(*key)))
        .unwrap_or_default()
}

pub(super) fn string_list(value: &Value, keys: &[&str]) -> Vec<String> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(Value::as_array))
        .map(|arr| {
            arr.iter()
                .filter_map(|item| value_to_string(Some(item)))
                .collect()
        })
        .unwrap_or_default()
}

fn value_to_u64(value: Option<&Value>) -> Option<u64> {
    match value? {
        Value::Number(n) => n.as_u64().or_else(|| n.as_i64().map(|v| v.max(0) as u64)),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

pub(super) fn value_to_string(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    }
}
