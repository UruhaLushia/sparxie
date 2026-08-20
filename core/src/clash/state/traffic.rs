//! Per-target WebSocket stream broadcasting for `/traffic` and `/memory`.
//!
//! Both endpoints emit one JSON frame per second and have lots of fan-out
//! potential (every screen in the app subscribes to traffic), so we open
//! at most one upstream connection per (target, path) and fan out via a
//! tokio broadcast channel. Idle channels self-prune.
//!
//! `/connections` lives in [`crate::clash::state::connections`] (frame post-processing
//! + paginated row fetching), and `/logs` in [`crate::clash::state::logs`] (ring
//!   buffer + replay-on-subscribe). Those two endpoints carry too much state
//!   to fit this generic broadcast pattern.

use std::collections::HashMap;
use std::marker::PhantomData;
use std::sync::{Arc, OnceLock};

use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, broadcast};

use crate::MihomoError;
use crate::clash::api::MihomoTarget;
use crate::clash::client::read_ws_text;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TrafficSample {
    pub up: u64,
    pub down: u64,
    #[serde(default, rename = "upTotal")]
    pub up_total: u64,
    #[serde(default, rename = "downTotal")]
    pub down_total: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct MemorySample {
    #[serde(default)]
    pub inuse: u64,
    #[serde(default)]
    pub oslimit: u64,
}

trait Sample: Clone + Send + Sync + 'static {
    fn parse(line: &str) -> Option<Self>;
}

impl Sample for TrafficSample {
    fn parse(line: &str) -> Option<Self> {
        serde_json::from_str(line).ok()
    }
}

impl Sample for MemorySample {
    fn parse(line: &str) -> Option<Self> {
        serde_json::from_str(line).ok()
    }
}

struct Registry<T: Sample> {
    map: Mutex<HashMap<String, Arc<TargetSlot<T>>>>,
    _marker: PhantomData<T>,
}

struct TargetSlot<T: Sample> {
    sender: broadcast::Sender<T>,
    generation: u64,
}

impl<T: Sample> Registry<T> {
    fn new() -> Self {
        Self {
            map: Mutex::new(HashMap::new()),
            _marker: PhantomData,
        }
    }
}

fn registry_traffic() -> &'static Registry<TrafficSample> {
    static R: OnceLock<Registry<TrafficSample>> = OnceLock::new();
    R.get_or_init(Registry::new)
}

fn registry_memory() -> &'static Registry<MemorySample> {
    static R: OnceLock<Registry<MemorySample>> = OnceLock::new();
    R.get_or_init(Registry::new)
}

fn target_key(target: &MihomoTarget) -> String {
    target.identity_key()
}

async fn subscribe<T: Sample>(
    registry: &'static Registry<T>,
    key: String,
    target: MihomoTarget,
    path: String,
) -> broadcast::Receiver<T> {
    let generation = crate::clash::state::stream_manager::generation(&target);
    let mut map = registry.map.lock().await;
    if let Some(slot) = map.get(&key).filter(|slot| slot.generation == generation) {
        return slot.sender.subscribe();
    }
    let (tx, rx) = broadcast::channel::<T>(64);
    let slot = Arc::new(TargetSlot {
        sender: tx,
        generation,
    });
    map.insert(key.clone(), slot.clone());
    drop(map);
    tokio::spawn(stream_loop::<T>(registry, target, path, key, slot));
    rx
}

async fn stream_loop<T: Sample>(
    registry: &'static Registry<T>,
    target: MihomoTarget,
    path: String,
    key: String,
    slot: Arc<TargetSlot<T>>,
) {
    let mut stream =
        crate::clash::state::stream_manager::TargetStream::new(&target, slot.generation);
    loop {
        // Re-check under the registry lock before removing, so a subscriber
        // that attaches just as the stream ends isn't orphaned.
        {
            let mut map = registry.map.lock().await;
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
        if let Err(error) = stream_once::<T>(&path, &mut stream, &slot).await
            && stream.disconnect()
        {
            eprintln!("[mihomo_backend] {path} stream {key}: {error}");
        }
    }
}

async fn stream_once<T: Sample>(
    path: &str,
    stream: &mut crate::clash::state::stream_manager::TargetStream,
    slot: &TargetSlot<T>,
) -> Result<(), MihomoError> {
    let Some(mut ws) = stream.open(path, &slot.sender).await? else {
        return Ok(());
    };
    loop {
        // Tear down promptly on either signal: the last subscriber dropping
        // (live switch — `closed()`) or an explicit Dart stop (dead upstream —
        // the stop tick, since no frame would arrive to fail a sink send).
        let text = tokio::select! {
            biased;
            _ = slot.sender.closed() => return Ok(()),
            _ = stream.changed() => return Ok(()),
            read = read_ws_text(&mut ws) => match read? {
                Some(t) => t,
                None => return Err(MihomoError::Network(format!("{path} WebSocket closed"))),
            },
        };
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(sample) = T::parse(trimmed) {
            let _ = slot.sender.send(sample);
        }
    }
}

pub async fn traffic_subscribe(
    target: MihomoTarget,
) -> Result<broadcast::Receiver<TrafficSample>, MihomoError> {
    Ok(subscribe(
        registry_traffic(),
        target_key(&target),
        target,
        "traffic".into(),
    )
    .await)
}

pub async fn memory_subscribe(
    target: MihomoTarget,
) -> Result<broadcast::Receiver<MemorySample>, MihomoError> {
    Ok(subscribe(
        registry_memory(),
        target_key(&target),
        target,
        "memory".into(),
    )
    .await)
}
