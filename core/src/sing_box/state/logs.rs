use crate::MihomoError;
use crate::backend::api::LogEntry;
use crate::sing_box::client::SingBoxTarget;
use crate::sing_box::proto::daemon::{LogLevel, log};

pub async fn subscribe(
    target: SingBoxTarget,
    _level: &str,
) -> Result<tonic::Streaming<crate::sing_box::proto::daemon::Log>, MihomoError> {
    let mut client = target.client().await?;
    Ok(client.subscribe_log(()).await?.into_inner())
}

pub async fn clear(target: SingBoxTarget) -> Result<(), MihomoError> {
    target.client().await?.clear_logs(()).await?;
    Ok(())
}

pub fn entries(messages: Vec<log::Message>, filter: &str) -> Vec<LogEntry> {
    messages
        .into_iter()
        .filter_map(|message| {
            let (level, message) = clean_entry(message.level, &message.message);
            if !level_allows(filter, level) {
                return None;
            }
            Some(LogEntry {
                time: String::new(),
                level: level.to_string(),
                message,
            })
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

fn level_allows(filter: &str, level: &str) -> bool {
    let Some(filter_rank) = level_rank(filter) else {
        return filter.to_ascii_lowercase() != "silent";
    };
    level_rank(level).is_some_and(|rank| rank >= filter_rank)
}

fn level_rank(level: &str) -> Option<u8> {
    match level.to_ascii_lowercase().as_str() {
        "trace" => Some(0),
        "debug" => Some(1),
        "info" => Some(2),
        "warning" | "warn" => Some(3),
        "error" => Some(4),
        "fatal" => Some(5),
        "panic" => Some(6),
        "silent" => None,
        _ => Some(2),
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
