use std::collections::HashMap;

use serde_json::{Value, json};

pub(super) fn profile_general_config(profile: &str) -> Value {
    let general = parse_profile_section(profile, "general");
    let mut out = serde_json::Map::new();
    insert_bool(&mut out, &general, "allow-lan", &["allow-wifi-access"]);
    insert_bool(&mut out, &general, "ipv6", &["ipv6"]);
    insert_string(&mut out, &general, "log-level", &["log-level", "loglevel"]);
    insert_number(
        &mut out,
        &general,
        "port",
        &["wifi-access-http-port", "http-port", "port"],
    );
    insert_number(
        &mut out,
        &general,
        "socks-port",
        &["wifi-access-socks5-port", "socks5-port", "socks-port"],
    );
    insert_number(
        &mut out,
        &general,
        "mixed-port",
        &["mixed-port", "wifi-access-mixed-port"],
    );
    Value::Object(out)
}

pub(super) fn to_ui_mode(mode: &str) -> String {
    match mode.to_lowercase().as_str() {
        "proxy" | "global" => "global".into(),
        "direct" => "direct".into(),
        _ => "rule".into(),
    }
}

pub(super) fn to_surge_mode(mode: &str) -> &str {
    match mode.to_lowercase().as_str() {
        "global" | "proxy" => "proxy",
        "direct" => "direct",
        _ => "rule",
    }
}

fn parse_profile_section(profile: &str, wanted: &str) -> HashMap<String, String> {
    let mut current = String::new();
    let mut out = HashMap::new();
    for raw_line in profile.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if let Some(section) = line.strip_prefix('[').and_then(|s| s.split_once(']')) {
            current = section.0.trim().to_ascii_lowercase();
            continue;
        }
        if current != wanted {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        out.insert(
            key.trim().to_ascii_lowercase(),
            value
                .trim()
                .trim_matches('"')
                .trim_matches('\'')
                .to_string(),
        );
    }
    out
}

fn insert_bool(
    out: &mut serde_json::Map<String, Value>,
    source: &HashMap<String, String>,
    key: &str,
    candidates: &[&str],
) {
    if let Some(value) = first_value(source, candidates).and_then(parse_bool) {
        out.insert(key.into(), Value::Bool(value));
    }
}

fn insert_number(
    out: &mut serde_json::Map<String, Value>,
    source: &HashMap<String, String>,
    key: &str,
    candidates: &[&str],
) {
    if let Some(value) = first_value(source, candidates).and_then(|v| v.parse::<u64>().ok()) {
        out.insert(key.into(), json!(value));
    }
}

fn insert_string(
    out: &mut serde_json::Map<String, Value>,
    source: &HashMap<String, String>,
    key: &str,
    candidates: &[&str],
) {
    if let Some(value) = first_value(source, candidates).filter(|v| !v.is_empty()) {
        out.insert(key.into(), Value::String(value.to_string()));
    }
}

fn first_value<'a>(source: &'a HashMap<String, String>, candidates: &[&str]) -> Option<&'a str> {
    candidates
        .iter()
        .find_map(|key| source.get(*key).map(String::as_str))
}

fn parse_bool(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}
