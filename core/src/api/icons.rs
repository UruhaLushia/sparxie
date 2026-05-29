//! Icon caches exposed to Dart.
//!
//! All three caches — remote proxy-group icons, local-process icons, and
//! process names — live in one shared redb database ([`crate::cache_db`]).
//! `init_cache` opens it; the per-subsystem inits set up in-memory state.

use crate::error::MihomoError;
use crate::{cache_db, icons, process_icons};

/// Open the shared cache database and initialize both icon subsystems.
/// Idempotent; the path is fixed on first call.
pub fn init_cache(cache_dir: String) -> Result<(), MihomoError> {
    cache_db::init(std::path::PathBuf::from(cache_dir))?;
    icons::init()?;
    process_icons::init()
}

pub async fn fetch_icon(url: String) -> Result<Vec<u8>, MihomoError> {
    icons::fetch(url).await
}

pub async fn fetch_process_icon(path: String) -> Result<Option<Vec<u8>>, MihomoError> {
    process_icons::fetch(path).await
}

pub async fn cached_process_icon(key: String) -> Result<Option<Vec<u8>>, MihomoError> {
    process_icons::cached(key).await
}

pub async fn store_process_icon(key: String, bytes: Vec<u8>) -> Result<(), MihomoError> {
    process_icons::store(key, bytes).await
}

pub async fn fetch_process_name(path: String) -> Result<Option<String>, MihomoError> {
    process_icons::name(path).await
}

pub async fn cached_process_name(key: String) -> Result<Option<String>, MihomoError> {
    process_icons::cached_name(key).await
}

pub async fn store_process_name(key: String, name: String) -> Result<(), MihomoError> {
    process_icons::store_name(key, name).await
}

pub fn reset_process_icon_misses() {
    process_icons::clear_memory();
}

/// Total size of the on-disk cache in bytes (keys + values across tables).
pub async fn icon_cache_size() -> Result<u64, MihomoError> {
    tokio::task::spawn_blocking(cache_db::total_size)
        .await
        .map_err(|e| MihomoError::Other(format!("cache size join: {e}")))?
}

/// Wipe every cached icon and name, then drop the in-memory resolve state so
/// fresh lookups don't surface stale negatives.
pub async fn clear_icon_cache() -> Result<(), MihomoError> {
    tokio::task::spawn_blocking(cache_db::clear_all)
        .await
        .map_err(|e| MihomoError::Other(format!("cache clear join: {e}")))??;
    process_icons::clear_memory();
    Ok(())
}
