//! Per-target rolling log buffer. Rust owns the entries; Dart receives only
//! cache metadata and fetches the window it is rendering.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{LogEntry, LogWindow, LogsFrame};
use crate::backend::log_store::LogStore;
use crate::clash::api::MihomoTarget;
use crate::clash::client::read_ws_text;

struct LogSlot {
    store: Arc<Mutex<LogStore>>,
    sender: broadcast::Sender<LogsFrame>,
    generation: u64,
}

type SlotMap = HashMap<String, Arc<LogSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

fn slot_key(target: &MihomoTarget) -> String {
    target.identity_key()
}

/// Snapshot + receiver are taken under one lock so the ingest task can't
/// slip an entry between them — no dropped or duplicated lines.
pub async fn subscribe(
    target: MihomoTarget,
    info_capacity: usize,
) -> Result<(LogsFrame, broadcast::Receiver<LogsFrame>), MihomoError> {
    let key = slot_key(&target);
    let generation = crate::clash::state::stream_manager::generation(&target);
    let mut map = slots().lock().await;
    let slot = if let Some(slot) = map.get(&key).filter(|slot| slot.generation == generation) {
        slot.clone()
    } else {
        // Rotate the producer after a hard target restart, but retain the log
        // store so existing rows do not disappear while the new WS connects.
        let store = map
            .get(&key)
            .map(|slot| slot.store.clone())
            .unwrap_or_else(|| Arc::new(Mutex::new(LogStore::new(info_capacity))));
        let (tx, _) = broadcast::channel::<LogsFrame>(64);
        let slot = Arc::new(LogSlot {
            store,
            sender: tx,
            generation,
        });
        map.insert(key.clone(), slot.clone());
        tokio::spawn(stream_loop(target, key, slot.clone()));
        slot
    };
    drop(map);

    let mut store = slot.store.lock().expect("logs store poisoned");
    store.set_info_capacity(info_capacity);
    let rx = slot.sender.subscribe();
    Ok((store.frame(true), rx))
}

pub async fn fetch_window(
    target: MihomoTarget,
    level: &str,
    query: &str,
    offset: usize,
    limit: usize,
    from_end: bool,
    anchor_id: u64,
) -> LogWindow {
    let key = slot_key(&target);
    let map = slots().lock().await;
    let Some(slot) = map.get(&key) else {
        return LogWindow::default();
    };
    slot.store
        .lock()
        .expect("logs store poisoned")
        .window(level, query, offset, limit, from_end, anchor_id)
}

pub async fn clear(target: MihomoTarget) {
    let key = slot_key(&target);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        let frame = slot.store.lock().expect("logs store poisoned").clear();
        let _ = slot.sender.send(frame);
    }
}

async fn stream_loop(target: MihomoTarget, key: String, slot: Arc<LogSlot>) {
    let mut stream =
        crate::clash::state::stream_manager::TargetStream::new(&target, slot.generation);
    loop {
        // Re-check under the slots lock before removing, so a subscriber that
        // attaches just as the stream ends isn't orphaned.
        {
            let mut map = slots().lock().await;
            let is_current = map
                .get(&key)
                .is_some_and(|current| Arc::ptr_eq(current, &slot));
            if !is_current {
                return;
            }
            if slot.sender.receiver_count() == 0 || stream.stopped() {
                map.remove(&key);
                return;
            }
        }
        if !stream.wait_ready(&slot.sender).await {
            continue;
        }
        if let Err(error) = stream_once(&mut stream, &slot).await
            && stream.disconnect()
        {
            eprintln!("[mihomo_backend] logs stream {key}: {error}");
        }
    }
}

async fn stream_once(
    stream: &mut crate::clash::state::stream_manager::TargetStream,
    slot: &LogSlot,
) -> Result<(), MihomoError> {
    let Some(mut ws) = stream
        .open("logs?level=debug&format=structured", &slot.sender)
        .await?
    else {
        return Ok(());
    };
    loop {
        // Tear down promptly on either signal: the last subscriber dropping
        // (live switch — `closed()`) or an explicit Dart stop (dead upstream —
        // the stop tick). Logs can stay silent for minutes, so neither a
        // read-driven nor frame-driven check would fire on its own here.
        let text = tokio::select! {
            biased;
            _ = slot.sender.closed() => return Ok(()),
            _ = stream.changed() => return Ok(()),
            read = read_ws_text(&mut ws) => match read? {
                Some(t) => t,
                None => return Err(MihomoError::Network("logs WebSocket closed".into())),
            },
        };
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Some(entry) = parse_log_entry(trimmed) else {
            continue;
        };
        let frame = slot.store.lock().expect("logs store poisoned").push(entry);
        let _ = slot.sender.send(frame);
    }
}

fn parse_log_entry(line: &str) -> Option<LogEntry> {
    let raw: Value = serde_json::from_str(line).ok()?;
    let level = first_string(&raw, &["level", "type"]);
    let message = first_string(&raw, &["message", "payload"]);
    if level.is_empty() && message.is_empty() {
        return None;
    }
    Some(LogEntry {
        id: 0,
        time: first_string(&raw, &["time"]),
        level,
        message,
    })
}

fn first_string(raw: &Value, keys: &[&str]) -> String {
    keys.iter()
        .find_map(|key| raw.get(key).and_then(Value::as_str))
        .unwrap_or_default()
        .to_string()
}
