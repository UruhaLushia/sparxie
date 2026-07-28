use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};

use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{
    CLOSED_CAP, Connection, ConnectionGroup, ConnectionGroupSort, ConnectionsFrame,
    ConnectionsListKind, ConnectionsSort,
};
use crate::backend::retry::RetryBackoff;
use crate::sing_box::client::{SingBoxTarget, target_key as base_target_key};
use crate::sing_box::proto::daemon::SubscribeConnectionsRequest;

mod event;
mod parse;
mod sort;

use event::apply_events;
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

fn target_key(target: &SingBoxTarget, interval_ms: u32) -> String {
    format!("{}|{}", base_target_key(target), interval_ms)
}

async fn slot_for(target: &SingBoxTarget, interval_ms: u32) -> Option<Arc<TargetSlot>> {
    slots()
        .lock()
        .await
        .get(&target_key(target, interval_or_default(interval_ms)))
        .cloned()
}

pub async fn subscribe(
    target: SingBoxTarget,
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

pub async fn set_sort(target: SingBoxTarget, interval_ms: u32, sort: ConnectionsSort, asc: bool) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    let mut state = slot
        .state
        .lock()
        .expect("sing-box connections state poisoned");
    state.sort = sort;
    state.asc = asc;
}

pub async fn clear_closed(target: SingBoxTarget, interval_ms: u32) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    slot.state
        .lock()
        .expect("sing-box connections state poisoned")
        .closed
        .clear();
}

pub async fn clear_closed_by_group(target: SingBoxTarget, interval_ms: u32, group: String) {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return;
    };
    slot.state
        .lock()
        .expect("sing-box connections state poisoned")
        .closed
        .retain(|row| !connection_in_group(row, &group));
}

pub async fn fetch_window(
    target: SingBoxTarget,
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
    let state = slot
        .state
        .lock()
        .expect("sing-box connections state poisoned");
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
    target: SingBoxTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    sort: ConnectionGroupSort,
    asc: bool,
    query: String,
) -> Vec<ConnectionGroup> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let state = slot
        .state
        .lock()
        .expect("sing-box connections state poisoned");
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
            .or_insert_with(|| initial_group(row, key));
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
    target: SingBoxTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    group: String,
    limit: u32,
    query: String,
) -> Vec<Connection> {
    let Some(slot) = slot_for(&target, interval_ms).await else {
        return Vec::new();
    };
    let state = slot
        .state
        .lock()
        .expect("sing-box connections state poisoned");
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

async fn stream_loop(target: SingBoxTarget, interval_ms: u32, key: String, slot: Arc<TargetSlot>) {
    let mut backoff = RetryBackoff::new();
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        match stream_once(&target, interval_ms, &slot).await {
            Ok(()) => backoff.reset(),
            Err(error) => {
                eprintln!("[backend] sing-box connections stream {key}: {error}");
                tokio::time::sleep(backoff.next_delay()).await;
            }
        }
    }
}

async fn stream_once(
    target: &SingBoxTarget,
    interval_ms: u32,
    slot: &TargetSlot,
) -> Result<(), MihomoError> {
    let request = SubscribeConnectionsRequest {
        interval: (interval_ms as i64) * 1_000_000,
    };
    let mut stream = target
        .client()
        .await?
        .subscribe_connections(request)
        .await?
        .into_inner();
    let mut first = true;
    loop {
        let events = tokio::select! {
            biased;
            _ = slot.sender.closed() => return Ok(()),
            read = stream.message() => match read? {
                Some(events) => events,
                None => return Ok(()),
            },
        };
        let frame = apply_events(target, slot, events, interval_ms, first);
        first = false;
        let _ = slot.sender.send(frame);
    }
}

fn push_closed(state: &mut State, row: Connection) {
    if state.closed.len() >= CLOSED_CAP {
        state.closed.pop_front();
    }
    state.closed.push_back(row);
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

fn initial_group(row: &Connection, key: String) -> ConnectionGroup {
    ConnectionGroup {
        key,
        label: if row.process.is_empty() {
            row.source_ip.clone()
        } else {
            row.process.clone()
        },
        process: row.process.clone(),
        process_path: row.process_path.clone(),
        source_ip: row.source_ip.clone(),
        ..Default::default()
    }
}
