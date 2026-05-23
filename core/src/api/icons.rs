//! Icon cache exposed to Dart.
//!
//! Dart calls [`init_icon_cache`] once at app startup with the platform's
//! cache directory (`getApplicationCacheDirectory()`); afterwards it can
//! call [`fetch_icon`] for every proxy-group icon URL. The first call per
//! URL hits the network; subsequent calls (within or across app launches)
//! return whatever's on disk and the cache refreshes in the background
//! once an entry is more than a day old.

use crate::error::MihomoError;
use crate::icons;

/// Configure where icon bytes are persisted. Idempotent; the path is
/// captured on the first successful call and reused for the process
/// lifetime.
pub fn init_icon_cache(cache_dir: String) -> Result<(), MihomoError> {
    icons::init(std::path::PathBuf::from(cache_dir))
}

/// Resolve [`url`] to icon bytes. See [`icons::fetch`] for cache semantics.
pub async fn fetch_icon(url: String) -> Result<Vec<u8>, MihomoError> {
    icons::fetch(url).await
}
