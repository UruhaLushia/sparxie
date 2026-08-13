use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{
    Connection, ConnectionGroup, ConnectionGroupSort, ConnectionsFrame, ConnectionsListKind,
    ConnectionsSort, ConnectionsTotals,
};
use crate::backend::retry::RetryBackoff;
use crate::surge_controller::client::{SurgeControllerTarget, with_unary_connection};

use super::target::Target;

mod parse;
mod sort;
mod store;
mod time;
mod value;

use parse::{fallback_id, parse_request, request_items};
use store::State;

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

fn target_key(target: &Target, interval_ms: u32) -> String {
    format!("{}|{interval_ms}", target.key())
}

async fn slot_for(target: &Target, interval_ms: u32) -> Option<Arc<TargetSlot>> {
    slots()
        .lock()
        .await
        .get(&target_key(target, interval_or_default(interval_ms)))
        .cloned()
}

pub async fn subscribe(
    target: impl Into<Target>,
    interval_ms: u32,
    closed_capacity: usize,
) -> Result<broadcast::Receiver<ConnectionsFrame>, MihomoError> {
    let target = target.into();
    let interval = interval_or_default(interval_ms);
    let key = target_key(&target, interval);
    let mut map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        slot.state
            .lock()
            .expect("surge connections state poisoned")
            .set_closed_capacity(closed_capacity);
        return Ok(slot.sender.subscribe());
    }
    let (tx, rx) = broadcast::channel::<ConnectionsFrame>(64);
    let slot = Arc::new(TargetSlot {
        state: Mutex::new(State::new(closed_capacity)),
        sender: tx,
    });
    map.insert(key.clone(), slot.clone());
    drop(map);
    tokio::spawn(stream_loop(target, interval, key, slot));
    Ok(rx)
}

pub async fn set_sort(
    target: impl Into<Target>,
    interval_ms: u32,
    sort: ConnectionsSort,
    asc: bool,
) {
    let target = target.into();
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    let mut state = slot.state.lock().expect("surge connections state poisoned");
    state.set_sort(sort, asc);
}

pub async fn clear_closed(target: impl Into<Target>, interval_ms: u32) {
    let target = target.into();
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .clear_closed();
}

pub async fn clear_closed_by_group(target: impl Into<Target>, interval_ms: u32, group: String) {
    let target = target.into();
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .clear_closed_by_group(&group);
}

pub async fn fetch_window(
    target: impl Into<Target>,
    interval_ms: u32,
    kind: ConnectionsListKind,
    offset: u32,
    limit: u32,
    query: String,
) -> (u32, Vec<Connection>) {
    let target = target.into();
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return (0, Vec::new());
    };
    let query = query.trim().to_lowercase();
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .window(kind, offset, limit, &query)
}

/// Return one connection's volatile counters outside the paged window.
pub async fn fetch_connection_stats_by_id(
    target: impl Into<Target>,
    interval_ms: u32,
    id: String,
) -> Option<(u64, u64, u64, u64)> {
    let target = target.into();
    let slot = slot_for(&target, interval_ms).await?;
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .connection_stats(&id)
}

pub async fn fetch_groups(
    target: impl Into<Target>,
    interval_ms: u32,
    kind: ConnectionsListKind,
    sort: ConnectionGroupSort,
    asc: bool,
    query: String,
) -> Vec<ConnectionGroup> {
    let target = target.into();
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let query = query.trim().to_lowercase();
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .groups(kind, sort, asc, &query)
}

pub async fn fetch_group_connections(
    target: impl Into<Target>,
    interval_ms: u32,
    kind: ConnectionsListKind,
    group: String,
    limit: u32,
    query: String,
) -> Vec<Connection> {
    let target = target.into();
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let query = query.trim().to_lowercase();
    slot.state
        .lock()
        .expect("surge connections state poisoned")
        .group_connections(kind, &group, limit, &query)
}

async fn stream_loop(target: Target, interval_ms: u32, key: String, slot: Arc<TargetSlot>) {
    let mut first = true;
    let mut backoff = RetryBackoff::new();
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        let result = match &target {
            Target::Http(_) => fetch_snapshot(&target, interval_ms, &slot, first).await,
            Target::Controller(target) => {
                fetch_controller_snapshot(target, interval_ms, &slot, first).await
            }
        };
        match result {
            Ok(frame) => {
                first = false;
                backoff.reset();
                let _ = slot.sender.send(frame);
                tokio::time::sleep(Duration::from_millis(interval_ms as u64)).await;
            }
            Err(error) => {
                eprintln!("[backend] surge connections stream: {error}");
                tokio::time::sleep(backoff.next_delay()).await;
            }
        }
    }
}

async fn fetch_snapshot(
    target: &Target,
    interval_ms: u32,
    slot: &TargetSlot,
    is_initial: bool,
) -> Result<ConnectionsFrame, MihomoError> {
    let Target::Http(target) = target else {
        return Err(MihomoError::Other("无效的 Surge HTTP 状态目标".into()));
    };
    let raw = target.client()?.get_json("v1/requests/active").await?;
    apply_snapshot(&raw, interval_ms, slot, is_initial)
}

async fn fetch_controller_snapshot(
    target: &SurgeControllerTarget,
    interval_ms: u32,
    slot: &TargetSlot,
    is_initial: bool,
) -> Result<ConnectionsFrame, MihomoError> {
    let raw = with_unary_connection(target, |connection| {
        Box::pin(async move { connection.request(["dump", "active"]).await })
    })
    .await?;
    apply_snapshot(&raw, interval_ms, slot, is_initial)
}

fn apply_snapshot(
    raw: &serde_json::Value,
    interval_ms: u32,
    slot: &TargetSlot,
    is_initial: bool,
) -> Result<ConnectionsFrame, MihomoError> {
    let dt_secs = (interval_ms as f64 / 1000.0).max(0.05);

    let mut state = slot.state.lock().expect("surge connections state poisoned");
    let mut current_ids = HashSet::with_capacity(state.active.len());
    for item in request_items(raw) {
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
            state.push_closed(row);
        }
    }
    state.compact_active();

    Ok(ConnectionsFrame {
        active_count: state.active.len() as u32,
        closed_count: state.closed.len() as u32,
        totals: ConnectionsTotals::default(),
        is_initial,
    })
}
