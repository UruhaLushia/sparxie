//! Explicit stop signal for the per-target streaming loops.
//!
//! flutter_rust_bridge does not abort a Rust async task when Dart cancels the
//! corresponding stream subscription — the spawned future runs to completion,
//! and the only liveness signal is `sink.add()` failing. That works while
//! frames flow (a live backend switch: the next frame's `add` fails, the
//! wrapper drops its receiver, and the producer self-prunes). But a *dead*
//! upstream (unreachable socket) produces no frames, so the wrapper parks on
//! `stream.next()` forever and the producer retries the dead socket on a
//! timer, spamming errors.
//!
//! So Dart explicitly calls [`stop`] for a backend it's switching away from.
//! Each producer captures its target's stop [`generation`] at start and bails
//! once it differs. A global [`watch`] tick (race-free, unlike `Notify`) wakes
//! producers blocked on a read or retry backoff so teardown is prompt.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use tokio::sync::watch;

use crate::clash::api::MihomoTarget;

struct Registry {
    /// base target key → monotonically increasing stop generation.
    generations: Mutex<HashMap<String, u64>>,
    /// Bumped on every stop so blocked producers wake and re-check.
    tick_tx: watch::Sender<u64>,
}

fn registry() -> &'static Registry {
    static R: OnceLock<Registry> = OnceLock::new();
    R.get_or_init(|| {
        let (tick_tx, _) = watch::channel(0u64);
        Registry {
            generations: Mutex::new(HashMap::new()),
            tick_tx,
        }
    })
}

/// Stable key for a target across all stream kinds (traffic/memory/connections
/// /logs), ignoring per-stream suffixes like interval or log level.
pub fn base_key(target: &MihomoTarget) -> String {
    format!(
        "{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or(""),
    )
}

/// Current stop generation for `base` (0 if never stopped).
pub fn generation(base: &str) -> u64 {
    *registry()
        .generations
        .lock()
        .expect("stream_stop poisoned")
        .get(base)
        .unwrap_or(&0)
}

/// A watch receiver for the global stop tick. Blocked producers await
/// [`watch::Receiver::changed`] on it, then re-check [`generation`].
pub fn ticks() -> watch::Receiver<u64> {
    registry().tick_tx.subscribe()
}

/// Signal every stream for `target` to tear down: bump its generation (the
/// authoritative value producers compare against) then tick the watch so any
/// blocked producer wakes immediately.
pub fn stop(target: &MihomoTarget) {
    let base = base_key(target);
    {
        let mut g = registry().generations.lock().expect("stream_stop poisoned");
        *g.entry(base).or_insert(0) += 1;
    }
    registry().tick_tx.send_modify(|t| *t = t.wrapping_add(1));
}
