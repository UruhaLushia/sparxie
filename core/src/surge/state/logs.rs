use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{LogEntry, LogWindow, LogsFrame};
use crate::backend::log_store::LogStore;
use crate::backend::retry::{RetryBackoff, RetryErrorLog};
use crate::surge_controller::client::{SurgeControllerConnection, SurgeControllerTarget};

use super::target::Target;
use super::time::unix_seconds_to_iso;

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
    let mut error_log = RetryErrorLog::new("surge events stream");
    let mut controller_connection = None;
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        let result = match &target {
            Target::Http(_) => poll_once(&target, &slot).await,
            Target::Controller(target) => {
                poll_controller_once(target, &mut controller_connection, &slot).await
            }
        };
        match result {
            Ok(()) => {
                backoff.reset();
                error_log.recovered();
                let interval = match &target {
                    Target::Http(_) => Duration::from_secs(5),
                    Target::Controller(_) => Duration::from_secs(15),
                };
                tokio::time::sleep(interval).await;
            }
            Err(error) => {
                controller_connection = None;
                error_log.record(&error);
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

async fn poll_controller_once(
    target: &SurgeControllerTarget,
    connection: &mut Option<SurgeControllerConnection>,
    slot: &LogSlot,
) -> Result<(), MihomoError> {
    if connection.is_none() {
        *connection = Some(target.connect().await?);
    }
    let connection = connection
        .as_mut()
        .expect("surge controller event connection initialized");
    let events = connection.request(["dump", "event"]).await?;
    push_raw(slot, &events);
    let logbook = connection.request(["logbook", "100"]).await?;
    push_entries(slot, parse_script_records(&logbook));
    Ok(())
}

fn push_raw(slot: &LogSlot, raw: &Value) {
    push_entries(slot, parse_events(raw));
}

fn push_entries(slot: &LogSlot, mut entries: Vec<LogEntry>) {
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
    if let Some(entries) = ["events", "logs", "entries"]
        .iter()
        .find_map(|key| payload.get(*key).and_then(Value::as_array))
        .or_else(|| payload.as_array())
    {
        return entries.iter().filter_map(parse_event).collect();
    }
    parse_event(payload).into_iter().collect()
}

fn parse_script_records(raw: &Value) -> Vec<LogEntry> {
    raw.get("data")
        .unwrap_or(raw)
        .get("records")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|record| string_field(record, "type").eq_ignore_ascii_case("script"))
        .filter_map(parse_script_record)
        .collect()
}

fn parse_script_record(raw: &Value) -> Option<LogEntry> {
    let content = string_field(raw, "content");
    let script = string_field(raw, "subtitle");
    let message = match (script.is_empty(), content.is_empty()) {
        (true, true) => return None,
        (true, false) => content,
        (false, true) => script,
        (false, false) => format!("[{script}] {content}"),
    };
    Some(LogEntry {
        id: 0,
        time: value_field(raw, "timestamp"),
        level: event_level(raw, &string_field(raw, "subsystem")),
        message,
    })
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
            .map(|key| value_field(raw, key))
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

fn value_field(raw: &Value, key: &str) -> String {
    match raw.get(key) {
        Some(Value::String(value)) => value.clone(),
        Some(value @ Value::Number(_)) => {
            unix_seconds_to_iso(value).unwrap_or_else(|| value.to_string())
        }
        _ => String::new(),
    }
}
