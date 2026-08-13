use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{LogEntry, LogWindow, LogsFrame};
use crate::backend::log_store::LogStore;
use crate::backend::retry::RetryBackoff;
use crate::surge_controller::client::SurgeControllerTarget;

use super::target::Target;

struct LogSlot {
    store: Mutex<LogStore>,
    sender: broadcast::Sender<LogsFrame>,
}

type SlotMap = HashMap<String, Arc<LogSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

pub async fn subscribe(
    target: impl Into<Target>,
    info_capacity: usize,
) -> Result<(LogsFrame, broadcast::Receiver<LogsFrame>), MihomoError> {
    let target = target.into();
    let key = target.key();
    let mut map = slots().lock().await;
    let (slot, rx) = if let Some(slot) = map.get(&key) {
        let slot = slot.clone();
        let rx = slot.sender.subscribe();
        (slot, rx)
    } else {
        let (tx, _) = broadcast::channel::<LogsFrame>(64);
        let slot = Arc::new(LogSlot {
            store: Mutex::new(LogStore::new(info_capacity)),
            sender: tx,
        });
        let rx = slot.sender.subscribe();
        map.insert(key.clone(), slot.clone());
        tokio::spawn(poll_loop(target, key, slot.clone()));
        (slot, rx)
    };
    drop(map);

    let mut store = slot.store.lock().expect("surge logs store poisoned");
    store.set_info_capacity(info_capacity);
    Ok((store.frame(true), rx))
}

pub async fn fetch_window(
    target: impl Into<Target>,
    level: &str,
    query: &str,
    offset: usize,
    limit: usize,
    from_end: bool,
    anchor_id: u64,
) -> LogWindow {
    let target = target.into();
    let key = target.key();
    let map = slots().lock().await;
    let Some(slot) = map.get(&key) else {
        return LogWindow::default();
    };
    slot.store
        .lock()
        .expect("surge logs store poisoned")
        .window(level, query, offset, limit, from_end, anchor_id)
}

pub async fn clear(target: impl Into<Target>) {
    let target = target.into();
    let key = target.key();
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

async fn poll_loop(target: Target, key: String, slot: Arc<LogSlot>) {
    let mut backoff = RetryBackoff::new();
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        let result = match &target {
            Target::Http(_) => poll_once(&target, &slot).await,
            Target::Controller(target) => watch_once(target, &slot).await,
        };
        match result {
            Ok(()) => {
                backoff.reset();
                if target.is_http() {
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
            Err(error) => {
                eprintln!("[backend] surge events stream: {error}");
                tokio::time::sleep(backoff.next_delay()).await;
            }
        }
    }
}

async fn poll_once(target: &Target, slot: &LogSlot) -> Result<(), MihomoError> {
    let Target::Http(target) = target else {
        return Err(MihomoError::Other("无效的 Surge HTTP 日志目标".into()));
    };
    let raw = target.client()?.get_json("v1/events").await?;
    push_raw(slot, &raw);
    Ok(())
}

async fn watch_once(target: &SurgeControllerTarget, slot: &LogSlot) -> Result<(), MihomoError> {
    let mut connection = target.connect().await?;
    let initial = connection.request(["log"]).await?;
    push_raw(slot, &initial);
    connection.send(["log", "watch"]).await?;
    loop {
        if slot.sender.receiver_count() == 0 {
            return Ok(());
        }
        match tokio::time::timeout(Duration::from_secs(1), connection.next_stream_value()).await {
            Ok(raw) => push_raw(slot, &raw?),
            Err(_) => continue,
        }
    }
}

fn push_raw(slot: &LogSlot, raw: &Value) {
    let mut entries = parse_events(raw);
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
}

fn parse_events(raw: &Value) -> Vec<LogEntry> {
    let payload = raw.get("data").unwrap_or(raw);
    if let Some(log) = payload.get("log").and_then(Value::as_str) {
        let fallback_level = string_field(payload, "level");
        // `log` snapshots are oldest-first while event lists are newest-first.
        // Return newest-first here so `push_raw` can normalize both sources.
        let mut entries = log
            .lines()
            .filter_map(|line| parse_log_line(line, &fallback_level))
            .collect::<Vec<_>>();
        entries.reverse();
        return entries;
    }
    if let Some(entries) = ["events", "logs", "entries"]
        .iter()
        .find_map(|key| payload.get(*key).and_then(Value::as_array))
        .or_else(|| payload.as_array())
    {
        return entries.iter().filter_map(parse_event).collect();
    }
    parse_event(payload).into_iter().collect()
}

fn parse_log_line(line: &str, fallback_level: &str) -> Option<LogEntry> {
    let line = line.trim();
    if line.is_empty() {
        return None;
    }
    let Some(marker_start) = line.find(" <") else {
        return Some(LogEntry {
            level: normalize_log_level(fallback_level),
            message: line.to_string(),
            ..Default::default()
        });
    };
    let level_start = marker_start + 2;
    let Some(level_end) = line[level_start..].find('>') else {
        return Some(LogEntry {
            level: normalize_log_level(fallback_level),
            message: line.to_string(),
            ..Default::default()
        });
    };
    let level_end = level_start + level_end;
    let time = line[..marker_start].trim().to_string();
    let message = line[level_end + 1..].trim().to_string();
    if message.is_empty() {
        return None;
    }
    Some(LogEntry {
        id: 0,
        time,
        level: normalize_log_level(&line[level_start..level_end]),
        message,
    })
}

fn normalize_log_level(level: &str) -> String {
    match level.trim().to_ascii_lowercase().as_str() {
        "trace" => "trace",
        "verbose" | "debug" => "debug",
        "warning" | "warn" => "warning",
        "error" => "error",
        "fatal" => "fatal",
        _ => "info",
    }
    .to_string()
}

fn parse_event(raw: &Value) -> Option<LogEntry> {
    if let Some(message) = raw.as_str().filter(|message| !message.is_empty()) {
        return Some(LogEntry {
            level: "info".into(),
            message: message.into(),
            ..Default::default()
        });
    }
    let message = ["content", "message", "text", "output"]
        .iter()
        .map(|key| string_field(raw, key))
        .find(|value| !value.is_empty())?;
    if message.is_empty() {
        return None;
    }
    let identifier = string_field(raw, "identifier");
    Some(LogEntry {
        id: 0,
        time: ["date", "time", "timestamp"]
            .iter()
            .map(|key| string_field(raw, key))
            .find(|value| !value.is_empty())
            .unwrap_or_default(),
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
