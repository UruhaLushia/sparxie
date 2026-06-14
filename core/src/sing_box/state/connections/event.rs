use crate::backend::api::ConnectionsFrame;
use crate::sing_box::client::SingBoxTarget;
use crate::sing_box::proto::daemon::{ConnectionEvent, ConnectionEventType, ConnectionEvents};

use super::parse::{closed_time, parse_connection, speed};
use super::{State, TargetSlot, push_closed};
use crate::sing_box::state::status;

pub(super) fn apply_events(
    target: &SingBoxTarget,
    slot: &TargetSlot,
    events: ConnectionEvents,
    interval_ms: u32,
    is_initial: bool,
) -> ConnectionsFrame {
    let mut state = slot
        .state
        .lock()
        .expect("sing-box connections state poisoned");
    if events.reset {
        state.active.clear();
        state.closed.clear();
    }
    let dt_secs = (interval_ms as f64 / 1000.0).max(0.05);
    for event in events.events {
        apply_event(&mut state, event, dt_secs);
    }
    ConnectionsFrame {
        active_count: state.active.len() as u32,
        closed_count: state.closed.len() as u32,
        totals: status::totals(target),
        is_initial,
    }
}

fn apply_event(state: &mut State, event: ConnectionEvent, dt_secs: f64) {
    let id = if event.id.is_empty() {
        event
            .connection
            .as_ref()
            .map(|c| c.id.clone())
            .unwrap_or_default()
    } else {
        event.id.clone()
    };
    if id.is_empty() {
        return;
    }
    match ConnectionEventType::try_from(event.r#type)
        .unwrap_or(ConnectionEventType::ConnectionEventUpdate)
    {
        ConnectionEventType::ConnectionEventClosed => close_event(state, id, event, dt_secs),
        ConnectionEventType::ConnectionEventNew | ConnectionEventType::ConnectionEventUpdate => {
            upsert_event(state, id, event, dt_secs)
        }
    }
}

fn upsert_event(state: &mut State, id: String, event: ConnectionEvent, dt_secs: f64) {
    let up_speed = speed(event.uplink_delta, dt_secs);
    let down_speed = speed(event.downlink_delta, dt_secs);
    if let Some(raw) = event.connection {
        let mut row = parse_connection(raw, up_speed, down_speed);
        row.id = id.clone();
        if row.is_closed {
            push_closed(state, row);
        } else {
            state.active.insert(id, row);
        }
        return;
    }
    if let Some(row) = state.active.get_mut(&id) {
        row.upload = row.upload.saturating_add(event.uplink_delta.max(0) as u64);
        row.download = row
            .download
            .saturating_add(event.downlink_delta.max(0) as u64);
        row.upload_speed = up_speed;
        row.download_speed = down_speed;
    }
}

fn close_event(state: &mut State, id: String, event: ConnectionEvent, dt_secs: f64) {
    let mut row = event
        .connection
        .map(|raw| {
            parse_connection(
                raw,
                speed(event.uplink_delta, dt_secs),
                speed(event.downlink_delta, dt_secs),
            )
        })
        .or_else(|| state.active.remove(&id))
        .unwrap_or_default();
    row.id = id;
    row.is_closed = true;
    row.upload_speed = 0;
    row.download_speed = 0;
    if event.closed_at > 0 {
        row.connection_logs
            .push(format!("closed_at={}", closed_time(event.closed_at)));
    }
    push_closed(state, row);
}
