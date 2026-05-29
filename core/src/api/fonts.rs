//! Font enumeration exposed to Dart.

use crate::fonts;

/// Distinct installed UI font family names, sorted. Empty on Android (which
/// uses the system font). Runs on the blocking pool — scanning the font
/// directories touches the filesystem.
pub async fn system_font_families() -> Vec<String> {
    tokio::task::spawn_blocking(fonts::list_families)
        .await
        .unwrap_or_default()
}
