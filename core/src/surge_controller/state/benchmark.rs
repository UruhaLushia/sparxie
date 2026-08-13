use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::watch;

use crate::MihomoError;
use crate::backend::retry::RetryBackoff;
use crate::surge_controller::client::{SurgeControllerTarget, target_key};

#[derive(Clone, Default)]
struct BenchmarkEntry {
    delay: i32,
    testing: bool,
    tested_at: f64,
    error: String,
}

struct Slot {
    entries: Mutex<HashMap<String, BenchmarkEntry>>,
    revision: watch::Sender<u64>,
    ready: watch::Sender<bool>,
    stop: watch::Sender<bool>,
}

impl Slot {
    fn update(&self, raw: &Value) {
        let Some(data) = benchmark_data(raw) else {
            return;
        };
        let mut entries = self
            .entries
            .lock()
            .expect("surge controller benchmark cache poisoned");
        let mut changed = false;
        for (key, value) in data {
            let next = parse_entry(value, entries.get(key).cloned());
            if entries.get(key).is_none_or(|current| {
                current.delay != next.delay
                    || current.testing != next.testing
                    || current.tested_at != next.tested_at
                    || current.error != next.error
            }) {
                entries.insert(key.clone(), next);
                changed = true;
            }
        }
        drop(entries);
        if changed {
            self.revision.send_modify(|revision| *revision += 1);
        }
    }

    fn delays(&self) -> HashMap<String, i32> {
        self.entries
            .lock()
            .expect("surge controller benchmark cache poisoned")
            .iter()
            .map(|(key, entry)| (key.clone(), entry.delay))
            .collect()
    }
}

fn slots() -> &'static Mutex<HashMap<String, Arc<Slot>>> {
    static SLOTS: OnceLock<Mutex<HashMap<String, Arc<Slot>>>> = OnceLock::new();
    SLOTS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) async fn snapshot(target: &SurgeControllerTarget) -> HashMap<String, i32> {
    let slot = slot(target);
    if slot
        .entries
        .lock()
        .expect("surge controller benchmark cache poisoned")
        .is_empty()
    {
        let mut revision = slot.revision.subscribe();
        if slot
            .entries
            .lock()
            .expect("surge controller benchmark cache poisoned")
            .is_empty()
        {
            let _ = tokio::time::timeout(Duration::from_secs(3), revision.changed()).await;
        }
    }
    slot.delays()
}

pub(crate) fn cached_delays(target: &SurgeControllerTarget) -> HashMap<String, i32> {
    slot(target).delays()
}

pub(crate) fn error(target: &SurgeControllerTarget, key: &str) -> String {
    slot(target)
        .entries
        .lock()
        .expect("surge controller benchmark cache poisoned")
        .get(key)
        .map(|entry| entry.error.clone())
        .unwrap_or_default()
}

pub(crate) async fn test_group(
    target: &SurgeControllerTarget,
    group: &str,
    keys: &[String],
) -> Result<(), MihomoError> {
    let slot = slot(target);
    wait_ready(&slot).await?;
    if keys.is_empty() {
        return Err(MihomoError::Other(format!(
            "Surge 策略组 {group} 没有可测速成员"
        )));
    }
    let before = tested_dates(&slot, keys);
    let mut revision = slot.revision.subscribe();
    let mut connection = target.connect().await?;
    connection.request(["test-group", group]).await?;
    tokio::time::timeout(Duration::from_secs(30), async {
        loop {
            if group_test_finished(&slot, keys, &before) {
                break;
            }
            if revision.changed().await.is_err() {
                break;
            }
        }
    })
    .await
    .map_err(|_| MihomoError::Network("等待 Surge 策略组延迟结果超时".into()))?;
    Ok(())
}

pub(crate) fn update_policy(target: &SurgeControllerTarget, key: String, delay: i32) {
    let slot = slot(target);
    slot.entries
        .lock()
        .expect("surge controller benchmark cache poisoned")
        .entry(key)
        .and_modify(|entry| {
            entry.delay = delay;
            entry.testing = false;
            entry.error.clear();
        })
        .or_insert(BenchmarkEntry {
            delay,
            ..Default::default()
        });
    slot.revision.send_modify(|revision| *revision += 1);
}

pub(crate) fn release_target(target: &SurgeControllerTarget) {
    if let Some(slot) = slots()
        .lock()
        .expect("surge controller benchmark slots poisoned")
        .remove(&target_key(target))
    {
        let _ = slot.stop.send(true);
    }
}

fn slot(target: &SurgeControllerTarget) -> Arc<Slot> {
    let key = target_key(target);
    let mut slots = slots()
        .lock()
        .expect("surge controller benchmark slots poisoned");
    if let Some(slot) = slots.get(&key) {
        return Arc::clone(slot);
    }
    let (revision, _) = watch::channel(0);
    let (ready, _) = watch::channel(false);
    let (stop, _) = watch::channel(false);
    let slot = Arc::new(Slot {
        entries: Mutex::new(HashMap::new()),
        revision,
        ready,
        stop,
    });
    slots.insert(key, Arc::clone(&slot));
    tokio::spawn(watch_loop(target.clone(), Arc::clone(&slot)));
    slot
}

async fn watch_loop(target: SurgeControllerTarget, slot: Arc<Slot>) {
    let mut backoff = RetryBackoff::new();
    loop {
        if *slot.stop.borrow() {
            return;
        }
        slot.ready.send_replace(false);
        match watch_once(&target, &slot).await {
            Ok(()) => return,
            Err(error) => {
                if *slot.ready.borrow() {
                    backoff.reset();
                }
                eprintln!("[backend] surge policy benchmark stream: {error}");
            }
        }
        let mut stop = slot.stop.subscribe();
        if *stop.borrow() {
            return;
        }
        tokio::select! {
            _ = tokio::time::sleep(backoff.next_delay()) => {}
            _ = stop.changed() => return,
        }
    }
}

async fn watch_once(target: &SurgeControllerTarget, slot: &Slot) -> Result<(), MihomoError> {
    if *slot.stop.borrow() {
        return Ok(());
    }
    let mut connection = target.connect().await?;
    connection.request(["watch", "policy-benchmark"]).await?;
    slot.ready.send_replace(true);
    let mut stop = slot.stop.subscribe();
    if *stop.borrow() {
        return Ok(());
    }
    loop {
        tokio::select! {
            changed = stop.changed() => {
                if changed.is_err() || *stop.borrow() {
                    return Ok(());
                }
            }
            raw = connection.next_stream_value() => slot.update(&raw?),
        }
    }
}

async fn wait_ready(slot: &Slot) -> Result<(), MihomoError> {
    let mut ready = slot.ready.subscribe();
    if *ready.borrow() {
        return Ok(());
    }
    tokio::time::timeout(Duration::from_secs(3), async {
        while !*ready.borrow() {
            if ready.changed().await.is_err() {
                break;
            }
        }
    })
    .await
    .map_err(|_| MihomoError::Network("连接 Surge 延迟事件流超时".into()))?;
    if *ready.borrow() {
        Ok(())
    } else {
        Err(MihomoError::Network("Surge 延迟事件流已断开".into()))
    }
}

fn benchmark_data(raw: &Value) -> Option<&serde_json::Map<String, Value>> {
    if raw
        .get("event")
        .and_then(Value::as_str)
        .is_some_and(|event| event != "policy-benchmark")
    {
        return None;
    }
    raw.get("data").unwrap_or(raw).as_object()
}

fn parse_entry(raw: &Value, previous: Option<BenchmarkEntry>) -> BenchmarkEntry {
    let testing = raw
        .get("testing")
        .and_then(Value::as_i64)
        .unwrap_or_default()
        != 0;
    let tested_at = raw
        .get("lastTestDate")
        .and_then(Value::as_f64)
        .unwrap_or_default();
    let score = raw
        .get("lastTestScoreInMS")
        .and_then(Value::as_i64)
        .and_then(|score| i32::try_from(score).ok())
        .unwrap_or_default();
    let error = raw
        .get("lastTestErrorMessage")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let delay = if testing {
        previous.as_ref().map(|entry| entry.delay).unwrap_or(-1)
    } else if score > 0 {
        score
    } else if score < 0 || !error.is_empty() {
        0
    } else {
        -1
    };
    BenchmarkEntry {
        delay,
        testing,
        tested_at,
        error,
    }
}

fn tested_dates(slot: &Slot, keys: &[String]) -> HashMap<String, f64> {
    let entries = slot
        .entries
        .lock()
        .expect("surge controller benchmark cache poisoned");
    keys.iter()
        .filter_map(|key| entries.get(key).map(|entry| (key.clone(), entry.tested_at)))
        .collect()
}

fn group_test_finished(slot: &Slot, keys: &[String], before: &HashMap<String, f64>) -> bool {
    let entries = slot
        .entries
        .lock()
        .expect("surge controller benchmark cache poisoned");
    let mut updated = false;
    for key in keys {
        let Some(entry) = entries.get(key) else {
            continue;
        };
        if entry.testing {
            return false;
        }
        updated |= entry.tested_at > before.get(key).copied().unwrap_or_default();
    }
    updated
}
