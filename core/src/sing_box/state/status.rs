use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use tokio::sync::{Mutex as AsyncMutex, broadcast};

use crate::MihomoError;
use crate::backend::api::{ConnectionsTotals, MemorySample, TrafficSample};
use crate::sing_box::client::{SingBoxTarget, target_key};
use crate::sing_box::proto::daemon::{Status, SubscribeStatusRequest};

#[derive(Clone, Default)]
struct LastStatus {
    traffic: TrafficSample,
    memory: MemorySample,
}

fn cache() -> &'static Mutex<HashMap<String, LastStatus>> {
    static C: OnceLock<Mutex<HashMap<String, LastStatus>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(HashMap::new()))
}

struct TargetSlot {
    sender: broadcast::Sender<(TrafficSample, MemorySample)>,
}

type SlotMap = HashMap<String, Arc<TargetSlot>>;

fn slots() -> &'static AsyncMutex<SlotMap> {
    static M: OnceLock<AsyncMutex<SlotMap>> = OnceLock::new();
    M.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

fn interval_or_default(interval_ms: u32) -> u32 {
    if interval_ms == 0 { 1000 } else { interval_ms }
}

fn slot_key(target: &SingBoxTarget, interval_ms: u32) -> String {
    format!("{}|{}", target_key(target), interval_ms)
}

pub async fn subscribe(
    target: SingBoxTarget,
    interval_ms: u32,
) -> Result<broadcast::Receiver<(TrafficSample, MemorySample)>, MihomoError> {
    let interval = interval_or_default(interval_ms);
    let key = slot_key(&target, interval);
    let mut map = slots().lock().await;
    if let Some(slot) = map.get(&key) {
        return Ok(slot.sender.subscribe());
    }
    let (tx, rx) = broadcast::channel(64);
    let slot = Arc::new(TargetSlot { sender: tx });
    map.insert(key.clone(), slot.clone());
    drop(map);
    tokio::spawn(stream_loop(target, interval, key, slot));
    Ok(rx)
}

pub fn store(target: &SingBoxTarget, status: &Status) -> (TrafficSample, MemorySample) {
    let traffic = TrafficSample {
        up: non_negative(status.uplink),
        down: non_negative(status.downlink),
        up_total: non_negative(status.uplink_total),
        down_total: non_negative(status.downlink_total),
    };
    let memory = MemorySample {
        inuse: status.memory,
        oslimit: 0,
    };
    cache()
        .lock()
        .expect("sing-box status cache poisoned")
        .insert(
            target_key(target),
            LastStatus {
                traffic: traffic.clone(),
                memory: memory.clone(),
            },
        );
    (traffic, memory)
}

pub fn totals(target: &SingBoxTarget) -> ConnectionsTotals {
    let guard = cache().lock().expect("sing-box status cache poisoned");
    let Some(status) = guard.get(&target_key(target)) else {
        return ConnectionsTotals::default();
    };
    ConnectionsTotals {
        upload: status.traffic.up_total,
        download: status.traffic.down_total,
        memory: status.memory.inuse,
    }
}

async fn stream_loop(target: SingBoxTarget, interval_ms: u32, key: String, slot: Arc<TargetSlot>) {
    loop {
        if slot.sender.receiver_count() == 0 {
            slots().lock().await.remove(&key);
            return;
        }
        match stream_once(&target, interval_ms, &slot).await {
            Ok(()) => {}
            Err(error) => {
                eprintln!("[backend] sing-box status stream {key}: {error}");
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }
        }
    }
}

async fn stream_once(
    target: &SingBoxTarget,
    interval_ms: u32,
    slot: &TargetSlot,
) -> Result<(), MihomoError> {
    let request = SubscribeStatusRequest {
        interval: (interval_ms as i64) * 1_000_000,
    };
    let mut stream = target
        .client()
        .await?
        .subscribe_status(request)
        .await?
        .into_inner();
    while let Some(status) = stream.message().await? {
        let _ = slot.sender.send(store(target, &status));
    }
    Ok(())
}

fn non_negative(value: i64) -> u64 {
    if value < 0 { 0 } else { value as u64 }
}
