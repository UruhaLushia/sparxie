use std::collections::HashSet;
use std::sync::Arc;

use serde_json::Value;

use crate::MihomoError;
use crate::backend::retry::RetryBackoff;
use crate::clash::api::MihomoTarget;
use crate::clash::client::{MihomoClient, read_ws_text};

use super::TargetSlot;
use super::parse::parse_connection;
use super::slots;
use super::types::{Connection, ConnectionsFrame, ConnectionsSort, ConnectionsTotals};

pub(super) async fn stream_loop(
    target: MihomoTarget,
    interval_ms: u32,
    key: String,
    slot: Arc<TargetSlot>,
) {
    // Capture the target's stop generation; bail if Dart stops it (a dead
    // upstream produces no frames, so the sink-failure path never fires).
    let base = crate::clash::state::stop::base_key(&target);
    let start_gen = crate::clash::state::stop::generation(&base);
    let mut backoff = RetryBackoff::new();
    loop {
        {
            let mut map = slots().lock().await;
            if slot.sender.receiver_count() == 0
                || crate::clash::state::stop::generation(&base) != start_gen
            {
                map.remove(&key);
                return;
            }
        }
        match stream_once(&target, interval_ms, &base, start_gen, &slot).await {
            Ok(()) => backoff.reset(),
            Err(error) => {
                eprintln!("[mihomo_backend] connections stream {key}: {error}");
                let mut ticks = crate::clash::state::stop::ticks();
                let _ = tokio::time::timeout(backoff.next_delay(), ticks.changed()).await;
            }
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
    let mut ticks = crate::clash::state::stop::ticks();

    loop {
        // Tear down promptly on either signal: the last subscriber dropping
        // or an explicit Dart stop when a dead upstream cannot emit a frame.
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
