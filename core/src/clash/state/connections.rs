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

use groups::{conn_in_group, connection_groups, group_connections_by_order};
use ordering::sort_rows;
use stream::stream_loop;
pub use types::*;

#[derive(Default)]
pub(super) struct State {
    pub(super) active: HashMap<String, Connection>,
    pub(super) closed: VecDeque<Connection>,
    closed_capacity: usize,
    sort: ConnectionsSort,
    asc: bool,
    active_version: u64,
    sorted_active_ids: Vec<String>,
    sorted_active_version: u64,
    sorted_active_sort: ConnectionsSort,
    sorted_active_asc: bool,
    sorted_active_valid: bool,
}

impl State {
    fn new(closed_capacity: usize) -> Self {
        Self {
            closed_capacity: closed_capacity.max(1),
            ..Self::default()
        }
    }

    fn set_closed_capacity(&mut self, closed_capacity: usize) {
        self.closed_capacity = closed_capacity.max(1);
        while self.closed.len() > self.closed_capacity {
            self.closed.pop_front();
        }
        if self.closed.capacity() > self.closed_capacity {
            self.closed.shrink_to(self.closed_capacity);
        }
    }

    pub(super) fn push_closed(&mut self, row: Connection) {
        if self.closed.len() >= self.closed_capacity {
            self.closed.pop_front();
        }
        self.closed.push_back(row);
    }

    fn clear_closed(&mut self) {
        self.closed = VecDeque::new();
    }

    pub(super) fn mark_active_changed(&mut self, release_stale_ids: bool) {
        self.active_version = self.active_version.wrapping_add(1);
        self.sorted_active_valid = false;
        if !release_stale_ids {
            return;
        }
        self.sorted_active_ids.clear();
        let active_len = self.active.len();
        if self.sorted_active_ids.capacity() > active_len.saturating_mul(2).max(64) {
            self.sorted_active_ids.shrink_to(active_len);
        }
        if self.active.capacity() > active_len.saturating_mul(4).max(64) {
            self.active.shrink_to_fit();
        }
    }
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
    closed_capacity: usize,
) -> Result<broadcast::Receiver<ConnectionsFrame>, MihomoError> {
    let interval = interval_or_default(interval_ms);
    let key = target_key(&target, interval);
    let mut map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        slot.state
            .lock()
            .expect("connections state poisoned")
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
    state.clear_closed();
}

pub async fn clear_closed_by_group(target: MihomoTarget, interval_ms: u32, group: String) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    let mut state = slot.state.lock().expect("connections state poisoned");
    state.closed.retain(|conn| !conn_in_group(conn, &group));
    state.closed.shrink_to_fit();
}

/// Slice the sorted list (active or closed) at `[offset, offset + limit)`.
pub async fn fetch_window(
    target: MihomoTarget,
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
    let mut state = slot.state.lock().expect("connections state poisoned");
    match kind {
        ConnectionsListKind::Active => {
            ensure_sorted_active_ids(&mut state);
            if query.is_empty() {
                let total = state.sorted_active_ids.len() as u32;
                let window = state
                    .sorted_active_ids
                    .iter()
                    .skip(offset as usize)
                    .take(limit as usize)
                    .filter_map(|id| state.active.get(id).cloned())
                    .collect();
                return (total, window);
            }
            let rows: Vec<_> = state
                .sorted_active_ids
                .iter()
                .filter_map(|id| state.active.get(id))
                .filter(|conn| conn.matches_query(&query))
                .collect();
            let total = rows.len() as u32;
            let window = rows
                .into_iter()
                .skip(offset as usize)
                .take(limit as usize)
                .cloned()
                .collect();
            (total, window)
        }
        ConnectionsListKind::Closed => {
            if query.is_empty() {
                let total = state.closed.len() as u32;
                let window = state
                    .closed
                    .iter()
                    .rev()
                    .skip(offset as usize)
                    .take(limit as usize)
                    .cloned()
                    .collect();
                return (total, window);
            }
            let rows: Vec<_> = state
                .closed
                .iter()
                .rev()
                .filter(|conn| conn.matches_query(&query))
                .collect();
            let total = rows.len() as u32;
            let window = rows
                .into_iter()
                .skip(offset as usize)
                .take(limit as usize)
                .cloned()
                .collect();
            (total, window)
        }
    }
}

/// Aggregate active or closed connections into source groups.
pub async fn fetch_groups(
    target: MihomoTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    sort: ConnectionGroupSort,
    asc: bool,
    query: String,
) -> Vec<ConnectionGroup> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let state = slot.state.lock().expect("connections state poisoned");
    match kind {
        ConnectionsListKind::Active => connection_groups(
            state.active.values(),
            sort,
            asc,
            &query.trim().to_lowercase(),
        ),
        ConnectionsListKind::Closed => connection_groups(
            state.closed.iter().rev(),
            sort,
            asc,
            &query.trim().to_lowercase(),
        ),
    }
}

/// Connections belonging to `group`, ordered like their source list.
pub async fn fetch_group_connections(
    target: MihomoTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    group: String,
    limit: u32,
    query: String,
) -> Vec<Connection> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let mut state = slot.state.lock().expect("connections state poisoned");
    let query = query.trim().to_lowercase();
    match kind {
        ConnectionsListKind::Active => {
            ensure_sorted_active_ids(&mut state);
            group_connections_by_order(
                &state.active,
                &state.sorted_active_ids,
                &group,
                limit,
                &query,
            )
        }
        ConnectionsListKind::Closed => state
            .closed
            .iter()
            .rev()
            .filter(|conn| conn_in_group(conn, &group) && conn.matches_query(&query))
            .take(limit as usize)
            .cloned()
            .collect(),
    }
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
