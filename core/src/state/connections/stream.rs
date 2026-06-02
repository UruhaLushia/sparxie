use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

use serde_json::Value;

use crate::MihomoError;
use crate::api::MihomoTarget;
use crate::client::{MihomoClient, read_ws_text};

use super::TargetSlot;
use super::parse::parse_connection;
use super::slots;
use super::types::{CLOSED_CAP, ConnectionsFrame, ConnectionsTotals};

pub(super) async fn stream_loop(
    target: MihomoTarget,
    interval_ms: u32,
    key: String,
    slot: Arc<TargetSlot>,
) {
    // Capture the target's stop generation; bail if Dart stops it (a dead
    // upstream produces no frames, so the sink-failure path never fires).
    let base = crate::state::stop::base_key(&target);
    let start_gen = crate::state::stop::generation(&base);
    loop {
        {
            let mut map = slots().lock().await;
            if slot.sender.receiver_count() == 0
                || crate::state::stop::generation(&base) != start_gen
            {
                map.remove(&key);
                return;
            }
        }
        if let Err(error) = stream_once(&target, interval_ms, &base, start_gen, &slot).await {
            eprintln!("[mihomo_backend] connections stream {key}: {error}");
            let mut ticks = crate::state::stop::ticks();
            let _ = tokio::time::timeout(Duration::from_secs(2), ticks.changed()).await;
        }
    }
}

async fn stream_once(
    target: &MihomoTarget,
    interval_ms: u32,
    base: &str,
    start_gen: u64,
    slot: &TargetSlot,
) -> Result<(), MihomoError> {
    let client = MihomoClient::new(
        &target.base_url,
        target.secret.clone(),
        target.allow_insecure,
    )?;
    let path = format!("connections?interval={interval_ms}");
    let mut ws = client.open_ws(&path).await?;
    let mut first = true;
    let mut ticks = crate::state::stop::ticks();

    loop {
        // Tear down promptly on either signal: the last subscriber dropping
        // or an explicit Dart stop when a dead upstream cannot emit a frame.
        let text = tokio::select! {
            biased;
            _ = slot.sender.closed() => return Ok(()),
            _ = ticks.changed() => {
                if crate::state::stop::generation(base) != start_gen {
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
        let parsed: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let frame = apply_snapshot(slot, parsed, first, interval_ms);
        first = false;
        let _ = slot.sender.send(frame);
    }
}

fn apply_snapshot(
    slot: &TargetSlot,
    raw: Value,
    is_initial: bool,
    interval_ms: u32,
) -> ConnectionsFrame {
    let upload_total = raw.get("uploadTotal").and_then(|v| v.as_u64()).unwrap_or(0);
    let download_total = raw
        .get("downloadTotal")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let memory = raw.get("memory").and_then(|v| v.as_u64()).unwrap_or(0);

    let dt_secs = (interval_ms as f64 / 1000.0).max(0.05);
    let mut state = slot.state.lock().expect("connections state poisoned");
    let mut current_ids = HashSet::with_capacity(state.active.len());

    if let Some(arr) = raw.get("connections").and_then(|v| v.as_array()) {
        for item in arr {
            let mut conn = parse_connection(item);
            if let Some(prev) = state.active.get(&conn.id) {
                conn.upload_speed =
                    (((conn.upload.saturating_sub(prev.upload)) as f64) / dt_secs).round() as u64;
                conn.download_speed = (((conn.download.saturating_sub(prev.download)) as f64)
                    / dt_secs)
                    .round() as u64;
            }
            current_ids.insert(conn.id.clone());
            state.active.insert(conn.id.clone(), conn);
        }
    }

    let removed_ids: Vec<String> = state
        .active
        .keys()
        .filter(|id| !current_ids.contains(*id))
        .cloned()
        .collect();
    for id in removed_ids {
        if let Some(mut row) = state.active.remove(&id) {
            row.is_closed = true;
            row.upload_speed = 0;
            row.download_speed = 0;
            if state.closed.len() >= CLOSED_CAP {
                state.closed.pop_front();
            }
            state.closed.push_back(row);
        }
    }
    state.active_version = state.active_version.wrapping_add(1);

    ConnectionsFrame {
        active_count: state.active.len() as u32,
        closed_count: state.closed.len() as u32,
        totals: ConnectionsTotals {
            upload: upload_total,
            download: download_total,
            memory,
        },
        is_initial,
    }
}
