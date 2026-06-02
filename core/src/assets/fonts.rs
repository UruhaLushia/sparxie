//! System UI-font enumeration for the desktop font picker.
//!
//! Pure-Rust `fontdb` scans the platform's font directories (no FreeType /
//! Fontconfig C deps), so this cross-compiles cleanly on desktop and is
//! excluded from mobile builds entirely.

/// Distinct installed font family names, sorted. Empty on mobile.
pub fn list_families() -> Vec<String> {
    families()
}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn families() -> Vec<String> {
    use std::collections::BTreeSet;

    let mut db = fontdb::Database::new();
    db.load_system_fonts();

    let mut names: BTreeSet<String> = BTreeSet::new();
    for face in db.faces() {
        // `families` is a list of (name, language); take the first, which is
        // the font's primary/typographic family name.
        if let Some((name, _)) = face.families.first() {
            let trimmed = name.trim();
            // Skip icon/symbol pseudo-fonts that aren't useful for UI text.
            if !trimmed.is_empty() {
                names.insert(trimmed.to_string());
            }
        }
    }
    names.into_iter().collect()
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
fn families() -> Vec<String> {
    Vec::new()
}
