use serde_json::Value;

pub(super) fn take_string(value: &Value, keys: &[&str]) -> String {
    take_optional_string(value, keys).unwrap_or_default()
}

pub(super) fn take_optional_string(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| value_to_string(value.get(*key)))
        .filter(|s| !s.is_empty())
}

pub(super) fn first_u64(value: &Value, keys: &[&str]) -> u64 {
    keys.iter()
        .find_map(|key| value_to_u64(value.get(*key)))
        .unwrap_or_default()
}

pub(super) fn first_optional_i32(value: &Value, keys: &[&str]) -> Option<i32> {
    keys.iter().find_map(|key| value_to_i32(value.get(*key)?))
}

pub(super) fn string_array(value: &Value, keys: &[&str]) -> Vec<String> {
    if let Some(arr) = value.as_array() {
        return arr
            .iter()
            .filter_map(|item| item.as_str().map(str::to_owned))
            .collect();
    }
    keys.iter()
        .find_map(|key| value.get(*key).and_then(Value::as_array))
        .map(|arr| {
            arr.iter()
                .filter_map(|item| item.as_str().map(str::to_owned))
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

pub(super) fn value_to_i32(value: &Value) -> Option<i32> {
    match value {
        Value::Number(n) => n
            .as_i64()
            .map(|v| v as i32)
            .or_else(|| n.as_f64().map(|v| v.round() as i32)),
        Value::String(s) => s.parse().ok(),
        Value::Object(map) => ["delay", "latency", "rtt"]
            .iter()
            .find_map(|key| map.get(*key).and_then(value_to_i32)),
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
