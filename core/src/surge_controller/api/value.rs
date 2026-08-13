use std::collections::HashMap;

use serde_json::Value;

pub(crate) fn string_map(value: Option<&Value>) -> HashMap<String, String> {
    value
        .and_then(Value::as_object)
        .map(|map| {
            map.iter()
                .filter_map(|(key, value)| {
                    value_string(Some(value)).map(|value| (key.clone(), value))
                })
                .collect()
        })
        .unwrap_or_default()
}

pub(crate) fn value_string(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(value) => Some(value.clone()),
        Value::Number(value) => Some(value.to_string()),
        Value::Bool(value) => Some(value.to_string()),
        _ => None,
    }
}
