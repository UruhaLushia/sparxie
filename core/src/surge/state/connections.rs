use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{
    CLOSED_CAP, Connection, ConnectionGroup, ConnectionGroupSort, ConnectionsFrame,
    ConnectionsListKind, ConnectionsSort, ConnectionsTotals,
};
use crate::backend::retry::RetryBackoff;
use crate::surge::api::traffic_sample;
use crate::surge::client::{SurgeTarget, target_key as base_target_key};

mod parse;
mod sort;
mod time;
mod value;

use parse::{fallback_id, parse_request, request_items};
use sort::{sort_groups, sort_rows};

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

type SlotMap = HashMap<String, Arc<TargetSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

fn interval_or_default(interval_ms: u32) -> u32 {
    if interval_ms == 0 { 1000 } else { interval_ms }
}

fn target_key(target: &SurgeTarget, interval_ms: u32) -> String {
    format!("{}|{}", base_target_key(target), interval_ms)
}

async fn slot_for(target: &SurgeTarget, interval_ms: u32) -> Option<Arc<TargetSlot>> {
    slots()
        .lock()
        .await
        .get(&target_key(target, interval_or_default(interval_ms)))
        .cloned()
}

pub async fn subscribe(
    target: SurgeTarget,
    interval_ms: u32,
) -> Result<broadcast::Receiver<ConnectionsFrame>, MihomoError> {
    let interval = interval_or_default(interval_ms);
    let key = target_key(&target, interval);
    let mut map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        return Ok(slot.sender.subscribe());
    }
    let (tx, rx) = broadcast::channel::<ConnectionsFrame>(64);
    let slot = Arc::new(TargetSlot {
        state: Mutex::new(State::default()),
        sender: tx,
    });
    map.insert(key.clone(), slot.clone());
    drop(map);
    tokio::spawn(stream_loop(target, interval, key, slot));
    Ok(rx)
}

pub async fn set_sort(target: SurgeTarget, interval_ms: u32, sort: ConnectionsSort, asc: bool) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    let mut state = slot.state.lock().expect("surge connections state poisoned");
    state.sort = sort;
    state.asc = asc;
}

pub async fn clear_closed(target: SurgeTarget, interval_ms: u32) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .closed
        .clear();
}

pub async fn clear_closed_by_group(target: SurgeTarget, interval_ms: u32, group: String) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .closed
        .retain(|row| !connection_in_group(row, &group));
}

pub async fn fetch_window(
    target: SurgeTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    offset: u32,
    limit: u32,
    query: String,
) -> (u32, Vec<Connection>) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return (0, Vec::new());
    };
    let query = query.trim().to_lowercase();
    let state = slot.state.lock().expect("surge connections state poisoned");
    let mut rows: Vec<Connection> = match kind {
        ConnectionsListKind::Active => state.active.values().cloned().collect(),
        ConnectionsListKind::Closed => state.closed.iter().rev().cloned().collect(),
    };
    sort_rows(&mut rows, state.sort, state.asc);
    rows.retain(|row| row.matches_query(&query));
    let total = rows.len() as u32;
    let window = rows
        .into_iter()
        .skip(offset as usize)
        .take(limit as usize)
        .collect();
    (total, window)
}

pub async fn fetch_groups(
    target: SurgeTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    sort: ConnectionGroupSort,
    asc: bool,
    query: String,
) -> Vec<ConnectionGroup> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let state = slot.state.lock().expect("surge connections state poisoned");
    let mut groups: HashMap<String, ConnectionGroup> = HashMap::new();
    let rows: Vec<&Connection> = match kind {
        ConnectionsListKind::Active => state.active.values().collect(),
        ConnectionsListKind::Closed => state.closed.iter().rev().collect(),
    };
    let query = query.trim().to_lowercase();
    let matching_groups = (!query.is_empty()).then(|| {
        rows.iter()
            .filter(|row| row.matches_query(&query))
            .map(|row| connection_group_key(row))
            .collect::<HashSet<_>>()
    });
    for row in rows.into_iter().filter(|row| {
        matching_groups
            .as_ref()
            .is_none_or(|groups| groups.contains(&connection_group_key(row)))
    }) {
        let key = connection_group_key(row);
        let entry = groups
            .entry(key.clone())
            .or_insert_with(|| ConnectionGroup {
                key: key.clone(),
                label: if key.is_empty() {
                    "未知".into()
                } else {
                    key.clone()
                },
                process: row.process.clone(),
                process_path: row.process_path.clone(),
                source_ip: row.source_ip.clone(),
                ..Default::default()
            });
        entry.count += 1;
        entry.upload = entry.upload.saturating_add(row.upload);
        entry.download = entry.download.saturating_add(row.download);
        entry.upload_speed = entry.upload_speed.saturating_add(row.upload_speed);
        entry.download_speed = entry.download_speed.saturating_add(row.download_speed);
    }
    let mut out: Vec<_> = groups.into_values().collect();
    sort_groups(&mut out, sort, asc);
    out
}

pub async fn fetch_group_connections(
    target: SurgeTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    group: String,
    limit: u32,
    query: String,
) -> Vec<Connection> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let state = slot.state.lock().expect("surge connections state poisoned");
    let mut rows: Vec<Connection> = match kind {
        ConnectionsListKind::Active => state
            .active
            .values()
            .filter(|row| connection_in_group(row, &group))
            .cloned()
            .collect(),
        ConnectionsListKind::Closed => state
            .closed
            .iter()
            .rev()
            .filter(|row| connection_in_group(row, &group))
            .cloned()
            .collect(),
    };
    let query = query.trim().to_lowercase();
    rows.retain(|row| row.matches_query(&query));
    sort_rows(&mut rows, state.sort, state.asc);
    rows.into_iter().take(limit as usize).collect()
}

fn connection_group_key(row: &Connection) -> String {
    if row.process.is_empty() {
        row.source_ip.clone()
    } else {
        row.process.clone()
    }
}

fn connection_in_group(row: &Connection, group: &str) -> bool {
    if row.process.is_empty() {
        row.source_ip == group
    } else {
        row.process == group
    }
}

async fn stream_loop(target: SurgeTarget, interval_ms: u32, key: String, slot: Arc<TargetSlot>) {
    let mut first = true;
    let mut backoff = RetryBackoff::new();
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        match fetch_snapshot(&target, interval_ms, &slot, first).await {
            Ok(frame) => {
                first = false;
                backoff.reset();
                let _ = slot.sender.send(frame);
                tokio::time::sleep(Duration::from_millis(interval_ms as u64)).await;
            }
            Err(error) => {
                eprintln!("[backend] surge connections stream {key}: {error}");
                tokio::time::sleep(backoff.next_delay()).await;
            }
        }
    }
}

async fn fetch_snapshot(
    target: &SurgeTarget,
    interval_ms: u32,
    slot: &TargetSlot,
    is_initial: bool,
) -> Result<ConnectionsFrame, MihomoError> {
    let client = target.client()?;
    let raw = client.get_json("v1/requests/active").await?;
    let traffic = traffic_sample(target.clone()).await.unwrap_or_default();
    let dt_secs = (interval_ms as f64 / 1000.0).max(0.05);

    let mut state = slot.state.lock().expect("surge connections state poisoned");
    let mut current_ids = HashSet::with_capacity(state.active.len());
    for item in request_items(&raw) {
        let mut conn = parse_request(item);
        if conn.id.is_empty() {
            conn.id = fallback_id(&conn);
        }
        if let Some(prev) = state.active.get(&conn.id) {
            if conn.upload_speed == 0 {
                conn.upload_speed =
                    (((conn.upload.saturating_sub(prev.upload)) as f64) / dt_secs).round() as u64;
            }
            if conn.download_speed == 0 {
                conn.download_speed = (((conn.download.saturating_sub(prev.download)) as f64)
                    / dt_secs)
                    .round() as u64;
            }
        }
        current_ids.insert(conn.id.clone());
        state.active.insert(conn.id.clone(), conn);
    }

    let removed: Vec<String> = state
        .active
        .keys()
        .filter(|id| !current_ids.contains(*id))
        .cloned()
        .collect();
    for id in removed {
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

    Ok(ConnectionsFrame {
        active_count: state.active.len() as u32,
        closed_count: state.closed.len() as u32,
        totals: ConnectionsTotals {
            upload: traffic.up_total,
            download: traffic.down_total,
            memory: 0,
            connections_in: 0,
            connections_out: 0,
        },
        is_initial,
    })
}
