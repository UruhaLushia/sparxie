use serde_json::Value;

use super::types::Connection;

pub(super) fn parse_connection(item: &Value) -> Connection {
    let metadata = item.get("metadata");
    Connection {
        id: take_string(Some(item), "id"),
        host: take_string(metadata, "host"),
        network: take_string(metadata, "network"),
        conn_type: take_first_string(metadata, &["type", "inbound"]),
        source_ip: take_string(metadata, "sourceIP"),
        source_port: take_u32(metadata, "sourcePort"),
        destination_ip: take_string(metadata, "destinationIP"),
        destination_port: take_u32(metadata, "destinationPort"),
        inbound_ip: take_string(metadata, "inboundIP"),
        inbound_port: take_u32(metadata, "inboundPort"),
        inbound_name: take_string(metadata, "inboundName"),
        dns_mode: take_string(metadata, "dnsMode"),
        uid: take_u32(metadata, "uid"),
        process: take_string(metadata, "process"),
        process_path: take_string(metadata, "processPath"),
        special_proxy: take_string(metadata, "specialProxy"),
        special_rules: take_string(metadata, "specialRules"),
        remote_destination: take_string(metadata, "remoteDestination"),
        sniff_host: take_string(metadata, "sniffHost"),
        rule: take_string(Some(item), "rule"),
        rule_payload: take_string(Some(item), "rulePayload"),
        chains: item
            .get("chains")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default(),
        connection_logs: take_string_list(metadata, "log"),
        upload: take_counter(Some(item), "upload"),
        download: take_counter(Some(item), "download"),
        upload_speed: 0,
        download_speed: 0,
        start: take_string(Some(item), "start"),
        is_closed: false,
    }
}

fn take_string(value: Option<&Value>, key: &str) -> String {
    value_to_string(value.and_then(|v| v.get(key)))
}

fn take_u32(value: Option<&Value>, key: &str) -> u32 {
    let raw = match value.and_then(|v| v.get(key)) {
        Some(v) => v,
        None => return 0,
    };
    if let Some(n) = raw.as_u64() {
        return n.min(u32::MAX as u64) as u32;
    }
    if let Some(s) = raw.as_str() {
        return s.parse::<u32>().unwrap_or(0);
    }
    0
}

fn take_counter(value: Option<&Value>, key: &str) -> u64 {
    let Some(raw) = value.and_then(|v| v.get(key)) else {
        return 0;
    };
    raw.as_u64()
        .or_else(|| raw.get("total").and_then(Value::as_u64))
        .unwrap_or(0)
}

fn take_first_string(value: Option<&Value>, keys: &[&str]) -> String {
    keys.iter()
        .map(|key| take_string(value, key))
        .find(|s| !s.is_empty())
        .unwrap_or_default()
}

fn take_string_list(value: Option<&Value>, key: &str) -> Vec<String> {
    value
        .and_then(|v| v.get(key))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .map(|item| value_to_string(Some(item)))
                .collect()
        })
        .unwrap_or_default()
}

fn value_to_string(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Bool(b)) => b.to_string(),
        _ => String::new(),
    }
}
