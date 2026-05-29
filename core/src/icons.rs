//! On-disk icon cache with stale-while-revalidate semantics.
//!
//! Calls return whatever's on disk immediately (even if stale); when an
//! entry's mtime is older than [`TTL`] a background refetch is spawned but
//! we still serve the stale bytes. On miss we fetch synchronously.
//!
//! Initialized once from Dart with the platform's cache directory; paths
//! and config live in a single global [`State`].

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime};

use reqwest::Client;
use tokio::fs;
use tokio::sync::Mutex as AsyncMutex;

use crate::error::MihomoError;

/// 1 day; entries older than this trigger a background refetch.
pub const TTL: Duration = Duration::from_secs(24 * 60 * 60);

struct State {
    dir: PathBuf,
    client: Client,
    /// URLs currently being refetched in the background, so we don't
    /// fan out multiple parallel refreshes for the same icon.
    inflight: Mutex<HashSet<String>>,
    /// Per-URL locks that serialize first-time (cache-miss) downloads, so a
    /// burst of nodes sharing one group icon results in a single fetch.
    miss_locks: Mutex<HashMap<String, Arc<AsyncMutex<()>>>>,
}

static STATE: OnceLock<State> = OnceLock::new();

/// Configure the on-disk cache directory. Called once from Dart with the
/// platform's app cache dir. Idempotent — subsequent calls are ignored
/// (the path is fixed for the process lifetime).
pub fn init(cache_dir: PathBuf) -> Result<(), MihomoError> {
    let dir = cache_dir.join("icons");
    if let Err(error) = std::fs::create_dir_all(&dir) {
        return Err(MihomoError::Other(format!(
            "failed to create icon cache dir {}: {error}",
            dir.display()
        )));
    }
    let client = Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| MihomoError::Other(format!("icon http client build: {e}")))?;
    let _ = STATE.set(State {
        dir,
        client,
        inflight: Mutex::new(HashSet::new()),
        miss_locks: Mutex::new(HashMap::new()),
    });
    Ok(())
}

fn state() -> Result<&'static State, MihomoError> {
    STATE.get().ok_or_else(|| {
        MihomoError::Other("icon cache not initialized; call init_icon_cache".into())
    })
}

fn path_for(state: &State, url: &str) -> PathBuf {
    let hash = blake3::hash(url.as_bytes());
    state.dir.join(format!("{}.bin", hash.to_hex()))
}

/// Return the cached bytes for [`url`].
///
/// - Disk hit (fresh): return bytes immediately.
/// - Disk hit (stale): return bytes immediately, refetch in the background.
/// - Disk miss: fetch synchronously and persist.
/// - Network failure on miss: return [`MihomoError::Network`].
pub async fn fetch(url: String) -> Result<Vec<u8>, MihomoError> {
    let state = state()?;
    let path = path_for(state, &url);

    // Disk lookup. Treat any read error as a miss.
    let cached = read_with_age(&path).await;

    if let Some((bytes, age)) = cached {
        if age >= TTL {
            spawn_refetch(state, url.clone(), path);
        }
        return Ok(bytes);
    }

    // Miss — coalesce concurrent first-time fetches for the same URL so a
    // group's many nodes don't each hit the network.
    let lock = miss_lock_for(state, &url);
    let _guard = lock.lock().await;

    // Another waiter may have populated the cache while we waited.
    if let Some((bytes, _)) = read_with_age(&path).await {
        release_miss_lock(state, &url);
        return Ok(bytes);
    }

    let result = download(&state.client, &url).await;
    if let Ok(bytes) = &result
        && let Err(error) = write_atomic(&path, bytes).await
    {
        // Don't fail the read just because we couldn't persist.
        tracing_warn(&format!("icon cache write failed for {url}: {error}"));
    }
    drop(_guard);
    release_miss_lock(state, &url);
    result
}

fn miss_lock_for(state: &State, url: &str) -> Arc<AsyncMutex<()>> {
    let mut map = state.miss_locks.lock().expect("icon miss_locks poisoned");
    map.entry(url.to_string())
        .or_insert_with(|| Arc::new(AsyncMutex::new(())))
        .clone()
}

fn release_miss_lock(state: &State, url: &str) {
    let mut map = state.miss_locks.lock().expect("icon miss_locks poisoned");
    // Drop the entry only when we hold the last reference besides the map's,
    // so a still-waiting task keeps the same lock instance.
    if let Some(lock) = map.get(url)
        && Arc::strong_count(lock) <= 2
    {
        map.remove(url);
    }
}

async fn read_with_age(path: &Path) -> Option<(Vec<u8>, Duration)> {
    let bytes = fs::read(path).await.ok()?;
    let mtime = fs::metadata(path).await.ok()?.modified().ok()?;
    let age = SystemTime::now()
        .duration_since(mtime)
        .unwrap_or(Duration::ZERO);
    Some((bytes, age))
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

async fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, bytes).await?;
    fs::rename(&tmp, path).await
}

fn spawn_refetch(state: &'static State, url: String, path: PathBuf) {
    let mut inflight = match state.inflight.lock() {
        Ok(g) => g,
        Err(_) => return, // poisoned; treat as full backoff
    };
    if !inflight.insert(url.clone()) {
        return; // already refreshing
    }
    drop(inflight);

    let client = state.client.clone();
    let inflight = &state.inflight;
    tokio::spawn(async move {
        let result = download(&client, &url).await;
        if let Ok(bytes) = result {
            let _ = write_atomic(&path, &bytes).await;
        }
        if let Ok(mut guard) = inflight.lock() {
            guard.remove(&url);
        }
    });
}

fn tracing_warn(msg: &str) {
    // No tracing dep right now; eprintln is enough — this only fires on
    // genuine disk write failures, which a user can spot in logs.
    eprintln!("[icons] {msg}");
}
