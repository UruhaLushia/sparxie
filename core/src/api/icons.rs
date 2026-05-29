//! Icon caches exposed to Dart.
//!
//! - `*_icon_cache` / `fetch_icon`: remote proxy-group icon URLs.
//! - `*_process_icon*` / `*_process_name*`: local-process icons and names
//!   (only meaningful when the backend runs on this machine).
//!
//! Seeded once at startup with the platform's cache directory.

use crate::error::MihomoError;
use crate::{icons, process_icons};

pub fn init_icon_cache(cache_dir: String) -> Result<(), MihomoError> {
    icons::init(std::path::PathBuf::from(cache_dir))
}

pub async fn fetch_icon(url: String) -> Result<Vec<u8>, MihomoError> {
    icons::fetch(url).await
}

pub fn init_process_icon_cache(cache_dir: String) -> Result<(), MihomoError> {
    process_icons::init(std::path::PathBuf::from(cache_dir))
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
    process_icons::clear_negative();
}
