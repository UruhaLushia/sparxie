use serde_json::Value;

pub(super) fn first_field(value: &Value, keys: &[&str]) -> String {
    for key in keys {
        if let Some(v) = value.get(*key).filter(|v| !v.is_null()) {
            return value_to_string(v);
        }
    }
    String::new()
}

pub(super) fn field_or(value: &Value, key: &str, default: &str) -> String {
    value
        .get(key)
        .filter(|v| !v.is_null())
        .map(value_to_string)
        .unwrap_or_else(|| default.to_string())
}

pub(super) fn value_to_i32(value: &Value) -> i32 {
    if let Some(n) = value.as_i64() {
        return n as i32;
    }
    if let Some(n) = value.as_f64() {
        return n.round() as i32;
    }
    if let Some(s) = value.as_str() {
        return s.parse::<i32>().unwrap_or_default();
    }
    0
}

pub(crate) fn proxy_delay(value: &Value) -> i32 {
    value
        .get("history")
        .and_then(Value::as_array)
        .and_then(|history| history.last())
        .and_then(|sample| sample.get("delay"))
        .or_else(|| value.get("delay"))
        .map(value_to_i32)
        .unwrap_or(-1)
}

pub(super) fn value_to_string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}
