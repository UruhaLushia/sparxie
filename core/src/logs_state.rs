//! Per-target rolling log buffer with replay-on-subscribe.
//!
//! Logs need to keep accumulating while the user is on a different tab —
//! the WebSocket should not disconnect just because the screen unmounted.
//! Rust owns the authoritative ring buffer; Dart subscribers get a one-shot
//! snapshot followed by live deltas, so a freshly-mounted screen sees the
//! last `LOGS_CAP` lines instantly rather than waiting for upstream traffic.
//!
//! Slots are keyed by `(target, level)` and never auto-prune — at full
//! capacity each slot holds at most a few hundred KB of strings plus one
//! idle WebSocket, which is well within phone budgets. Use [`clear`] to
//! drop a slot's buffer; the upstream loop keeps running so the next event
//! still flows.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::api::MihomoTarget;
use crate::client::{MihomoClient, read_ws_text};
use crate::error::MihomoError;

pub const LOGS_CAP: usize = 500;

/// One log line. Mirrors mihomo's `format=structured` output.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LogEntry {
    #[serde(default)]
    pub time: String,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub message: String,
}

struct LogSlot {
    buffer: Mutex<VecDeque<LogEntry>>,
    sender: broadcast::Sender<LogEntry>,
}

type SlotMap = HashMap<String, Arc<LogSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

fn normalize_level(level: &str) -> &str {
    if level.is_empty() { "info" } else { level }
}

fn slot_key(target: &MihomoTarget, level: &str) -> String {
    format!(
        "{}|{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or(""),
        level,
    )
}

/// Atomically grab the cached snapshot plus a fresh broadcast receiver.
///
/// Holding the buffer mutex across `subscribe()` and `iter().cloned()`
/// guarantees the ingest task can't insert between snapshot and delta
/// stream — no dropped or duplicated entries.
pub async fn subscribe(
    target: MihomoTarget,
    level: &str,
) -> Result<(Vec<LogEntry>, broadcast::Receiver<LogEntry>), MihomoError> {
    let level = normalize_level(level).to_string();
    let key = slot_key(&target, &level);
    let mut map = slots().lock().await;
    let slot = if let Some(s) = map.get(&key) {
        s.clone()
    } else {
        let (tx, _) = broadcast::channel::<LogEntry>(64);
        let slot = Arc::new(LogSlot {
            buffer: Mutex::new(VecDeque::new()),
            sender: tx,
        });
        map.insert(key.clone(), slot.clone());
        tokio::spawn(stream_loop(target, level, key, slot.clone()));
        slot
    };
    drop(map);

    let buf = slot.buffer.lock().expect("logs buffer poisoned");
    let rx = slot.sender.subscribe();
    let snapshot: Vec<LogEntry> = buf.iter().cloned().collect();
    Ok((snapshot, rx))
}

/// Drop the cached buffer. The upstream stream keeps running, so new
/// entries continue to land normally.
pub async fn clear(target: MihomoTarget, level: &str) {
    let level = normalize_level(level);
    let key = slot_key(&target, level);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        let mut buf = slot.buffer.lock().expect("logs buffer poisoned");
        buf.clear();
    }
}

async fn stream_loop(
    target: MihomoTarget,
    level: String,
    key: String,
    slot: Arc<LogSlot>,
) {
    loop {
        if let Err(error) = stream_once(&target, &level, &slot).await {
            eprintln!("[mihomo_backend] logs stream {key}: {error}");
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    }
}

async fn stream_once(
    target: &MihomoTarget,
    level: &str,
    slot: &LogSlot,
) -> Result<(), MihomoError> {
    let client = MihomoClient::new(&target.base_url, target.secret.clone())?;
    let path = format!("logs?level={level}&format=structured");
    let mut ws = client.open_ws(&path).await?;
    while let Some(text) = read_ws_text(&mut ws).await? {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Ok(entry): Result<LogEntry, _> = serde_json::from_str(trimmed) else {
            continue;
        };
        // Append + broadcast under the same mutex so concurrent `subscribe`
        // calls see a consistent (snapshot, delta-stream) pair.
        let mut buf = slot.buffer.lock().expect("logs buffer poisoned");
        if buf.len() >= LOGS_CAP {
            buf.pop_front();
        }
        buf.push_back(entry.clone());
        let _ = slot.sender.send(entry);
    }
    Ok(())
}
