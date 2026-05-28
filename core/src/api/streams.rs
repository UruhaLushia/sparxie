use futures_util::StreamExt;
use tokio_stream::wrappers::BroadcastStream;

use crate::connections_state::{clear_closed, fetch_window, set_sort, subscribe};
// Re-export the wire types so frb scanning `crate::api::*` discovers them
// alongside the functions that use them (otherwise they'd be treated as
// opaque). They live in `connections_state` for organizational reasons but
// the Dart-facing surface is here.
pub use crate::connections_state::{
    Connection, ConnectionsFrame, ConnectionsListKind, ConnectionsSort, ConnectionsTotals,
};
use crate::error::MihomoError;
// `StreamSink<T>` is emitted into `frb_generated.rs` by the
// `frb_generated_boilerplate_io!()` / `_web!()` macros — that variant exposes
// the `add(value: T)` method we need here. A generic helper that takes
// `StreamSink<T>` would fail to resolve `add()` because frb's `Drop` impl is
// `T: 'static` but the inherent method only exists on the generated alias for
// concrete `T`s, so each call site below inlines its own loop.
use crate::frb_generated::StreamSink;
pub use crate::logs_state::LogEntry;
use crate::logs_state::{clear as logs_clear, subscribe as logs_subscribe};
use crate::traffic::{MemorySample, TrafficSample, memory_subscribe, traffic_subscribe};

use super::MihomoTarget;

/// Subscribe to mihomo's `/traffic` WebSocket feed (1Hz).
pub async fn traffic_stream(
    target: MihomoTarget,
    sink: StreamSink<TrafficSample>,
) -> Result<(), MihomoError> {
    let rx = traffic_subscribe(target).await?;
    let mut stream = BroadcastStream::new(rx);
    while let Some(item) = stream.next().await {
        let Ok(sample) = item else { continue };
        if sink.add(sample).is_err() {
            break;
        }
    }
    Ok(())
}

/// Subscribe to mihomo's `/memory` WebSocket feed (1Hz).
pub async fn memory_stream(
    target: MihomoTarget,
    sink: StreamSink<MemorySample>,
) -> Result<(), MihomoError> {
    let rx = memory_subscribe(target).await?;
    let mut stream = BroadcastStream::new(rx);
    while let Some(item) = stream.next().await {
        let Ok(sample) = item else { continue };
        if sink.add(sample).is_err() {
            break;
        }
    }
    Ok(())
}

/// Subscribe to mihomo's `/logs?level=&format=structured` feed.
///
/// The stream first replays up to `LOGS_CAP` cached entries (so the UI
/// shows context immediately on (re)subscribe), then continues with live
/// deltas. Snapshot + stream are taken under the same lock, so no entries
/// are dropped or duplicated across the boundary.
pub async fn logs_stream(
    target: MihomoTarget,
    level: String,
    sink: StreamSink<LogEntry>,
) -> Result<(), MihomoError> {
    let (snapshot, rx) = logs_subscribe(target, &level).await?;
    for entry in snapshot {
        if sink.add(entry).is_err() {
            return Ok(());
        }
    }
    let mut stream = BroadcastStream::new(rx);
    while let Some(item) = stream.next().await {
        let Ok(sample) = item else { continue };
        if sink.add(sample).is_err() {
            break;
        }
    }
    Ok(())
}

/// Drop the cached log buffer for `(target, level)`. The upstream stream
/// keeps running so new lines flow normally.
pub async fn clear_logs(target: MihomoTarget, level: String) {
    logs_clear(target, &level).await
}

/// Subscribe to mihomo's `/connections?interval=<ms>` WebSocket feed.
///
/// Each frame carries totals and the active/closed counts. Dart pages
/// the row payloads it actually needs via [`fetch_connection_window`].
pub async fn connections_stream(
    target: MihomoTarget,
    interval_ms: u32,
    sink: StreamSink<ConnectionsFrame>,
) -> Result<(), MihomoError> {
    let rx = subscribe(target, interval_ms).await?;
    let mut stream = BroadcastStream::new(rx);
    while let Some(item) = stream.next().await {
        let Ok(frame) = item else { continue };
        if sink.add(frame).is_err() {
            break;
        }
    }
    Ok(())
}

/// Page a slice of the sorted connections list. `kind` picks active vs
/// closed; `offset`/`limit` are bounds-checked.
pub async fn fetch_connection_window(
    target: MihomoTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    offset: u32,
    limit: u32,
) -> Vec<Connection> {
    fetch_window(target, interval_ms, kind, offset, limit).await
}

/// Update the per-target sort key. Effective from the next emitted frame.
pub async fn set_connections_sort(
    target: MihomoTarget,
    interval_ms: u32,
    sort: ConnectionsSort,
    asc: bool,
) {
    set_sort(target, interval_ms, sort, asc).await
}

/// Drop the closed-connections FIFO buffer for the given target/interval.
/// The next emitted frame will report `closed_count = 0`.
pub async fn clear_closed_connections(target: MihomoTarget, interval_ms: u32) {
    clear_closed(target, interval_ms).await
}
