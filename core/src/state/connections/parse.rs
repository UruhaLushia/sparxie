use serde_json::Value;

use super::types::Connection;

pub(super) fn parse_connection(item: &Value) -> Connection {
    let metadata = item.get("metadata");
    Connection {
        id: take_string(Some(item), "id"),
        host: take_string(metadata, "host"),
        network: take_string(metadata, "network"),
        conn_type: take_string(metadata, "type"),
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
        upload: item.get("upload").and_then(|v| v.as_u64()).unwrap_or(0),
        download: item.get("download").and_then(|v| v.as_u64()).unwrap_or(0),
        upload_speed: 0,
        download_speed: 0,
        start: take_string(Some(item), "start"),
        is_closed: false,
    }
}

fn take_string(value: Option<&Value>, key: &str) -> String {
    value
        .and_then(|v| v.get(key))
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string()
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
