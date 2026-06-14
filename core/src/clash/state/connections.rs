//! Snapshot-based connections state with on-demand row pagination.
//!
//! mihomo's `/connections` WebSocket pushes a full snapshot every interval.
//! Rust keeps the authoritative active/closed rows and only emits frame counts;
//! Dart pages the actual rows via [`fetch_window`] as it scrolls.

mod groups;
mod ordering;
mod parse;
mod stream;
pub(crate) mod types;

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};

use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::clash::api::MihomoTarget;

use groups::{active_groups, group_connections_by_order};
use ordering::sort_rows;
use stream::stream_loop;
pub use types::*;

#[derive(Default)]
pub(super) struct State {
    pub(super) active: HashMap<String, Connection>,
    pub(super) closed: VecDeque<Connection>,
    sort: ConnectionsSort,
    asc: bool,
    active_version: u64,
    sorted_active_ids: Vec<String>,
    sorted_active_version: u64,
    sorted_active_sort: ConnectionsSort,
    sorted_active_asc: bool,
    sorted_active_valid: bool,
}

pub(super) struct TargetSlot {
    pub(super) state: Mutex<State>,
    pub(super) sender: broadcast::Sender<ConnectionsFrame>,
}

type SlotMap = HashMap<String, Arc<TargetSlot>>;

pub(super) fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

fn interval_or_default(interval_ms: u32) -> u32 {
    if interval_ms == 0 { 1000 } else { interval_ms }
}

fn target_key(target: &MihomoTarget, interval_ms: u32) -> String {
    format!(
        "{}|{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or(""),
        interval_ms,
    )
}

async fn slot_for(target: &MihomoTarget, interval_ms: u32) -> Option<Arc<TargetSlot>> {
    let interval = interval_or_default(interval_ms);
    let key = target_key(target, interval);
    slots().lock().await.get(&key).cloned()
}

pub async fn subscribe(
    target: MihomoTarget,
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

pub async fn set_sort(target: MihomoTarget, interval_ms: u32, sort: ConnectionsSort, asc: bool) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    let mut state = slot.state.lock().expect("connections state poisoned");
    state.sort = sort;
    state.asc = asc;
}

/// Drop the entire closed-connections FIFO for the given target/interval slot.
/// The next stream frame will report `closed_count = 0`.
pub async fn clear_closed(target: MihomoTarget, interval_ms: u32) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    let mut state = slot.state.lock().expect("connections state poisoned");
    state.closed.clear();
}

/// Slice the sorted list (active or closed) at `[offset, offset + limit)`.
pub async fn fetch_window(
    target: MihomoTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    offset: u32,
    limit: u32,
) -> Vec<Connection> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let mut state = slot.state.lock().expect("connections state poisoned");
    match kind {
        ConnectionsListKind::Active => {
            ensure_sorted_active_ids(&mut state);
            state
                .sorted_active_ids
                .iter()
                .skip(offset as usize)
                .take(limit as usize)
                .filter_map(|id| state.active.get(id).cloned())
                .collect()
        }
        ConnectionsListKind::Closed => state
            .closed
            .iter()
            .rev()
            .skip(offset as usize)
            .take(limit as usize)
            .cloned()
            .collect(),
    }
}

/// Aggregate active connections into source groups, ordered by `sort`.
pub async fn fetch_groups(
    target: MihomoTarget,
    interval_ms: u32,
    sort: ConnectionGroupSort,
    asc: bool,
) -> Vec<ConnectionGroup> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let state = slot.state.lock().expect("connections state poisoned");
    active_groups(state.active.values(), sort, asc)
}

/// Active connections belonging to `group`, sorted and capped at `limit`.
pub async fn fetch_group_connections(
    target: MihomoTarget,
    interval_ms: u32,
    group: String,
    limit: u32,
) -> Vec<Connection> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let mut state = slot.state.lock().expect("connections state poisoned");
    ensure_sorted_active_ids(&mut state);
    group_connections_by_order(&state.active, &state.sorted_active_ids, &group, limit)
}

fn ensure_sorted_active_ids(state: &mut State) {
    if state.sorted_active_valid
        && state.sorted_active_version == state.active_version
        && state.sorted_active_sort == state.sort
        && state.sorted_active_asc == state.asc
    {
        return;
    }

    let mut rows: Vec<&Connection> = state.active.values().collect();
    sort_rows(&mut rows, state.sort, state.asc);
    state.sorted_active_ids.clear();
    state.sorted_active_ids.reserve(rows.len());
    state
        .sorted_active_ids
        .extend(rows.into_iter().map(|conn| conn.id.clone()));
    state.sorted_active_version = state.active_version;
    state.sorted_active_sort = state.sort;
    state.sorted_active_asc = state.asc;
    state.sorted_active_valid = true;
}
