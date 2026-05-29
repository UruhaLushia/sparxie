//! Snapshot-based connections state with on-demand row pagination.
//!
//! mihomo's `/connections` WebSocket pushes a full snapshot every interval.
//! Instead of forwarding it (potentially tens of thousands of rows on a
//! noisy network) or trying to keep an incremental diff in sync (fragile
//! on mobile suspend/resume), we maintain authoritative state on the
//! Rust side:
//!
//! - `active`: id → row, refreshed from each upstream snapshot. Rows that
//!   disappear from one frame to the next are moved into `closed`.
//! - `closed`: a fixed-capacity FIFO of recently-disconnected connections.
//! - `sort` / `asc`: per-target sort key, set by Dart via [`set_sort`].
//!
//! The stream pushes only a [`ConnectionsFrame`] (totals + counts); Dart
//! pages the actual rows via [`fetch_window`] as it scrolls.

use std::collections::{HashMap, VecDeque};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::api::MihomoTarget;
use crate::client::{MihomoClient, read_ws_text};
use crate::error::MihomoError;

/// Closed-connections retention. Approximately 250–500 KB at full capacity.
pub const CLOSED_CAP: usize = 500;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Connection {
    pub id: String,
    pub host: String,
    pub network: String,
    pub conn_type: String,
    pub source_ip: String,
    pub source_port: u32,
    pub destination_ip: String,
    pub destination_port: u32,
    pub inbound_ip: String,
    pub inbound_port: u32,
    pub inbound_name: String,
    pub dns_mode: String,
    pub uid: u32,
    pub process: String,
    pub process_path: String,
    pub special_proxy: String,
    pub special_rules: String,
    pub remote_destination: String,
    pub sniff_host: String,
    pub rule: String,
    pub rule_payload: String,
    pub chains: Vec<String>,
    pub upload: u64,
    pub download: u64,
    pub upload_speed: u64,
    pub download_speed: u64,
    pub start: String,
    /// True for rows pulled from the [`closed`] buffer.
    pub is_closed: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionsTotals {
    pub upload: u64,
    pub download: u64,
    pub memory: u64,
}

/// Aggregate of all active connections sharing one process (or source IP
/// when the process is unknown). Totals/speeds sum over the group's active
/// connections only — a closed connection drops out of its group.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionGroup {
    pub key: String,
    pub label: String,
    pub process: String,
    pub process_path: String,
    pub source_ip: String,
    pub count: u32,
    pub upload: u64,
    pub download: u64,
    pub upload_speed: u64,
    pub download_speed: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionsFrame {
    pub active_count: u32,
    pub closed_count: u32,
    pub totals: ConnectionsTotals,
    /// True for the very first frame after each WS connect (or reconnect)
    /// so Dart knows to drop any stale row caches.
    pub is_initial: bool,
}

/// Which list a window slice is drawn from.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionsListKind {
    Active,
    Closed,
}

/// Sort key for the connections list. Mirrors Dart's `ConnectionsSort`.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionsSort {
    Time,
    Upload,
    Download,
    UploadSpeed,
    DownloadSpeed,
    Process,
}

impl Default for ConnectionsSort {
    fn default() -> Self {
        Self::Time
    }
}

/// Sort key for the process-group list. Mirrors Dart's `ConnectionGroupSort`.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionGroupSort {
    Name,
    Count,
    Upload,
    Download,
    UploadSpeed,
    DownloadSpeed,
}

impl Default for ConnectionGroupSort {
    fn default() -> Self {
        Self::Name
    }
}

#[derive(Default)]
struct State {
    active: HashMap<String, Connection>,
    closed: VecDeque<Connection>,
    sort: ConnectionsSort,
    asc: bool,
}

struct TargetSlot {
    state: Mutex<State>,
    sender: broadcast::Sender<ConnectionsFrame>,
}

type SlotMap = HashMap<String, std::sync::Arc<TargetSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

fn target_key(target: &MihomoTarget, interval_ms: u32) -> String {
    format!(
        "{}|{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or(""),
        interval_ms,
    )
}

pub async fn subscribe(
    target: MihomoTarget,
    interval_ms: u32,
) -> Result<broadcast::Receiver<ConnectionsFrame>, MihomoError> {
    let interval = if interval_ms == 0 { 1000 } else { interval_ms };
    let key = target_key(&target, interval);
    let mut map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        return Ok(slot.sender.subscribe());
    }
    let (tx, rx) = broadcast::channel::<ConnectionsFrame>(64);
    let slot = std::sync::Arc::new(TargetSlot {
        state: Mutex::new(State::default()),
        sender: tx,
    });
    map.insert(key.clone(), slot.clone());
    drop(map);
    tokio::spawn(stream_loop(target, interval, key, slot));
    Ok(rx)
}

pub async fn set_sort(
    target: MihomoTarget,
    interval_ms: u32,
    sort: ConnectionsSort,
    asc: bool,
) {
    let interval = if interval_ms == 0 { 1000 } else { interval_ms };
    let key = target_key(&target, interval);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        let mut state = slot.state.lock().expect("connections state poisoned");
        state.sort = sort;
        state.asc = asc;
    }
}

/// Drop the entire closed-connections FIFO for the given target/interval slot.
/// The next stream frame will report `closed_count = 0`. No-op if the slot
/// hasn't been spun up yet.
pub async fn clear_closed(target: MihomoTarget, interval_ms: u32) {
    let interval = if interval_ms == 0 { 1000 } else { interval_ms };
    let key = target_key(&target, interval);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        let mut state = slot.state.lock().expect("connections state poisoned");
        state.closed.clear();
    }
}

/// Slice the sorted list (active or closed) at `[offset, offset + limit)`.
/// Bounds-checked; returns fewer rows than `limit` near the tail.
pub async fn fetch_window(
    target: MihomoTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    offset: u32,
    limit: u32,
) -> Vec<Connection> {
    let interval = if interval_ms == 0 { 1000 } else { interval_ms };
    let key = target_key(&target, interval);
    let map = slots().lock().await;
    let Some(slot) = map.get(&key) else {
        return Vec::new();
    };
    let state = slot.state.lock().expect("connections state poisoned");
    let asc = state.asc;
    let sort = state.sort;
    match kind {
        ConnectionsListKind::Active => {
            let mut rows: Vec<Connection> = state.active.values().cloned().collect();
            sort_rows(&mut rows, sort, asc);
            slice(rows, offset, limit)
        }
        ConnectionsListKind::Closed => {
            // Closed buffer is back = newest; for stable indexing we walk
            // from newest to oldest.
            let rows: Vec<Connection> =
                state.closed.iter().rev().cloned().collect();
            slice(rows, offset, limit)
        }
    }
}

fn slice(rows: Vec<Connection>, offset: u32, limit: u32) -> Vec<Connection> {
    let start = (offset as usize).min(rows.len());
    let end = start.saturating_add(limit as usize).min(rows.len());
    rows[start..end].to_vec()
}

/// Grouping key for an active connection: its process name, or the source
/// IP when no process is reported (e.g. remote / non-local backends).
fn group_key(conn: &Connection) -> String {
    if !conn.process.is_empty() {
        conn.process.clone()
    } else {
        conn.source_ip.clone()
    }
}

/// Aggregate active connections into per-process groups, ordered by `sort`.
/// The per-target connection sort key orders connections *within* a group,
/// independent of how the groups themselves are ordered here.
pub async fn fetch_groups(
    target: MihomoTarget,
    interval_ms: u32,
    sort: ConnectionGroupSort,
    asc: bool,
) -> Vec<ConnectionGroup> {
    let interval = if interval_ms == 0 { 1000 } else { interval_ms };
    let key = target_key(&target, interval);
    let map = slots().lock().await;
    let Some(slot) = map.get(&key) else {
        return Vec::new();
    };
    let state = slot.state.lock().expect("connections state poisoned");

    let mut groups: HashMap<String, ConnectionGroup> = HashMap::new();
    for conn in state.active.values() {
        let gkey = group_key(conn);
        let group = groups.entry(gkey.clone()).or_insert_with(|| ConnectionGroup {
            key: gkey,
            label: if conn.process.is_empty() {
                conn.source_ip.clone()
            } else {
                conn.process.clone()
            },
            process: conn.process.clone(),
            process_path: conn.process_path.clone(),
            source_ip: conn.source_ip.clone(),
            ..Default::default()
        });
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

fn sort_groups(rows: &mut [ConnectionGroup], sort: ConnectionGroupSort, asc: bool) {
    match sort {
        ConnectionGroupSort::Name => {
            rows.sort_by(|a, b| {
                cmp_str(&a.label.to_lowercase(), &b.label.to_lowercase(), asc)
            })
        }
        ConnectionGroupSort::Count => {
            rows.sort_by(|a, b| cmp_u64(a.count as u64, b.count as u64, asc))
        }
        ConnectionGroupSort::Upload => rows.sort_by(|a, b| cmp_u64(a.upload, b.upload, asc)),
        ConnectionGroupSort::Download => {
            rows.sort_by(|a, b| cmp_u64(a.download, b.download, asc))
        }
        ConnectionGroupSort::UploadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.upload_speed, b.upload_speed, asc))
        }
        ConnectionGroupSort::DownloadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.download_speed, b.download_speed, asc))
        }
    }
}

/// Active connections belonging to `group`, sorted by the per-target sort
/// key and capped at `limit`.
pub async fn fetch_group_connections(
    target: MihomoTarget,
    interval_ms: u32,
    group: String,
    limit: u32,
) -> Vec<Connection> {
    let interval = if interval_ms == 0 { 1000 } else { interval_ms };
    let key = target_key(&target, interval);
    let map = slots().lock().await;
    let Some(slot) = map.get(&key) else {
        return Vec::new();
    };
    let state = slot.state.lock().expect("connections state poisoned");
    let mut rows: Vec<Connection> = state
        .active
        .values()
        .filter(|c| group_key(c) == group)
        .cloned()
        .collect();
    sort_rows(&mut rows, state.sort, state.asc);
    rows.truncate(limit as usize);
    rows
}

fn sort_rows(rows: &mut [Connection], sort: ConnectionsSort, asc: bool) {
    match sort {
        ConnectionsSort::Time => rows.sort_by(|a, b| cmp_str(&a.start, &b.start, asc)),
        ConnectionsSort::Upload => rows.sort_by(|a, b| cmp_u64(a.upload, b.upload, asc)),
        ConnectionsSort::Download => {
            rows.sort_by(|a, b| cmp_u64(a.download, b.download, asc))
        }
        ConnectionsSort::UploadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.upload_speed, b.upload_speed, asc))
        }
        ConnectionsSort::DownloadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.download_speed, b.download_speed, asc))
        }
        ConnectionsSort::Process => {
            rows.sort_by(|a, b| cmp_str(&a.process, &b.process, asc))
        }
    }
}

async fn stream_loop(
    target: MihomoTarget,
    interval_ms: u32,
    key: String,
    slot: std::sync::Arc<TargetSlot>,
) {
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        if let Err(error) = stream_once(&target, interval_ms, &slot).await {
            eprintln!("[mihomo_backend] connections stream {key}: {error}");
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    }
}

async fn stream_once(
    target: &MihomoTarget,
    interval_ms: u32,
    slot: &TargetSlot,
) -> Result<(), MihomoError> {
    let client = MihomoClient::new(&target.base_url, target.secret.clone(), target.allow_insecure)?;
    let path = format!("connections?interval={interval_ms}");
    let mut ws = client.open_ws(&path).await?;
    let mut first = true;

    while let Some(text) = read_ws_text(&mut ws).await? {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        let parsed: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let frame = apply_snapshot(slot, parsed, first, interval_ms);
        first = false;
        let _ = slot.sender.send(frame);
    }
    Ok(())
}

fn apply_snapshot(
    slot: &TargetSlot,
    raw: Value,
    is_initial: bool,
    interval_ms: u32,
) -> ConnectionsFrame {
    let upload_total = raw.get("uploadTotal").and_then(|v| v.as_u64()).unwrap_or(0);
    let download_total = raw
        .get("downloadTotal")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let memory = raw.get("memory").and_then(|v| v.as_u64()).unwrap_or(0);

    let dt_secs = (interval_ms as f64 / 1000.0).max(0.05);
    let mut state = slot.state.lock().expect("connections state poisoned");
    let mut current_ids = HashMap::with_capacity(state.active.len());

    if let Some(arr) = raw.get("connections").and_then(|v| v.as_array()) {
        for item in arr {
            let mut conn = parse_connection(item);
            if let Some(prev) = state.active.get(&conn.id) {
                conn.upload_speed =
                    (((conn.upload.saturating_sub(prev.upload)) as f64) / dt_secs).round() as u64;
                conn.download_speed = (((conn.download.saturating_sub(prev.download)) as f64)
                    / dt_secs)
                    .round() as u64;
            }
            current_ids.insert(conn.id.clone(), ());
            state.active.insert(conn.id.clone(), conn);
        }
    }

    let removed_ids: Vec<String> = state
        .active
        .keys()
        .filter(|id| !current_ids.contains_key(*id))
        .cloned()
        .collect();
    for id in removed_ids {
        if let Some(mut row) = state.active.remove(&id) {
            row.is_closed = true;
            row.upload_speed = 0;
            row.download_speed = 0;
            if state.closed.len() >= CLOSED_CAP {
                state.closed.pop_front();
            }
            state.closed.push_back(row);
        }
    }

    let active_count = state.active.len() as u32;
    let closed_count = state.closed.len() as u32;

    ConnectionsFrame {
        active_count,
        closed_count,
        totals: ConnectionsTotals {
            upload: upload_total,
            download: download_total,
            memory,
        },
        is_initial,
    }
}

fn cmp_u64(a: u64, b: u64, asc: bool) -> std::cmp::Ordering {
    if asc { a.cmp(&b) } else { b.cmp(&a) }
}

fn cmp_str(a: &str, b: &str, asc: bool) -> std::cmp::Ordering {
    if asc { a.cmp(b) } else { b.cmp(a) }
}

fn parse_connection(item: &Value) -> Connection {
    let metadata = item.get("metadata").cloned().unwrap_or(Value::Null);
    Connection {
        id: take_string(item, "id"),
        host: take_string(&metadata, "host"),
        network: take_string(&metadata, "network"),
        conn_type: take_string(&metadata, "type"),
        source_ip: take_string(&metadata, "sourceIP"),
        source_port: take_u32(&metadata, "sourcePort"),
        destination_ip: take_string(&metadata, "destinationIP"),
        destination_port: take_u32(&metadata, "destinationPort"),
        inbound_ip: take_string(&metadata, "inboundIP"),
        inbound_port: take_u32(&metadata, "inboundPort"),
        inbound_name: take_string(&metadata, "inboundName"),
        dns_mode: take_string(&metadata, "dnsMode"),
        uid: take_u32(&metadata, "uid"),
        process: take_string(&metadata, "process"),
        process_path: take_string(&metadata, "processPath"),
        special_proxy: take_string(&metadata, "specialProxy"),
        special_rules: take_string(&metadata, "specialRules"),
        remote_destination: take_string(&metadata, "remoteDestination"),
        sniff_host: take_string(&metadata, "sniffHost"),
        rule: take_string(item, "rule"),
        rule_payload: take_string(item, "rulePayload"),
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
        start: take_string(item, "start"),
        is_closed: false,
    }
}

fn take_string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string()
}

fn take_u32(value: &Value, key: &str) -> u32 {
    let raw = match value.get(key) {
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
