use serde_json::Value;

use crate::backend::api::Connection;

use super::time::unix_seconds_to_iso;
use super::value::{first_string, first_u32, first_u64, string_list, value_to_string};

pub(super) fn request_items(raw: &Value) -> Vec<&Value> {
    if let Some(arr) = raw.as_array() {
        return arr.iter().collect();
    }
    for key in ["requests", "active", "data"] {
        if let Some(arr) = raw.get(key).and_then(Value::as_array) {
            return arr.iter().collect();
        }
    }
    Vec::new()
}

pub(super) fn parse_request(item: &Value) -> Connection {
    let endpoint = parse_endpoint(&first_string(item, &["URL", "url", "remoteHost", "host"]));
    let destination_ip = clean_remote_address(
        &first_string(item, &["remoteAddress", "destinationIP", "destinationIp"])
            .unwrap_or_default(),
    )
    .unwrap_or_else(|| endpoint.host.clone());
    let policy_node =
        first_string(item, &["policyName", "policy", "rulePolicy"]).unwrap_or_default();
    let policy_group = first_string(item, &["originalPolicyName"]).unwrap_or_default();
    let method = first_string(item, &["method", "protocol"]).unwrap_or_default();
    let mut chains = Vec::new();
    if !policy_node.is_empty() {
        chains.push(policy_node.clone());
    }
    if !policy_group.is_empty() && policy_group != policy_node {
        chains.push(policy_group);
    }
    let explicit_port = first_u32(item, &["destinationPort", "remotePort"]);
    let (rule, rule_payload) = split_rule(
        &first_string(item, &["rule", "ruleName"])
            .or_else(|| first_string(item, &["rulePayload", "ruleValue"])),
    );

    Connection {
        id: value_to_string(item.get("id"))
            .or_else(|| value_to_string(item.get("requestId")))
            .unwrap_or_default(),
        host: endpoint.display_host,
        conn_type: method,
        source_ip: first_string(
            item,
            &[
                "sourceAddress",
                "sourceIP",
                "sourceIp",
                "clientIP",
                "clientAddress",
            ],
        )
        .unwrap_or_default(),
        source_port: first_u32(item, &["sourcePort", "clientPort"]),
        destination_ip,
        destination_port: if explicit_port == 0 {
            endpoint.port
        } else {
            explicit_port
        },
        inbound_ip: first_string(item, &["localAddress"]).unwrap_or_default(),
        inbound_name: first_string(item, &["interface"]).unwrap_or_default(),
        uid: first_u32(item, &["uid", "pid"]),
        process: first_string(item, &["process", "processName", "application"]).unwrap_or_default(),
        process_path: first_string(item, &["processPath", "applicationPath"]).unwrap_or_default(),
        rule,
        rule_payload,
        chains,
        connection_logs: string_list(item, &["notes"]),
        special_proxy: policy_node,
        special_rules: first_string(item, &["status", "remark"]).unwrap_or_default(),
        remote_destination: first_string(item, &["URL", "url", "remoteHost"]).unwrap_or_default(),
        sniff_host: endpoint.sniff_host,
        upload: first_u64(item, &["outBytes", "upload", "uploadTotal"]),
        download: first_u64(item, &["inBytes", "download", "downloadTotal"]),
        upload_speed: first_u64(item, &["outCurrentSpeed", "uploadSpeed"]),
        download_speed: first_u64(item, &["inCurrentSpeed", "downloadSpeed"]),
        start: start_time(item),
        ..Default::default()
    }
}

struct Endpoint {
    display_host: String,
    host: String,
    port: u32,
    sniff_host: String,
}

fn parse_endpoint(raw: &Option<String>) -> Endpoint {
    let raw = raw.as_deref().unwrap_or_default().trim();
    let (address, hint) = split_hint(raw);
    let (host, port) = split_host_port(address);
    let sniff_host = hint.filter(|value| value != "Port Map").unwrap_or_default();
    let display_host = if sniff_host.is_empty() {
        host.clone()
    } else {
        sniff_host.clone()
    };
    Endpoint {
        display_host,
        host,
        port,
        sniff_host,
    }
}

fn split_hint(raw: &str) -> (&str, Option<String>) {
    let Some((address, rest)) = raw.rsplit_once(" (") else {
        return (raw, None);
    };
    let hint = rest.strip_suffix(')').unwrap_or(rest).trim();
    if hint.is_empty() {
        (address.trim(), None)
    } else {
        (address.trim(), Some(hint.to_string()))
    }
}

fn split_host_port(raw: &str) -> (String, u32) {
    let raw = raw.trim();
    if let Some(rest) = raw.strip_prefix('[')
        && let Some((host, suffix)) = rest.split_once(']')
    {
        let port = suffix
            .strip_prefix(':')
            .and_then(|value| value.parse().ok())
            .unwrap_or_default();
        return (host.to_string(), port);
    }
    let Some((host, port)) = raw.rsplit_once(':') else {
        return (raw.to_string(), 0);
    };
    if port.chars().all(|ch| ch.is_ascii_digit()) {
        (host.to_string(), port.parse().unwrap_or_default())
    } else {
        (raw.to_string(), 0)
    }
}

fn clean_remote_address(raw: &str) -> Option<String> {
    let value = raw.split(" (").next().unwrap_or(raw).trim();
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

fn split_rule(raw: &Option<String>) -> (String, String) {
    let raw = raw.as_deref().unwrap_or_default().trim();
    if raw.is_empty() {
        return (String::new(), String::new());
    }
    for delimiter in [' ', ','] {
        if let Some((rule_type, payload)) = raw.split_once(delimiter) {
            return (
                rule_type.trim().to_string(),
                payload.trim_start_matches(delimiter).trim().to_string(),
            );
        }
    }
    if let Some((rule_type, payload)) = raw.split_once('(') {
        return (
            rule_type.trim().to_string(),
            format!("({}", payload.trim()).trim().to_string(),
        );
    }
    (raw.to_string(), String::new())
}

fn start_time(item: &Value) -> String {
    first_string(item, &["start", "startTime", "createdAt"])
        .or_else(|| unix_seconds_to_iso(item.get("startDate")?))
        .unwrap_or_default()
}

pub(super) fn fallback_id(conn: &Connection) -> String {
    format!(
        "{}|{}|{}|{}|{}",
        conn.host, conn.source_ip, conn.destination_ip, conn.destination_port, conn.start
    )
}
