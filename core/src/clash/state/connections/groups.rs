use std::collections::HashMap;

use super::ordering::sort_groups;
use super::types::{Connection, ConnectionGroup, ConnectionGroupSort};

/// Stable key + display label for mihomo's internally-generated connections
/// (DNS hijack, internal probes, etc.). These carry no source address or
/// process, so they'd otherwise collapse into one empty-key group.
const INNER_KEY: &str = "inner";
const INNER_LABEL: &str = "内部连接";

pub(super) fn connection_groups<'a, I>(
    connections: I,
    sort: ConnectionGroupSort,
    asc: bool,
) -> Vec<ConnectionGroup>
where
    I: IntoIterator<Item = &'a Connection>,
{
    let mut groups: HashMap<String, ConnectionGroup> = HashMap::new();
    for conn in connections {
        let gkey = group_key(conn);
        let group = groups
            .entry(gkey)
            .or_insert_with_key(|key| initial_group(conn, key.clone()));
        group.count += 1;
        group.upload = group.upload.saturating_add(conn.upload);
        group.download = group.download.saturating_add(conn.download);
        group.upload_speed = group.upload_speed.saturating_add(conn.upload_speed);
        group.download_speed = group.download_speed.saturating_add(conn.download_speed);
        // A group's first-seen member may lack a path even when later ones have it.
        if group.process_path.is_empty() && !conn.process_path.is_empty() {
            group.process_path = conn.process_path.clone();
        }
    }

    let mut rows: Vec<ConnectionGroup> = groups.into_values().collect();
    sort_groups(&mut rows, sort, asc);
    rows
}

pub(super) fn group_connections_by_order(
    active: &HashMap<String, Connection>,
    sorted_ids: &[String],
    group: &str,
    limit: u32,
) -> Vec<Connection> {
    let mut rows = Vec::new();
    for id in sorted_ids {
        if rows.len() >= limit as usize {
            break;
        }
        let Some(conn) = active.get(id).filter(|conn| conn_in_group(conn, group)) else {
            continue;
        };
        rows.push(conn.clone());
    }
    rows
}

pub(super) fn conn_in_group(conn: &Connection, group: &str) -> bool {
    if is_inner(conn) {
        group == INNER_KEY
    } else if !conn.process.is_empty() {
        conn.process == group
    } else {
        conn.source_ip == group
    }
}

fn initial_group(conn: &Connection, key: String) -> ConnectionGroup {
    ConnectionGroup {
        key,
        label: group_label(conn),
        // Inner connections have no owning process / source address.
        process: if is_inner(conn) {
            String::new()
        } else {
            conn.process.clone()
        },
        process_path: if is_inner(conn) {
            String::new()
        } else {
            conn.process_path.clone()
        },
        source_ip: if is_inner(conn) {
            String::new()
        } else {
            conn.source_ip.clone()
        },
        ..Default::default()
    }
}

/// True for connections mihomo generates itself (`metadata.type == "Inner"`),
/// which lack source IP / process info.
fn is_inner(conn: &Connection) -> bool {
    conn.conn_type.eq_ignore_ascii_case("inner")
}

/// Grouping key for a connection: a dedicated bucket for inner
/// connections, else the process name, else the source IP.
fn group_key(conn: &Connection) -> String {
    if is_inner(conn) {
        INNER_KEY.to_string()
    } else if !conn.process.is_empty() {
        conn.process.clone()
    } else {
        conn.source_ip.clone()
    }
}

fn group_label(conn: &Connection) -> String {
    if is_inner(conn) {
        INNER_LABEL.to_string()
    } else if !conn.process.is_empty() {
        conn.process.clone()
    } else {
        conn.source_ip.clone()
    }
}
