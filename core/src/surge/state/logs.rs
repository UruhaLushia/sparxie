use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{LogEntry, LogWindow, LogsFrame};
use crate::backend::log_store::LogStore;
use crate::backend::retry::RetryBackoff;
use crate::surge::client::{SurgeTarget, target_key};

struct LogSlot {
    store: Mutex<LogStore>,
    sender: broadcast::Sender<LogsFrame>,
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
) -> Result<(LogsFrame, broadcast::Receiver<LogsFrame>), MihomoError> {
    let key = slot_key(&target);
    let mut map = slots().lock().await;
    let slot = if let Some(slot) = map.get(&key) {
        slot.clone()
    } else {
        let (tx, _) = broadcast::channel::<LogsFrame>(64);
        let slot = Arc::new(LogSlot {
            store: Mutex::new(LogStore::new(info_capacity)),
            sender: tx,
        });
        map.insert(key.clone(), slot.clone());
        tokio::spawn(poll_loop(target, key, slot.clone()));
        slot
    };
    drop(map);

    let mut store = slot.store.lock().expect("surge logs store poisoned");
    store.set_info_capacity(info_capacity);
    let rx = slot.sender.subscribe();
    Ok((store.frame(true), rx))
}

pub async fn fetch_window(
    target: SurgeTarget,
    level: &str,
    query: &str,
    offset: usize,
    limit: usize,
    from_end: bool,
) -> LogWindow {
    let key = slot_key(&target);
    let map = slots().lock().await;
    let Some(slot) = map.get(&key) else {
        return LogWindow::default();
    };
    slot.store
        .lock()
        .expect("surge logs store poisoned")
        .window(level, query, offset, limit, from_end)
}

pub async fn clear(target: SurgeTarget) {
    let key = slot_key(&target);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        let frame = slot
            .store
            .lock()
            .expect("surge logs store poisoned")
            .clear();
        let _ = slot.sender.send(frame);
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
        let frame = slot
            .store
            .lock()
            .expect("surge logs store poisoned")
            .push_unique(key, entry);
        if let Some(frame) = frame {
            let _ = slot.sender.send(frame);
        }
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
        id: 0,
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

fn event_key(entry: &LogEntry) -> String {
    format!("{}|{}|{}", entry.time, entry.level, entry.message)
}

fn string_field(raw: &Value, key: &str) -> String {
    raw.get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}
