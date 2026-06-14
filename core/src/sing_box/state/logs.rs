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
            let level = level_name(message.level);
            if !level_allows(filter, level) {
                return None;
            }
            Some(LogEntry {
                time: String::new(),
                level: level.to_string(),
                message: message.message,
            })
        })
        .collect()
}

fn level_name(level: i32) -> &'static str {
    match LogLevel::try_from(level).unwrap_or(LogLevel::Info) {
        LogLevel::Panic | LogLevel::Fatal | LogLevel::Error => "error",
        LogLevel::Warn => "warning",
        LogLevel::Info => "info",
        LogLevel::Debug | LogLevel::Trace => "debug",
    }
}

fn level_allows(filter: &str, level: &str) -> bool {
    match filter.to_ascii_lowercase().as_str() {
        "silent" => false,
        "error" | "fatal" => matches!(level, "error" | "fatal"),
        "warning" | "warn" => matches!(level, "warning" | "warn" | "error" | "fatal"),
        "debug" | "trace" => true,
        _ => true,
    }
}
