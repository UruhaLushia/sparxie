//! Per-target WebSocket stream broadcasting for `/traffic` and `/memory`.
//!
//! Both endpoints emit one JSON frame per second and have lots of fan-out
//! potential (every screen in the app subscribes to traffic), so we open
//! at most one upstream connection per (target, path) and fan out via a
//! tokio broadcast channel. Idle channels self-prune.
//!
//! `/connections` lives in [`crate::connections_state`] (frame post-processing
//! + paginated row fetching), and `/logs` in [`crate::logs_state`] (ring
//! buffer + replay-on-subscribe). Those two endpoints carry too much state
//! to fit this generic broadcast pattern.

use std::collections::HashMap;
use std::marker::PhantomData;
use std::sync::OnceLock;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, broadcast};

use crate::api::MihomoTarget;
use crate::client::{MihomoClient, read_ws_text};
use crate::error::MihomoError;

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
    map: Mutex<HashMap<String, broadcast::Sender<T>>>,
    _marker: PhantomData<T>,
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
    format!(
        "{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or(""),
    )
}

async fn subscribe<T: Sample>(
    registry: &'static Registry<T>,
    key: String,
    target: MihomoTarget,
    path: String,
) -> broadcast::Receiver<T> {
    let mut map = registry.map.lock().await;
    if let Some(tx) = map.get(&key) {
        return tx.subscribe();
    }
    let (tx, rx) = broadcast::channel::<T>(64);
    map.insert(key.clone(), tx);
    drop(map);
    tokio::spawn(stream_loop::<T>(registry, target, path, key));
    rx
}

async fn stream_loop<T: Sample>(
    registry: &'static Registry<T>,
    target: MihomoTarget,
    path: String,
    key: String,
) {
    loop {
        let listeners = {
            let map = registry.map.lock().await;
            map.get(&key).map(|tx| tx.receiver_count()).unwrap_or(0)
        };
        if listeners == 0 {
            registry.map.lock().await.remove(&key);
            return;
        }
        if let Err(error) = stream_once::<T>(registry, &target, &path, &key).await {
            eprintln!("[mihomo_backend] {path} stream {key}: {error}");
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    }
}

async fn stream_once<T: Sample>(
    registry: &'static Registry<T>,
    target: &MihomoTarget,
    path: &str,
    key: &str,
) -> Result<(), MihomoError> {
    let client = MihomoClient::new(&target.base_url, target.secret.clone(), target.allow_insecure)?;
    let mut ws = client.open_ws(path).await?;
    while let Some(text) = read_ws_text(&mut ws).await? {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(sample) = T::parse(trimmed) {
            let map = registry.map.lock().await;
            if let Some(tx) = map.get(key) {
                let _ = tx.send(sample);
            }
        }
    }
    Ok(())
}

pub async fn traffic_subscribe(
    target: MihomoTarget,
) -> Result<broadcast::Receiver<TrafficSample>, MihomoError> {
    Ok(subscribe(registry_traffic(), target_key(&target), target, "traffic".into()).await)
}

pub async fn memory_subscribe(
    target: MihomoTarget,
) -> Result<broadcast::Receiver<MemorySample>, MihomoError> {
    Ok(subscribe(registry_memory(), target_key(&target), target, "memory".into()).await)
}
