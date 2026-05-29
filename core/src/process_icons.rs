//! Local-process icon + name cache. Desktop resolves via `file-icon`;
//! Android resolves through its PackageManager (Kotlin) and persists the
//! result here via [`store`] / [`store_name`], so the .so omits `file-icon`.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use tokio::sync::Semaphore;

use crate::error::MihomoError;

/// Bounds concurrent resolves so a burst of new connections doesn't spawn
/// dozens of parallel desktop-file scans. Mirrors Sparkle's cap.
const MAX_CONCURRENT: usize = 5;

#[cfg(not(target_os = "android"))]
const ICON_SIZE: u32 = 64;

struct State {
    dir: PathBuf,
    sem: Semaphore,
    /// Keys known to have no resolvable icon — avoids rescanning the
    /// filesystem every frame for the same misses.
    negative: Mutex<HashSet<String>>,
    /// Keys mid-resolve, so concurrent callers share one resolve.
    inflight: Mutex<HashSet<String>>,
    names: Mutex<HashMap<String, Option<String>>>,
}

static STATE: OnceLock<State> = OnceLock::new();

pub fn init(cache_dir: PathBuf) -> Result<(), MihomoError> {
    let dir = cache_dir.join("proc-icons");
    if let Err(error) = std::fs::create_dir_all(&dir) {
        return Err(MihomoError::Other(format!(
            "failed to create process-icon cache dir {}: {error}",
            dir.display()
        )));
    }
    let _ = STATE.set(State {
        dir,
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

fn path_for(state: &State, key: &str) -> PathBuf {
    let hash = blake3::hash(key.as_bytes());
    state.dir.join(format!("{}.png", hash.to_hex()))
}

fn name_path_for(state: &State, key: &str) -> PathBuf {
    let hash = blake3::hash(key.as_bytes());
    state.dir.join(format!("{}.name", hash.to_hex()))
}

/// Disk-only icon lookup; `None` on a miss without resolving.
pub async fn cached(key: String) -> Result<Option<Vec<u8>>, MihomoError> {
    let state = state()?;
    if key.is_empty() {
        return Ok(None);
    }
    Ok(tokio::fs::read(path_for(state, &key)).await.ok())
}

/// Persist icon `bytes` resolved outside Rust (Android) into the shared cache.
pub async fn store(key: String, bytes: Vec<u8>) -> Result<(), MihomoError> {
    let state = state()?;
    if key.is_empty() || bytes.is_empty() {
        return Ok(());
    }
    let _ = write_atomic(&path_for(state, &key), &bytes).await;
    Ok(())
}

/// Resolve `process_path` to its application name, memoized in memory and on
/// disk. `None` means no better name than the caller's fallback was found.
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

    // An existing `.name` file is authoritative, even when empty (= no name).
    let name_path = name_path_for(state, &process_path);
    if let Ok(text) = tokio::fs::read_to_string(&name_path).await {
        let resolved = if text.is_empty() { None } else { Some(text) };
        if let Ok(mut names) = state.names.lock() {
            names.insert(process_path, resolved.clone());
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

    let _ = write_atomic(&name_path, resolved.as_deref().unwrap_or("").as_bytes()).await;
    if let Ok(mut names) = state.names.lock() {
        names.insert(process_path, resolved.clone());
    }
    Ok(resolved)
}

/// Disk-only name lookup; `None` on a miss or a cached "no name" (Android).
pub async fn cached_name(key: String) -> Result<Option<String>, MihomoError> {
    let state = state()?;
    if key.is_empty() {
        return Ok(None);
    }
    match tokio::fs::read_to_string(name_path_for(state, &key)).await {
        Ok(text) if !text.is_empty() => Ok(Some(text)),
        _ => Ok(None),
    }
}

/// Persist an app `name` resolved outside Rust (Android) into the shared cache.
pub async fn store_name(key: String, name: String) -> Result<(), MihomoError> {
    let state = state()?;
    if key.is_empty() {
        return Ok(());
    }
    let _ = write_atomic(&name_path_for(state, &key), name.as_bytes()).await;
    Ok(())
}

/// Resolve `process_path` to icon bytes: disk hit, then negative cache, then
/// a deduped resolve on the blocking pool.
pub async fn fetch(process_path: String) -> Result<Option<Vec<u8>>, MihomoError> {
    let state = state()?;
    if process_path.is_empty() {
        return Ok(None);
    }

    let cache_path = path_for(state, &process_path);
    if let Ok(bytes) = tokio::fs::read(&cache_path).await {
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

    let result = resolve(state, &process_path, &cache_path).await;

    if let Ok(mut inflight) = state.inflight.lock() {
        inflight.remove(&process_path);
    }
    result
}

async fn resolve(
    state: &'static State,
    process_path: &str,
    cache_path: &Path,
) -> Result<Option<Vec<u8>>, MihomoError> {
    let _permit = state
        .sem
        .acquire()
        .await
        .map_err(|e| MihomoError::Other(format!("process-icon semaphore closed: {e}")))?;

    let path = process_path.to_string();
    let icon = tokio::task::spawn_blocking(move || resolve_icon_bytes(&path))
        .await
        .map_err(|e| MihomoError::Other(format!("process-icon join: {e}")))?;

    match icon {
        Some(bytes) if !bytes.is_empty() => {
            let _ = write_atomic(cache_path, &bytes).await;
            Ok(Some(bytes))
        }
        _ => {
            if let Ok(mut neg) = state.negative.lock() {
                neg.insert(process_path.to_string());
            }
            Ok(None)
        }
    }
}

#[cfg(not(target_os = "android"))]
fn resolve_icon_bytes(path: &str) -> Option<Vec<u8>> {
    let options = file_icon::FileIconOptions {
        size: Some(ICON_SIZE),
        ..Default::default()
    };
    file_icon::file_to_buf_with_options(path, options).ok()
}

// Android resolves icons via PackageManager, so `file-icon` is absent here.
#[cfg(target_os = "android")]
fn resolve_icon_bytes(_path: &str) -> Option<Vec<u8>> {
    None
}

#[cfg(not(target_os = "android"))]
fn resolve_app_name(path: &str) -> Option<String> {
    file_icon::get_app_name_with_options(path, file_icon::FileIconOptions::default())
        .ok()
        .filter(|name| !name.is_empty())
}

#[cfg(target_os = "android")]
fn resolve_app_name(_path: &str) -> Option<String> {
    None
}

async fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    tokio::fs::write(&tmp, bytes).await?;
    tokio::fs::rename(&tmp, path).await
}

fn poisoned<T>(_: std::sync::PoisonError<T>) -> MihomoError {
    MihomoError::Other("process-icon cache lock poisoned".into())
}

/// Forget negative-cache entries so previously-unresolved keys retry.
pub fn clear_negative() {
    if let Some(state) = STATE.get()
        && let Ok(mut neg) = state.negative.lock()
    {
        neg.clear();
    }
}
