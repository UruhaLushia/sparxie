use crate::backend::api::Connection;
use crate::sing_box::proto::daemon::{Connection as PbConnection, ProcessInfo};

use super::super::time::unix_millis_to_iso;

pub(super) fn parse_connection(
    raw: PbConnection,
    upload_speed: u64,
    download_speed: u64,
) -> Connection {
    let (source_ip, source_port) = split_host_port(&raw.source);
    let (destination_ip, destination_port) = split_host_port(&raw.destination);
    let process_path = raw
        .process_info
        .as_ref()
        .map(|info| info.process_path.clone())
        .unwrap_or_default();
    let process = process_name(raw.process_info.as_ref(), &process_path);
    let (rule, rule_payload) = split_rule(&raw.rule);
    let mut chains = raw.chain_list;
    if chains.is_empty() && !raw.outbound.is_empty() {
        chains.push(raw.outbound.clone());
    }
    Connection {
        id: raw.id,
        host: if raw.domain.is_empty() {
            destination_ip.clone()
        } else {
            raw.domain.clone()
        },
        network: raw.network,
        conn_type: raw.protocol,
        source_ip,
        source_port,
        destination_ip,
        destination_port,
        inbound_name: raw.inbound,
        uid: raw
            .process_info
            .as_ref()
            .and_then(|info| u32::try_from(info.user_id).ok())
            .unwrap_or_default(),
        process,
        process_path,
        rule,
        rule_payload,
        chains,
        upload: non_negative(raw.uplink_total),
        download: non_negative(raw.downlink_total),
        upload_speed,
        download_speed,
        start: unix_millis_to_iso(raw.created_at),
        is_closed: raw.closed_at > 0,
        remote_destination: raw.destination,
        sniff_host: raw.domain,
        special_proxy: raw.outbound,
        special_rules: raw.outbound_type,
        ..Default::default()
    }
}

pub(super) fn closed_time(millis: i64) -> String {
    unix_millis_to_iso(millis)
}

pub(super) fn speed(delta: i64, dt_secs: f64) -> u64 {
    if delta <= 0 {
        0
    } else {
        ((delta as f64) / dt_secs).round() as u64
    }
}

fn process_name(info: Option<&ProcessInfo>, path: &str) -> String {
    if let Some(package) = info.and_then(|info| info.package_names.first()) {
        return package.clone();
    }
    path.rsplit(['/', '\\'])
        .next()
        .filter(|value| !value.is_empty())
        .unwrap_or_default()
        .to_string()
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

fn split_rule(raw: &str) -> (String, String) {
    let raw = raw.trim();
    if raw.is_empty() {
        return (String::new(), String::new());
    }
    for delimiter in [' ', ','] {
        if let Some((rule_type, payload)) = raw.split_once(delimiter) {
            return (rule_type.trim().to_string(), payload.trim().to_string());
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

fn non_negative(value: i64) -> u64 {
    if value < 0 { 0 } else { value as u64 }
}
