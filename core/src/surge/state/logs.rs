use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::LogEntry;
use crate::backend::retry::RetryBackoff;
use crate::surge::client::{SurgeTarget, target_key};

const LOGS_CAP: usize = 500;

struct LogSlot {
    state: Mutex<LogState>,
    sender: broadcast::Sender<LogEntry>,
}

#[derive(Default)]
struct LogState {
    buffer: VecDeque<(String, LogEntry)>,
    seen: HashSet<String>,
}

type SlotMap = HashMap<String, Arc<LogSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

fn slot_key(target: &SurgeTarget) -> String {
    target_key(target)
}

pub async fn subscribe(
    target: SurgeTarget,
    level: &str,
) -> Result<(Vec<LogEntry>, broadcast::Receiver<LogEntry>), MihomoError> {
    let key = slot_key(&target);
    let mut map = slots().lock().await;
    let slot = if let Some(slot) = map.get(&key) {
        slot.clone()
    } else {
        let (tx, _) = broadcast::channel::<LogEntry>(64);
        let slot = Arc::new(LogSlot {
            state: Mutex::new(LogState::default()),
            sender: tx,
        });
        map.insert(key.clone(), slot.clone());
        tokio::spawn(poll_loop(target, key, slot.clone()));
        slot
    };
    drop(map);

    let state = slot.state.lock().expect("surge logs state poisoned");
    let rx = slot.sender.subscribe();
    Ok((
        state
            .buffer
            .iter()
            .filter(|(_, entry)| level_allows(level, &entry.level))
            .map(|(_, entry)| entry.clone())
            .collect(),
        rx,
    ))
}

pub async fn clear(target: SurgeTarget, _level: &str) {
    let key = slot_key(&target);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        let mut state = slot.state.lock().expect("surge logs state poisoned");
        state.buffer.clear();
        state.seen.clear();
    }
}

async fn poll_loop(target: SurgeTarget, key: String, slot: Arc<LogSlot>) {
    let mut backoff = RetryBackoff::new();
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        match poll_once(&target, &slot).await {
            Ok(()) => {
                backoff.reset();
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
            Err(error) => {
                eprintln!("[backend] surge events stream {key}: {error}");
                tokio::time::sleep(backoff.next_delay()).await;
            }
        }
    }
}

async fn poll_once(target: &SurgeTarget, slot: &LogSlot) -> Result<(), MihomoError> {
    let raw = target.client()?.get_json("v1/events").await?;
    let mut entries = parse_events(&raw);
    entries.reverse();
    for entry in entries {
        let key = event_key(&entry);
        {
            let mut state = slot.state.lock().expect("surge logs state poisoned");
            if !state.seen.insert(key.clone()) {
                continue;
            }
            if state.buffer.len() >= LOGS_CAP
                && let Some((old_key, _)) = state.buffer.pop_front()
            {
                state.seen.remove(&old_key);
            }
            state.buffer.push_back((key, entry.clone()));
        }
        let _ = slot.sender.send(entry);
    }
    Ok(())
}

fn parse_events(raw: &Value) -> Vec<LogEntry> {
    raw.get("events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(parse_event)
        .collect()
}

fn parse_event(raw: &Value) -> Option<LogEntry> {
    let message = string_field(raw, "content");
    if message.is_empty() {
        return None;
    }
    let identifier = string_field(raw, "identifier");
    Some(LogEntry {
        time: string_field(raw, "date"),
        level: event_level(raw, &identifier),
        message,
    })
}

fn event_level(raw: &Value, identifier: &str) -> String {
    let marker = identifier.to_ascii_lowercase();
    if marker.contains("fatal") || marker.contains("error") {
        return "error".into();
    }
    if marker.contains("warning") || marker.contains("warn") {
        return "warning".into();
    }
    match raw.get("type").and_then(Value::as_i64).unwrap_or_default() {
        1 => "warning".into(),
        value if value >= 2 => "error".into(),
        _ => "info".into(),
    }
}

pub fn level_allows(filter: &str, level: &str) -> bool {
    match filter.to_ascii_lowercase().as_str() {
        "silent" => false,
        "error" | "fatal" => matches!(level, "error" | "fatal"),
        "warning" | "warn" => matches!(level, "warning" | "warn" | "error" | "fatal"),
        "debug" | "trace" => true,
        _ => true,
    }
}

fn event_key(entry: &LogEntry) -> String {
    format!("{}|{}|{}", entry.time, entry.level, entry.message)
}

fn string_field(raw: &Value, key: &str) -> String {
    raw.get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}
