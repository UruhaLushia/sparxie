//! Remote proxy-group icon cache with stale-while-revalidate semantics.
//!
//! Backed by the shared redb database ([`crate::cache::db`]). Entries are
//! stamped with their fetch time; reads return cached bytes immediately and
//! spawn a background refetch once an entry is older than [`TTL`]. Misses
//! fetch synchronously, coalescing concurrent first-time fetches per URL.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use reqwest::Client;
use tokio::sync::Mutex as AsyncMutex;

use crate::MihomoError;
use crate::cache::db::{self, ICONS};

/// 1 day; entries older than this trigger a background refetch.
pub const TTL: Duration = Duration::from_secs(24 * 60 * 60);

struct State {
    client: Client,
    /// URLs currently being refetched in the background, so we don't
    /// fan out multiple parallel refreshes for the same icon.
    inflight: Mutex<HashSet<String>>,
    /// Per-URL locks that serialize first-time (cache-miss) downloads, so a
    /// burst of nodes sharing one group icon results in a single fetch.
    miss_locks: Mutex<HashMap<String, Arc<AsyncMutex<()>>>>,
}

static STATE: OnceLock<State> = OnceLock::new();

/// Initialize the HTTP client. The shared cache DB is opened separately via
/// [`db::init`]. Idempotent.
pub fn init() -> Result<(), MihomoError> {
    if STATE.get().is_some() {
        return Ok(());
    }
    let client = Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| MihomoError::Other(format!("icon http client build: {e}")))?;
    let _ = STATE.set(State {
        client,
        inflight: Mutex::new(HashSet::new()),
        miss_locks: Mutex::new(HashMap::new()),
    });
    Ok(())
}

fn state() -> Result<&'static State, MihomoError> {
    STATE
        .get()
        .ok_or_else(|| MihomoError::Other("icon cache not initialized".into()))
}

fn key_for(url: &str) -> String {
    blake3::hash(url.as_bytes()).to_hex().to_string()
}

/// Return cached bytes for `url`: fresh hit returns immediately, stale hit
/// returns immediately and refetches in the background, miss fetches
/// synchronously (coalesced per URL).
pub async fn fetch(url: String) -> Result<Vec<u8>, MihomoError> {
    let state = state()?;
    let key = key_for(&url);

    if let Some((created, bytes)) = read_entry(&key).await? {
        if db::age(created) >= TTL {
            spawn_refetch(state, url.clone(), key.clone());
        }
        return Ok(bytes);
    }

    // Miss — coalesce concurrent first-time fetches for the same URL.
    let lock = miss_lock_for(state, &url);
    let _guard = lock.lock().await;

    if let Some((_, bytes)) = read_entry(&key).await? {
        release_miss_lock(state, &url);
        return Ok(bytes);
    }

    let result = download(&state.client, &url).await;
    if let Ok(bytes) = &result {
        let _ = store_entry(key, bytes.clone()).await;
    }
    drop(_guard);
    release_miss_lock(state, &url);
    result
}

async fn read_entry(key: &str) -> Result<Option<(u64, Vec<u8>)>, MihomoError> {
    let key = key.to_string();
    let raw = tokio::task::spawn_blocking(move || db::get_bytes(ICONS, &key))
        .await
        .map_err(|e| MihomoError::Other(format!("icon cache join: {e}")))??;
    Ok(raw.and_then(|v| db::unstamp(&v).map(|(s, b)| (s, b.to_vec()))))
}

async fn store_entry(key: String, bytes: Vec<u8>) -> Result<(), MihomoError> {
    let value = db::stamp(db::now_secs(), &bytes);
    tokio::task::spawn_blocking(move || db::put_bytes(ICONS, &key, &value))
        .await
        .map_err(|e| MihomoError::Other(format!("icon cache join: {e}")))?
}

fn miss_lock_for(state: &State, url: &str) -> Arc<AsyncMutex<()>> {
    let mut map = state.miss_locks.lock().expect("icon miss_locks poisoned");
    map.entry(url.to_string())
        .or_insert_with(|| Arc::new(AsyncMutex::new(())))
        .clone()
}

fn release_miss_lock(state: &State, url: &str) {
    let mut map = state.miss_locks.lock().expect("icon miss_locks poisoned");
    if let Some(lock) = map.get(url)
        && Arc::strong_count(lock) <= 2
    {
        map.remove(url);
    }
}

async fn download(client: &Client, url: &str) -> Result<Vec<u8>, MihomoError> {
    let response = client
        .get(url)
        .send()
        .await
        .map_err(|e| MihomoError::Network(format!("icon fetch {url}: {e}")))?;
    if !response.status().is_success() {
        return Err(MihomoError::Upstream {
            status: response.status().as_u16(),
            body: format!("icon fetch {url} failed"),
        });
    }
    let bytes = response
        .bytes()
        .await
        .map_err(|e| MihomoError::Network(format!("icon read {url}: {e}")))?;
    Ok(bytes.to_vec())
}

fn spawn_refetch(state: &'static State, url: String, key: String) {
    let mut inflight = match state.inflight.lock() {
        Ok(g) => g,
        Err(_) => return,
    };
    if !inflight.insert(url.clone()) {
        return; // already refreshing
    }
    drop(inflight);

    let client = state.client.clone();
    let inflight = &state.inflight;
    tokio::spawn(async move {
        if let Ok(bytes) = download(&client, &url).await {
            let _ = store_entry(key, bytes).await;
        }
        if let Ok(mut guard) = inflight.lock() {
            guard.remove(&url);
        }
    });
}
