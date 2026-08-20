//! One reconnect coordinator shared by every WebSocket of a Clash target.
//!
//! The endpoints still require separate sockets, but their availability is a
//! target-level property. The first failed stream closes its siblings and
//! starts one HTTP health probe. All streams stay parked until that probe
//! succeeds, avoiding four independent reconnect loops for an unreachable
//! target.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use tokio::sync::{broadcast, watch};

use crate::MihomoError;
use crate::backend::retry::{RetryBackoff, RetryErrorLog};
use crate::clash::api::MihomoTarget;
use crate::clash::client::WsStream;

#[derive(Clone, Copy, Default)]
struct TargetState {
    generation: u64,
    outage: u64,
    recovered: u64,
}

impl TargetState {
    fn is_ready(&self) -> bool {
        self.recovered == self.outage
    }

    fn disconnect(&mut self, generation: u64, outage: u64) -> Option<u64> {
        if self.generation != generation || self.outage != outage || !self.is_ready() {
            return None;
        }
        self.outage = self.outage.wrapping_add(1);
        Some(self.outage)
    }

    fn recover(&mut self, generation: u64, outage: u64) -> bool {
        if self.generation != generation || self.outage != outage || self.is_ready() {
            return false;
        }
        self.recovered = self.outage;
        true
    }

    fn pending(&self, generation: u64, outage: u64) -> bool {
        self.generation == generation && self.outage == outage && !self.is_ready()
    }

    fn stop(&mut self) {
        self.generation = self.generation.wrapping_add(1);
        self.recovered = self.outage;
    }
}

struct Registry {
    states: Mutex<HashMap<String, TargetState>>,
    tick_tx: watch::Sender<u64>,
}

fn registry() -> &'static Registry {
    static R: OnceLock<Registry> = OnceLock::new();
    R.get_or_init(|| {
        let (tick_tx, _) = watch::channel(0u64);
        Registry {
            states: Mutex::new(HashMap::new()),
            tick_tx,
        }
    })
}

fn target_key(target: &MihomoTarget) -> String {
    target.identity_key()
}

fn state(key: &str) -> TargetState {
    registry()
        .states
        .lock()
        .expect("stream manager poisoned")
        .get(key)
        .copied()
        .unwrap_or_default()
}

pub fn generation(target: &MihomoTarget) -> u64 {
    state(&target_key(target)).generation
}

fn notify() {
    registry()
        .tick_tx
        .send_modify(|tick| *tick = tick.wrapping_add(1));
}

pub struct TargetStream {
    target: MihomoTarget,
    key: String,
    generation: u64,
    outage: u64,
    ticks: watch::Receiver<u64>,
}

impl TargetStream {
    pub fn new(target: &MihomoTarget, generation: u64) -> Self {
        let key = target_key(target);
        Self {
            target: target.clone(),
            outage: state(&key).outage,
            key,
            generation,
            ticks: registry().tick_tx.subscribe(),
        }
    }

    pub fn stopped(&self) -> bool {
        state(&self.key).generation != self.generation
    }

    /// Wait for the shared HTTP probe, the last listener dropping, or an
    /// explicit stop. Only a successful probe returns true.
    pub async fn wait_ready<T: Clone>(&mut self, sender: &broadcast::Sender<T>) -> bool {
        tokio::select! {
            biased;
            _ = sender.closed() => false,
            ready = self.wait_for_recovery() => ready,
        }
    }

    async fn wait_for_recovery(&mut self) -> bool {
        loop {
            let current = state(&self.key);
            if current.generation != self.generation {
                return false;
            }
            if current.is_ready() {
                self.outage = current.outage;
                return true;
            }
            if self.ticks.changed().await.is_err() {
                return false;
            }
        }
    }

    /// Open a socket as part of the current shared connection round. A stop
    /// or sibling failure also cancels an in-flight handshake.
    pub async fn open<T: Clone>(
        &mut self,
        path: &str,
        sender: &broadcast::Sender<T>,
    ) -> Result<Option<WsStream>, MihomoError> {
        let client = self.target.client()?;
        tokio::select! {
            biased;
            _ = sender.closed() => Ok(None),
            _ = self.changed() => Ok(None),
            result = client.open_ws(path) => result.map(Some),
        }
    }

    /// Wake an active socket when the target stops or a sibling detects an
    /// outage in the current connection round.
    pub async fn changed(&mut self) {
        loop {
            let current = state(&self.key);
            if current.generation != self.generation || current.outage != self.outage {
                return;
            }
            if self.ticks.changed().await.is_err() {
                return;
            }
        }
    }

    /// Collapse simultaneous failures into one outage and one health probe.
    pub fn disconnect(&self) -> bool {
        let outage = registry()
            .states
            .lock()
            .expect("stream manager poisoned")
            .entry(self.key.clone())
            .or_default()
            .disconnect(self.generation, self.outage);
        let Some(outage) = outage else {
            return false;
        };
        notify();
        tokio::spawn(probe(
            self.target.clone(),
            self.key.clone(),
            self.generation,
            outage,
        ));
        true
    }
}

async fn probe(target: MihomoTarget, key: String, generation: u64, outage: u64) {
    let mut backoff = RetryBackoff::new();
    let mut error_log = RetryErrorLog::new("clash stream health probe");
    let client = match target.client() {
        Ok(client) => client,
        Err(error) => {
            error_log.record(&error);
            return;
        }
    };
    let mut ticks = registry().tick_tx.subscribe();

    loop {
        let result = tokio::select! {
            result = client.get_json("version") => result.map(|_| ()),
            _ = wait_until_resolved(&key, generation, outage, &mut ticks) => return,
        };
        match result {
            Ok(()) => {
                recover(&key, generation, outage);
                return;
            }
            Err(error) => error_log.record(&error),
        }

        tokio::select! {
            _ = tokio::time::sleep(backoff.next_delay()) => {}
            _ = wait_until_resolved(&key, generation, outage, &mut ticks) => return,
        }
    }
}

async fn wait_until_resolved(
    key: &str,
    generation: u64,
    outage: u64,
    ticks: &mut watch::Receiver<u64>,
) {
    loop {
        if !state(key).pending(generation, outage) {
            return;
        }
        if ticks.changed().await.is_err() {
            return;
        }
    }
}

fn recover(key: &str, generation: u64, outage: u64) {
    let changed = registry()
        .states
        .lock()
        .expect("stream manager poisoned")
        .entry(key.to_owned())
        .or_default()
        .recover(generation, outage);
    if changed {
        notify();
    }
}

/// Stop every current stream and health probe for a target. Future
/// subscriptions receive a new generation and may connect immediately.
pub fn stop(target: &MihomoTarget) {
    {
        let mut states = registry().states.lock().expect("stream manager poisoned");
        let state = states.entry(target_key(target)).or_default();
        state.stop();
    }
    notify();
}

#[cfg(test)]
mod tests {
    use super::TargetState;

    #[test]
    fn sibling_failures_start_one_outage() {
        let mut state = TargetState::default();
        assert_eq!(state.disconnect(0, 0), Some(1));
        assert_eq!(state.disconnect(0, 0), None);
        assert!(state.pending(0, 1));
    }

    #[test]
    fn only_the_matching_probe_can_recover_an_outage() {
        let mut state = TargetState::default();
        let outage = state.disconnect(0, 0).unwrap();
        assert!(!state.recover(1, outage));
        assert!(!state.recover(0, outage + 1));
        assert!(state.recover(0, outage));
        assert!(!state.pending(0, outage));
    }

    #[test]
    fn stopped_stream_cannot_start_an_outage() {
        let mut state = TargetState {
            generation: 1,
            ..TargetState::default()
        };
        assert_eq!(state.disconnect(0, 0), None);
    }

    #[test]
    fn stop_resolves_the_old_outage_and_starts_a_ready_generation() {
        let mut state = TargetState::default();
        let outage = state.disconnect(0, 0).unwrap();
        state.stop();
        assert!(!state.pending(0, outage));
        assert_eq!(state.generation, 1);
        assert!(state.is_ready());
    }
}
