use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

use serde_json::Value;

use crate::MihomoError;
use crate::clash::api::MihomoTarget;
use crate::clash::client::read_ws_text;

use super::TargetSlot;
use super::parse::parse_connection;
use super::slots;
use super::types::{Connection, ConnectionsFrame, ConnectionsSort, ConnectionsTotals};

const MIN_FRAME_DEADLINE: Duration = Duration::from_secs(5);

pub(super) async fn stream_loop(
    target: MihomoTarget,
    interval_ms: u32,
    key: String,
    slot: Arc<TargetSlot>,
) {
    let mut stream =
        crate::clash::state::stream_manager::TargetStream::new(&target, slot.generation);
    loop {
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
        if let Err(error) = stream_once(interval_ms, &mut stream, &slot).await
            && stream.disconnect()
        {
            eprintln!("[mihomo_backend] connections stream {key}: {error}");
        }
    }
}

async fn stream_once(
    interval_ms: u32,
    stream: &mut crate::clash::state::stream_manager::TargetStream,
    slot: &TargetSlot,
) -> Result<(), MihomoError> {
    let path = format!("connections?interval={interval_ms}");
    let Some(mut ws) = stream.open(&path, &slot.sender).await? else {
        return Ok(());
    };
    let mut first = true;
    let deadline =
        Duration::from_millis((interval_ms as u64).saturating_mul(3)).max(MIN_FRAME_DEADLINE);

    loop {
        // Tear down promptly on either signal: the last subscriber dropping
        // or an explicit Dart stop when a dead upstream cannot emit a frame.
        let text = tokio::select! {
            biased;
            _ = slot.sender.closed() => return Ok(()),
            _ = stream.changed() => return Ok(()),
            read = tokio::time::timeout(deadline, read_ws_text(&mut ws)) => match read {
                Ok(Ok(Some(text))) => text,
                Ok(Ok(None)) => {
                    return Err(MihomoError::Network("connections WebSocket closed".into()));
                }
                Ok(Err(error)) => return Err(error),
                Err(_) => return Err(MihomoError::Network(format!(
                    "connections WebSocket missed its {deadline:?} frame deadline"
                ))),
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
    let mut order_dirty = is_initial || sort_needs_live_resort(state.sort);
    let mut active_set_changed = is_initial;

    if let Some(arr) = raw.get("connections").and_then(|v| v.as_array()) {
        for item in arr {
            let mut conn = parse_connection(item);
            let id = conn.id.clone();
            if let Some(prev) = state.active.get(&id) {
                conn.upload_speed =
                    (((conn.upload.saturating_sub(prev.upload)) as f64) / dt_secs).round() as u64;
                conn.download_speed = (((conn.download.saturating_sub(prev.download)) as f64)
                    / dt_secs)
                    .round() as u64;
                if stable_sort_key_changed(prev, &conn, state.sort) {
                    order_dirty = true;
                }
            } else {
                order_dirty = true;
                active_set_changed = true;
            }
            current_ids.insert(id.clone());
            state.active.insert(id, conn);
        }
    }

    let removed_ids: Vec<String> = state
        .active
        .keys()
        .filter(|id| !current_ids.contains(*id))
        .cloned()
        .collect();
    if !removed_ids.is_empty() {
        order_dirty = true;
        active_set_changed = true;
    }
    for id in removed_ids {
        if let Some(mut row) = state.active.remove(&id) {
            row.is_closed = true;
            row.upload_speed = 0;
            row.download_speed = 0;
            state.push_closed(row);
        }
    }
    if order_dirty {
        state.mark_active_changed(active_set_changed);
    }

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

fn sort_needs_live_resort(sort: ConnectionsSort) -> bool {
    matches!(
        sort,
        ConnectionsSort::Upload
            | ConnectionsSort::Download
            | ConnectionsSort::UploadSpeed
            | ConnectionsSort::DownloadSpeed
    )
}

fn stable_sort_key_changed(prev: &Connection, next: &Connection, sort: ConnectionsSort) -> bool {
    match sort {
        ConnectionsSort::Time => prev.start != next.start,
        ConnectionsSort::Process => prev.process != next.process,
        ConnectionsSort::Upload
        | ConnectionsSort::Download
        | ConnectionsSort::UploadSpeed
        | ConnectionsSort::DownloadSpeed => false,
    }
}
