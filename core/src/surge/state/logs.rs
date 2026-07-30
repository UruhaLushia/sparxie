use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::LogEntry;
use crate::backend::retry::RetryBackoff;
use crate::surge::client::{SurgeTarget, target_key};

struct LogSlot {
    state: Mutex<LogState>,
    sender: broadcast::Sender<LogEntry>,
}

struct LogState {
    buffer: VecDeque<(String, LogEntry)>,
    seen: HashSet<String>,
    info_entries: usize,
    info_capacity: usize,
}

impl LogState {
    fn new(info_capacity: usize) -> Self {
        Self {
            buffer: VecDeque::new(),
            seen: HashSet::new(),
            info_entries: 0,
            info_capacity: info_capacity.max(1),
        }
    }

    fn set_info_capacity(&mut self, info_capacity: usize) {
        self.info_capacity = info_capacity.max(1);
        self.trim();
    }

    fn push(&mut self, key: String, entry: LogEntry) -> bool {
        if !self.seen.insert(key.clone()) {
            return false;
        }
        if level_allows("info", &entry.level) {
            self.info_entries += 1;
        }
        self.buffer.push_back((key, entry));
        self.trim();
        true
    }

    fn clear(&mut self) {
        self.buffer.clear();
        self.seen.clear();
        self.info_entries = 0;
    }

    fn trim(&mut self) {
        while self.info_entries > self.info_capacity {
            let Some((key, entry)) = self.buffer.pop_front() else {
                self.info_entries = 0;
                break;
            };
            self.seen.remove(&key);
            if level_allows("info", &entry.level) {
                self.info_entries -= 1;
            }
        }
    }
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
    info_capacity: usize,
) -> Result<(Vec<LogEntry>, broadcast::Receiver<LogEntry>), MihomoError> {
    let key = slot_key(&target);
    let mut map = slots().lock().await;
    let slot = if let Some(slot) = map.get(&key) {
        slot.clone()
    } else {
        let (tx, _) = broadcast::channel::<LogEntry>(64);
        let slot = Arc::new(LogSlot {
            state: Mutex::new(LogState::new(info_capacity)),
            sender: tx,
        });
        map.insert(key.clone(), slot.clone());
        tokio::spawn(poll_loop(target, key, slot.clone()));
        slot
    };
    drop(map);

    let mut state = slot.state.lock().expect("surge logs state poisoned");
    state.set_info_capacity(info_capacity);
    let rx = slot.sender.subscribe();
    Ok((
        state
            .buffer
            .iter()
            .map(|(_, entry)| entry.clone())
            .collect(),
        rx,
    ))
}

pub async fn clear(target: SurgeTarget) {
    let key = slot_key(&target);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        let mut state = slot.state.lock().expect("surge logs state poisoned");
        state.clear();
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
        let inserted = {
            let mut state = slot.state.lock().expect("surge logs state poisoned");
            state.push(key, entry.clone())
        };
        if !inserted {
            continue;
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
