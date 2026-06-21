//! Per-target rolling log buffer with replay-on-subscribe. Rust owns the
//! ring; Dart subscribes for an atomic snapshot + delta stream so a fresh
//! screen sees the last `LOGS_CAP` lines instantly.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::retry::RetryBackoff;
use crate::clash::api::MihomoTarget;
use crate::clash::client::{MihomoClient, read_ws_text};

pub const LOGS_CAP: usize = 500;

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

/// Snapshot + receiver are taken under one lock so the ingest task can't
/// slip an entry between them — no dropped or duplicated lines.
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

pub async fn clear(target: MihomoTarget, level: &str) {
    let level = normalize_level(level);
    let key = slot_key(&target, level);
    let map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        slot.buffer.lock().expect("logs buffer poisoned").clear();
    }
}

async fn stream_loop(target: MihomoTarget, level: String, key: String, slot: Arc<LogSlot>) {
    // Capture the target's stop generation; bail if Dart stops it (a dead
    // upstream produces no frames, so the sink-failure path never fires).
    let base = crate::clash::state::stop::base_key(&target);
    let start_gen = crate::clash::state::stop::generation(&base);
    let mut backoff = RetryBackoff::new();
    loop {
        // Re-check under the slots lock before removing, so a subscriber that
        // attaches just as the stream ends isn't orphaned.
        {
            let mut map = slots().lock().await;
            if slot.sender.receiver_count() == 0
                || crate::clash::state::stop::generation(&base) != start_gen
            {
                map.remove(&key);
                return;
            }
        }
        match stream_once(&target, &level, &base, start_gen, &slot).await {
            Ok(()) => backoff.reset(),
            Err(error) => {
                eprintln!("[mihomo_backend] logs stream {key}: {error}");
                // Wake early if a stop arrives during the retry backoff.
                let mut ticks = crate::clash::state::stop::ticks();
                let _ = tokio::time::timeout(backoff.next_delay(), ticks.changed()).await;
            }
        }
    }
}

async fn stream_once(
    target: &MihomoTarget,
    level: &str,
    base: &str,
    start_gen: u64,
    slot: &LogSlot,
) -> Result<(), MihomoError> {
    let client = MihomoClient::new(
        &target.base_url,
        target.secret.clone(),
        target.allow_insecure,
    )?;
    let path = format!("logs?level={level}&format=structured");
    let mut ws = client.open_ws(&path).await?;
    let mut ticks = crate::clash::state::stop::ticks();
    loop {
        // Tear down promptly on either signal: the last subscriber dropping
        // (live switch — `closed()`) or an explicit Dart stop (dead upstream —
        // the stop tick). Logs can stay silent for minutes, so neither a
        // read-driven nor frame-driven check would fire on its own here.
        let text = tokio::select! {
            biased;
            _ = slot.sender.closed() => return Ok(()),
            _ = ticks.changed() => {
                if crate::clash::state::stop::generation(base) != start_gen {
                    return Ok(());
                }
                continue;
            }
            read = read_ws_text(&mut ws) => match read? {
                Some(t) => t,
                None => return Ok(()),
            },
        };
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Some(entry) = parse_log_entry(trimmed) else {
            continue;
        };
        {
            let mut buf = slot.buffer.lock().expect("logs buffer poisoned");
            if buf.len() >= LOGS_CAP {
                buf.pop_front();
            }
            buf.push_back(entry.clone());
        }
        let _ = slot.sender.send(entry);
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
