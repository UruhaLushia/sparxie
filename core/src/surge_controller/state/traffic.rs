use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{broadcast, watch};

use crate::MihomoError;
use crate::backend::api::TrafficSample;
use crate::backend::retry::{RetryBackoff, RetryErrorLog};
use crate::surge_controller::client::{SurgeControllerTarget, target_key};

const EVENT_TIMEOUT: Duration = Duration::from_secs(5);

struct Slot {
    sender: broadcast::Sender<TrafficSample>,
    stop: watch::Sender<bool>,
}

#[derive(Default)]
struct ConnectorTraffic {
    up_total: u64,
    down_total: u64,
}

#[derive(Default)]
struct TrafficState {
    connectors: HashMap<String, ConnectorTraffic>,
    sample: TrafficSample,
}

fn slots() -> &'static Mutex<HashMap<String, Arc<Slot>>> {
    static SLOTS: OnceLock<Mutex<HashMap<String, Arc<Slot>>>> = OnceLock::new();
    SLOTS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn subscribe(target: SurgeControllerTarget) -> broadcast::Receiver<TrafficSample> {
    let key = target_key(&target);
    let mut slots = slots()
        .lock()
        .expect("surge controller traffic slots poisoned");
    if let Some(slot) = slots.get(&key) {
        return slot.sender.subscribe();
    }
    let (sender, receiver) = broadcast::channel(8);
    let (stop, _) = watch::channel(false);
    let slot = Arc::new(Slot { sender, stop });
    slots.insert(key.clone(), Arc::clone(&slot));
    tokio::spawn(stream_loop(target, key, Arc::clone(&slot)));
    receiver
}

pub(crate) fn release_target(target: &SurgeControllerTarget) {
    if let Some(slot) = slots()
        .lock()
        .expect("surge controller traffic slots poisoned")
        .remove(&target_key(target))
    {
        let _ = slot.stop.send(true);
    }
}

async fn stream_loop(target: SurgeControllerTarget, key: String, slot: Arc<Slot>) {
    let mut backoff = RetryBackoff::new();
    let mut error_log = RetryErrorLog::new("surge traffic stream");
    let mut state = TrafficState::default();
    loop {
        if should_stop(&slot) {
            remove_slot(&key, &slot);
            return;
        }
        match stream_once(&target, &slot, &mut state, &mut backoff, &mut error_log).await {
            Ok(()) => {
                remove_slot(&key, &slot);
                return;
            }
            Err(error) => error_log.record(&error),
        }
        let mut stop = slot.stop.subscribe();
        tokio::select! {
            _ = tokio::time::sleep(backoff.next_delay()) => {}
            _ = stop.changed() => {
                remove_slot(&key, &slot);
                return;
            }
        }
    }
}

async fn stream_once(
    target: &SurgeControllerTarget,
    slot: &Slot,
    state: &mut TrafficState,
    backoff: &mut RetryBackoff,
    error_log: &mut RetryErrorLog,
) -> Result<(), MihomoError> {
    let mut connection = target.connect().await?;
    let initial = connection.request(["dump", "traffic"]).await?;
    state.replace_connectors(initial.get("data").unwrap_or(&initial));
    connection
        .request(["watch", "real-time-speed", "traffic"])
        .await?;
    if slot.sender.send(state.sample.clone()).is_err() {
        return Ok(());
    }
    let mut stop = slot.stop.subscribe();
    loop {
        if should_stop(slot) {
            return Ok(());
        }
        tokio::select! {
            changed = stop.changed() => {
                if changed.is_err() || *stop.borrow() {
                    return Ok(());
                }
            }
            raw = tokio::time::timeout(EVENT_TIMEOUT, connection.next_stream_value()) => {
                let raw = raw
                    .map_err(|_| MihomoError::Network("Surge 流量事件流超时".into()))??;
                backoff.reset();
                error_log.recovered();
                if let Some(sample) = state.update(&raw)
                    && slot.sender.send(sample).is_err()
                {
                    return Ok(());
                }
            }
        }
    }
}

fn should_stop(slot: &Slot) -> bool {
    *slot.stop.borrow() || slot.sender.receiver_count() == 0
}

fn remove_slot(key: &str, slot: &Arc<Slot>) {
    let mut slots = slots()
        .lock()
        .expect("surge controller traffic slots poisoned");
    if slots
        .get(key)
        .is_some_and(|current| Arc::ptr_eq(current, slot))
    {
        slots.remove(key);
    }
}

impl TrafficState {
    fn update(&mut self, raw: &Value) -> Option<TrafficSample> {
        match raw.get("event").and_then(Value::as_str)? {
            "traffic" => {
                self.update_connectors(raw.get("data").unwrap_or(raw));
                None
            }
            "real-time-speed" => {
                let data = raw.get("data").unwrap_or(raw);
                self.sample.up = field_u64(data, "out").unwrap_or_default();
                self.sample.down = field_u64(data, "in").unwrap_or_default();
                Some(self.sample.clone())
            }
            _ => None,
        }
    }

    fn replace_connectors(&mut self, data: &Value) {
        self.connectors.clear();
        self.sample.up_total = 0;
        self.sample.down_total = 0;
        self.update_connectors(data);
    }

    fn update_connectors(&mut self, data: &Value) {
        let Some(connectors) = data.get("connector").and_then(Value::as_object) else {
            return;
        };
        for (key, raw) in connectors {
            let connector = self.connectors.entry(key.clone()).or_default();
            if let Some(value) = field_u64(raw, "out") {
                self.sample.up_total = self
                    .sample
                    .up_total
                    .saturating_sub(connector.up_total)
                    .saturating_add(value);
                connector.up_total = value;
            }
            if let Some(value) = field_u64(raw, "in") {
                self.sample.down_total = self
                    .sample
                    .down_total
                    .saturating_sub(connector.down_total)
                    .saturating_add(value);
                connector.down_total = value;
            }
        }
    }
}

fn field_u64(raw: &Value, key: &str) -> Option<u64> {
    match raw.get(key)? {
        Value::Number(value) => value
            .as_u64()
            .or_else(|| value.as_i64().map(|value| value.max(0) as u64)),
        Value::String(value) => value.parse().ok(),
        _ => None,
    }
}
