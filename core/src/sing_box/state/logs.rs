use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{LogEntry, LogWindow, LogsFrame};
use crate::backend::log_store::LogStore;
use crate::backend::retry::RetryBackoff;
use crate::sing_box::client::{SingBoxTarget, target_key};
use crate::sing_box::proto::daemon::{LogLevel, log};

struct LogSlot {
    store: Mutex<LogStore>,
    sender: broadcast::Sender<LogsFrame>,
}

type SlotMap = HashMap<String, Arc<LogSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static SLOTS: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    SLOTS.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

pub async fn subscribe(
    target: SingBoxTarget,
    info_capacity: usize,
) -> Result<(LogsFrame, broadcast::Receiver<LogsFrame>), MihomoError> {
    let key = target_key(&target);
    let mut map = slots().lock().await;
    let slot = if let Some(slot) = map.get(&key) {
        slot.clone()
    } else {
        let (sender, _) = broadcast::channel(64);
        let slot = Arc::new(LogSlot {
            store: Mutex::new(LogStore::new(info_capacity)),
            sender,
        });
        map.insert(key.clone(), slot.clone());
        tokio::spawn(stream_loop(target, key, slot.clone()));
        slot
    };
    drop(map);

    let mut store = slot.store.lock().expect("sing-box logs store poisoned");
    store.set_info_capacity(info_capacity);
    let receiver = slot.sender.subscribe();
    Ok((store.frame(true), receiver))
}

pub async fn fetch_window(
    target: SingBoxTarget,
    level: &str,
    query: &str,
    offset: usize,
    limit: usize,
    from_end: bool,
    anchor_id: u64,
) -> LogWindow {
    let key = target_key(&target);
    let map = slots().lock().await;
    let Some(slot) = map.get(&key) else {
        return LogWindow::default();
    };
    slot.store
        .lock()
        .expect("sing-box logs store poisoned")
        .window(level, query, offset, limit, from_end, anchor_id)
}

pub async fn clear(target: SingBoxTarget) -> Result<(), MihomoError> {
    let key = target_key(&target);
    if let Some(slot) = slots().lock().await.get(&key) {
        let frame = slot
            .store
            .lock()
            .expect("sing-box logs store poisoned")
            .clear();
        let _ = slot.sender.send(frame);
    }
    target.client().await?.clear_logs(()).await?;
    Ok(())
}

async fn stream_loop(target: SingBoxTarget, key: String, slot: Arc<LogSlot>) {
    let mut backoff = RetryBackoff::new();
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        match stream_once(&target, &slot).await {
            Ok(()) => backoff.reset(),
            Err(error) => {
                eprintln!("[backend] sing-box logs stream {key}: {error}");
                tokio::time::sleep(backoff.next_delay()).await;
            }
        }
    }
}

async fn stream_once(target: &SingBoxTarget, slot: &LogSlot) -> Result<(), MihomoError> {
    let mut client = target.client().await?;
    let mut stream = client.subscribe_log(()).await?.into_inner();
    loop {
        let log = tokio::select! {
            _ = slot.sender.closed() => return Ok(()),
            log = stream.message() => log?,
        };
        let Some(log) = log else { return Ok(()) };
        for entry in entries(log.messages) {
            let frame = slot
                .store
                .lock()
                .expect("sing-box logs store poisoned")
                .push(entry);
            let _ = slot.sender.send(frame);
        }
    }
}

pub fn entries(messages: Vec<log::Message>) -> Vec<LogEntry> {
    messages
        .into_iter()
        .map(|message| {
            let (level, message) = clean_entry(message.level, &message.message);
            LogEntry {
                id: 0,
                time: String::new(),
                level: level.to_string(),
                message,
            }
        })
        .collect()
}

fn level_name(level: i32) -> &'static str {
    match LogLevel::try_from(level).unwrap_or(LogLevel::Info) {
        LogLevel::Panic => "panic",
        LogLevel::Fatal => "fatal",
        LogLevel::Error => "error",
        LogLevel::Warn => "warning",
        LogLevel::Info => "info",
        LogLevel::Debug => "debug",
        LogLevel::Trace => "trace",
    }
}

fn clean_entry(level: i32, raw: &str) -> (&'static str, String) {
    let fallback = level_name(level);
    let stripped = strip_ansi(raw);
    let text = stripped.trim_end_matches(['\r', '\n']);
    if let Some((parsed_level, rest)) = take_level_prefix(text) {
        return (parsed_level, rest.trim_start().to_string());
    }
    (fallback, text.to_string())
}

fn take_level_prefix(text: &str) -> Option<(&'static str, &str)> {
    const LEVELS: [(&str, &str); 8] = [
        ("WARNING", "warning"),
        ("PANIC", "panic"),
        ("FATAL", "fatal"),
        ("ERROR", "error"),
        ("TRACE", "trace"),
        ("DEBUG", "debug"),
        ("INFO", "info"),
        ("WARN", "warning"),
    ];
    for (prefix, level) in LEVELS {
        let Some(rest) = text.get(prefix.len()..) else {
            continue;
        };
        if text[..prefix.len()].eq_ignore_ascii_case(prefix)
            && rest
                .as_bytes()
                .first()
                .is_none_or(|b| matches!(b, b'[' | b' ' | b'\t' | b':'))
        {
            return Some((level, rest.strip_prefix(':').unwrap_or(rest)));
        }
    }
    None
}

fn strip_ansi(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == 0x1b {
            i = skip_ansi(bytes, i);
            continue;
        }
        let ch = input[i..].chars().next().expect("valid utf-8 boundary");
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

fn skip_ansi(bytes: &[u8], start: usize) -> usize {
    if start + 1 >= bytes.len() {
        return start + 1;
    }
    match bytes[start + 1] {
        b'[' => {
            let mut i = start + 2;
            while i < bytes.len() {
                let b = bytes[i];
                i += 1;
                if (0x40..=0x7e).contains(&b) {
                    break;
                }
            }
            i
        }
        b']' => {
            let mut i = start + 2;
            while i < bytes.len() {
                if bytes[i] == 0x07 {
                    return i + 1;
                }
                if bytes[i] == 0x1b && i + 1 < bytes.len() && bytes[i + 1] == b'\\' {
                    return i + 2;
                }
                i += 1;
            }
            i
        }
        _ => start + 2,
    }
}
