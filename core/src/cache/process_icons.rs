//! Local-process icon + name cache. Desktop resolves via `file-icon`;
//! Android resolves through its PackageManager (Kotlin) and persists the
//! result here via [`store`] / [`store_name`]. iOS skips process metadata.
//!
//! Bytes and names live in the shared redb database ([`crate::cache::db`]).

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use tokio::sync::Semaphore;

use crate::MihomoError;
use crate::cache::db::{self, PROC_ICONS};
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
use crate::utils::image::normalize_desktop_icon;

/// Bounds concurrent resolves so a burst of new connections doesn't spawn
/// dozens of parallel desktop-file scans. Mirrors Sparkle's cap.
const MAX_CONCURRENT: usize = 5;
const DEFAULT_ICON_SIZE: u32 = 256;
const MAX_MEMOIZED_KEYS: usize = 512;

/// Process icons can change when apps update; keep the disk cache fresh while
/// still avoiding repeated file-icon extraction during normal use.
const ICON_TTL: Duration = Duration::from_secs(24 * 60 * 60);

struct State {
    sem: Semaphore,
    /// Keys known to have no resolvable icon — avoids rescanning the
    /// filesystem every frame for the same misses.
    negative: Mutex<HashSet<String>>,
    /// Keys mid-resolve, so concurrent callers share one resolve.
    inflight: Mutex<HashSet<String>>,
    names: Mutex<HashMap<String, Option<String>>>,
}

static STATE: OnceLock<State> = OnceLock::new();

/// Initialize the in-memory resolve state. The shared cache DB is opened
/// separately via [`db::init`]. Idempotent.
pub fn init() -> Result<(), MihomoError> {
    let _ = STATE.set(State {
        sem: Semaphore::new(MAX_CONCURRENT),
        negative: Mutex::new(HashSet::new()),
        inflight: Mutex::new(HashSet::new()),
        names: Mutex::new(HashMap::new()),
    });
    Ok(())
}

fn state() -> Result<&'static State, MihomoError> {
    STATE
        .get()
        .ok_or_else(|| MihomoError::Other("process-icon cache not initialized".into()))
}

fn icon_key(key: &str) -> String {
    blake3::hash(key.as_bytes()).to_hex().to_string()
}

fn sized_icon_key(key: &str, size: u32) -> String {
    format!("{}@{}", key, icon_size(size))
}

fn icon_size(size: u32) -> u32 {
    size.clamp(1, DEFAULT_ICON_SIZE)
}

fn cache_name(names: &mut HashMap<String, Option<String>>, key: String, value: Option<String>) {
    if names.len() >= MAX_MEMOIZED_KEYS
        && !names.contains_key(&key)
        && let Some(evicted) = names.keys().next().cloned()
    {
        names.remove(&evicted);
    }
    names.insert(key, value);
}

fn remember_negative(negative: &mut HashSet<String>, key: String) {
    if negative.len() >= MAX_MEMOIZED_KEYS
        && !negative.contains(&key)
        && let Some(evicted) = negative.iter().next().cloned()
    {
        negative.remove(&evicted);
    }
    negative.insert(key);
}

async fn db_get_icon(key: String) -> Result<Option<Vec<u8>>, MihomoError> {
    tokio::task::spawn_blocking(move || {
        let now = db::now_secs();
        let value = db::get_bytes(PROC_ICONS, &icon_key(&key))?;
        Ok(value.and_then(|raw| {
            let (created, bytes) = db::unstamp(&raw)?;
            (created <= now && Duration::from_secs(now - created) < ICON_TTL)
                .then(|| bytes.to_vec())
        }))
    })
    .await
    .map_err(|e| MihomoError::Other(format!("proc-icon join: {e}")))?
}

async fn db_put_icon(key: String, bytes: Vec<u8>) -> Result<(), MihomoError> {
    tokio::task::spawn_blocking(move || {
        let value = db::stamp(db::now_secs(), &bytes);
        db::put_bytes(PROC_ICONS, &icon_key(&key), &value)
    })
    .await
    .map_err(|e| MihomoError::Other(format!("proc-icon join: {e}")))?
}

async fn db_get_name(key: String) -> Result<Option<String>, MihomoError> {
    tokio::task::spawn_blocking(move || db::get_str(&icon_key(&key)))
        .await
        .map_err(|e| MihomoError::Other(format!("proc-name join: {e}")))?
}

async fn db_put_name(key: String, value: String) -> Result<(), MihomoError> {
    tokio::task::spawn_blocking(move || db::put_str(&icon_key(&key), &value))
        .await
        .map_err(|e| MihomoError::Other(format!("proc-name join: {e}")))?
}

/// Disk-only icon lookup; `None` on a miss without resolving.
pub async fn cached(key: String) -> Result<Option<Vec<u8>>, MihomoError> {
    if key.is_empty() {
        return Ok(None);
    }
    db_get_icon(key).await
}

/// Disk-only sized icon lookup; `None` on a miss without resolving.
pub async fn cached_sized(key: String, size: u32) -> Result<Option<Vec<u8>>, MihomoError> {
    if key.is_empty() {
        return Ok(None);
    }
    db_get_icon(sized_icon_key(&key, size)).await
}

/// Persist icon `bytes` resolved outside Rust (Android) into the shared cache.
pub async fn store(key: String, bytes: Vec<u8>) -> Result<(), MihomoError> {
    if key.is_empty() || bytes.is_empty() {
        return Ok(());
    }
    db_put_icon(key, bytes).await
}

/// Resolve `process_path` to its application name, memoized in memory and in
/// the cache DB. `None` means no better name than the caller's fallback.
pub async fn name(process_path: String) -> Result<Option<String>, MihomoError> {
    let state = state()?;
    if process_path.is_empty() {
        return Ok(None);
    }
    if let Ok(names) = state.names.lock()
        && let Some(cached) = names.get(&process_path)
    {
        return Ok(cached.clone());
    }

    // A stored entry is authoritative, even when empty (= resolved, no name).
    if let Some(text) = db_get_name(process_path.clone()).await? {
        let resolved = if text.is_empty() { None } else { Some(text) };
        if let Ok(mut names) = state.names.lock() {
            cache_name(&mut names, process_path, resolved.clone());
        }
        return Ok(resolved);
    }

    let _permit = state
        .sem
        .acquire()
        .await
        .map_err(|e| MihomoError::Other(format!("process-icon semaphore closed: {e}")))?;
    let path = process_path.clone();
    let resolved = tokio::task::spawn_blocking(move || resolve_app_name(&path))
        .await
        .map_err(|e| MihomoError::Other(format!("process-name join: {e}")))?;

    let _ = db_put_name(process_path.clone(), resolved.clone().unwrap_or_default()).await;
    if let Ok(mut names) = state.names.lock() {
        cache_name(&mut names, process_path, resolved.clone());
    }
    Ok(resolved)
}

/// Disk-only name lookup; `None` on a miss or a cached "no name" (Android).
pub async fn cached_name(key: String) -> Result<Option<String>, MihomoError> {
    if key.is_empty() {
        return Ok(None);
    }
    Ok(db_get_name(key).await?.filter(|s| !s.is_empty()))
}

/// Persist an app `name` resolved outside Rust (Android) into the shared cache.
pub async fn store_name(key: String, name: String) -> Result<(), MihomoError> {
    if key.is_empty() {
        return Ok(());
    }
    db_put_name(key, name).await
}

/// Resolve `process_path` to icon bytes: cache hit, then negative cache, then
/// a deduped resolve on the blocking pool.
pub async fn fetch(process_path: String) -> Result<Option<Vec<u8>>, MihomoError> {
    fetch_sized(process_path, DEFAULT_ICON_SIZE).await
}

/// Resolve `process_path` to icon bytes at the exact display pixel size.
pub async fn fetch_sized(process_path: String, size: u32) -> Result<Option<Vec<u8>>, MihomoError> {
    let state = state()?;
    if process_path.is_empty() {
        return Ok(None);
    }
    let size = icon_size(size);
    let cache_key = sized_icon_key(&process_path, size);

    if let Some(bytes) = db_get_icon(cache_key.clone()).await? {
        return Ok(Some(bytes));
    }
    if state
        .negative
        .lock()
        .map(|set| set.contains(&process_path))
        .unwrap_or(false)
    {
        return Ok(None);
    }

    {
        let mut inflight = state.inflight.lock().map_err(poisoned)?;
        if !inflight.insert(process_path.clone()) {
            // Another task is resolving; retry on a later frame, don't block.
            return Ok(None);
        }
    }

    let result = resolve(state, process_path.clone(), size, cache_key).await;

    if let Ok(mut inflight) = state.inflight.lock() {
        inflight.remove(&process_path);
    }
    result
}

async fn resolve(
    state: &'static State,
    process_path: String,
    size: u32,
    cache_key: String,
) -> Result<Option<Vec<u8>>, MihomoError> {
    let _permit = state
        .sem
        .acquire()
        .await
        .map_err(|e| MihomoError::Other(format!("process-icon semaphore closed: {e}")))?;

    let path = process_path.clone();
    let icon = tokio::task::spawn_blocking(move || resolve_icon_bytes_sized(&path, size))
        .await
        .map_err(|e| MihomoError::Other(format!("process-icon join: {e}")))?;

    match icon {
        Some(bytes) if !bytes.is_empty() => {
            let _ = db_put_icon(cache_key, bytes.clone()).await;
            Ok(Some(bytes))
        }
        _ => {
            if let Ok(mut neg) = state.negative.lock() {
                remember_negative(&mut neg, process_path);
            }
            Ok(None)
        }
    }
}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn resolve_icon_bytes_sized(path: &str, size: u32) -> Option<Vec<u8>> {
    // No explicit size — `file-icon` already returns a large/native icon by
    // default. Normalize before caching, matching Sparkle's renderer-side
    // `cropAndPadTransparent` without repeating that work in Flutter.
    let bytes = file_icon::file_to_buf(path).ok()?;
    normalize_desktop_icon(&bytes, size).or(Some(bytes))
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
fn resolve_icon_bytes_sized(_path: &str, _size: u32) -> Option<Vec<u8>> {
    None
}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn resolve_app_name(path: &str) -> Option<String> {
    file_icon::get_app_name_with_options(path, file_icon::FileIconOptions::default())
        .ok()
        .filter(|name| !name.is_empty())
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
fn resolve_app_name(_path: &str) -> Option<String> {
    None
}

fn poisoned<T>(_: std::sync::PoisonError<T>) -> MihomoError {
    MihomoError::Other("process-icon cache lock poisoned".into())
}

/// Forget in-memory negative + name memo so previously-unresolved keys retry
/// and cleared DB entries aren't masked by stale memory.
pub fn clear_memory() {
    if let Some(state) = STATE.get() {
        if let Ok(mut neg) = state.negative.lock() {
            neg.clear();
            neg.shrink_to_fit();
        }
        if let Ok(mut names) = state.names.lock() {
            names.clear();
            names.shrink_to_fit();
        }
    }
}
