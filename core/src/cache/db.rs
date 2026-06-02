//! Shared on-disk cache backed by a single redb database.
//!
//! Three tables live in `<cache_dir>/cache.redb`:
//! - `icons`: blake3(url) → `[8-byte unix-secs created][image bytes]` for
//!   remote proxy-group icons (the timestamp drives stale-while-revalidate).
//! - `proc_icons`: process key → raw icon bytes.
//! - `proc_names`: process key → app name (empty value = resolved-no-name).
//!
//! redb is pure-Rust and synchronous, so every call hops to the blocking
//! pool. The database is opened once and shared for the process lifetime.

use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use redb::{Database, ReadableTable, TableDefinition};

use crate::MihomoError;

pub const ICONS: TableDefinition<'_, &str, &[u8]> = TableDefinition::new("icons");
pub const PROC_ICONS: TableDefinition<'_, &str, &[u8]> = TableDefinition::new("proc_icons");
pub const PROC_NAMES: TableDefinition<'_, &str, &str> = TableDefinition::new("proc_names");

static DB: OnceLock<Database> = OnceLock::new();

/// Open the shared database under `cache_dir`. Idempotent — the first
/// successful call wins and the path is fixed for the process lifetime.
pub fn init(cache_dir: PathBuf) -> Result<(), MihomoError> {
    if DB.get().is_some() {
        return Ok(());
    }
    std::fs::create_dir_all(&cache_dir).map_err(|e| {
        MihomoError::Other(format!("create cache dir {}: {e}", cache_dir.display()))
    })?;
    let db = Database::create(cache_dir.join("cache.redb"))
        .map_err(|e| MihomoError::Other(format!("open cache db: {e}")))?;
    // Ensure tables exist so reads before any write don't error.
    let txn = db
        .begin_write()
        .map_err(|e| MihomoError::Other(format!("cache db txn: {e}")))?;
    {
        txn.open_table(ICONS)
            .and(txn.open_table(PROC_ICONS))
            .map_err(|e| MihomoError::Other(format!("cache db table: {e}")))?;
        txn.open_table(PROC_NAMES)
            .map_err(|e| MihomoError::Other(format!("cache db table: {e}")))?;
    }
    txn.commit()
        .map_err(|e| MihomoError::Other(format!("cache db commit: {e}")))?;
    let _ = DB.set(db);
    Ok(())
}

fn db() -> Result<&'static Database, MihomoError> {
    DB.get()
        .ok_or_else(|| MihomoError::Other("cache db not initialized".into()))
}

pub fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Fetch raw bytes from a blob table.
pub fn get_bytes(
    table: TableDefinition<'static, &'static str, &'static [u8]>,
    key: &str,
) -> Result<Option<Vec<u8>>, MihomoError> {
    let db = db()?;
    let txn = db
        .begin_read()
        .map_err(|e| MihomoError::Other(format!("cache read txn: {e}")))?;
    let table = match txn.open_table(table) {
        Ok(t) => t,
        Err(redb::TableError::TableDoesNotExist(_)) => return Ok(None),
        Err(e) => return Err(MihomoError::Other(format!("cache open: {e}"))),
    };
    let value = table
        .get(key)
        .map_err(|e| MihomoError::Other(format!("cache get: {e}")))?;
    Ok(value.map(|v| v.value().to_vec()))
}

pub fn put_bytes(
    table: TableDefinition<'static, &'static str, &'static [u8]>,
    key: &str,
    value: &[u8],
) -> Result<(), MihomoError> {
    let db = db()?;
    let txn = db
        .begin_write()
        .map_err(|e| MihomoError::Other(format!("cache write txn: {e}")))?;
    {
        let mut table = txn
            .open_table(table)
            .map_err(|e| MihomoError::Other(format!("cache open: {e}")))?;
        table
            .insert(key, value)
            .map_err(|e| MihomoError::Other(format!("cache insert: {e}")))?;
    }
    txn.commit()
        .map_err(|e| MihomoError::Other(format!("cache commit: {e}")))?;
    Ok(())
}

pub fn get_str(key: &str) -> Result<Option<String>, MihomoError> {
    let db = db()?;
    let txn = db
        .begin_read()
        .map_err(|e| MihomoError::Other(format!("cache read txn: {e}")))?;
    let table = match txn.open_table(PROC_NAMES) {
        Ok(t) => t,
        Err(redb::TableError::TableDoesNotExist(_)) => return Ok(None),
        Err(e) => return Err(MihomoError::Other(format!("cache open: {e}"))),
    };
    let value = table
        .get(key)
        .map_err(|e| MihomoError::Other(format!("cache get: {e}")))?;
    Ok(value.map(|v| v.value().to_string()))
}

pub fn put_str(key: &str, value: &str) -> Result<(), MihomoError> {
    let db = db()?;
    let txn = db
        .begin_write()
        .map_err(|e| MihomoError::Other(format!("cache write txn: {e}")))?;
    {
        let mut table = txn
            .open_table(PROC_NAMES)
            .map_err(|e| MihomoError::Other(format!("cache open: {e}")))?;
        table
            .insert(key, value)
            .map_err(|e| MihomoError::Other(format!("cache insert: {e}")))?;
    }
    txn.commit()
        .map_err(|e| MihomoError::Other(format!("cache commit: {e}")))?;
    Ok(())
}

/// Total bytes stored across all tables (keys + values), best effort.
pub fn total_size() -> Result<u64, MihomoError> {
    let db = db()?;
    let txn = db
        .begin_read()
        .map_err(|e| MihomoError::Other(format!("cache read txn: {e}")))?;
    let mut total: u64 = 0;
    for blob in [ICONS, PROC_ICONS] {
        if let Ok(table) = txn.open_table(blob) {
            for entry in table.iter().into_iter().flatten().flatten() {
                let (k, v) = entry;
                total += k.value().len() as u64 + v.value().len() as u64;
            }
        }
    }
    if let Ok(table) = txn.open_table(PROC_NAMES) {
        for entry in table.iter().into_iter().flatten().flatten() {
            let (k, v) = entry;
            total += k.value().len() as u64 + v.value().len() as u64;
        }
    }
    Ok(total)
}

/// Drop every cached entry across all tables.
pub fn clear_all() -> Result<(), MihomoError> {
    let db = db()?;
    let txn = db
        .begin_write()
        .map_err(|e| MihomoError::Other(format!("cache write txn: {e}")))?;
    {
        // Re-creating each table by opening and draining keeps it simple and
        // avoids leaving the file without the tables our reads expect.
        let mut icons = txn
            .open_table(ICONS)
            .map_err(|e| MihomoError::Other(format!("cache open: {e}")))?;
        icons
            .retain(|_, _| false)
            .map_err(|e| MihomoError::Other(format!("cache clear: {e}")))?;
        let mut pi = txn
            .open_table(PROC_ICONS)
            .map_err(|e| MihomoError::Other(format!("cache open: {e}")))?;
        pi.retain(|_, _| false)
            .map_err(|e| MihomoError::Other(format!("cache clear: {e}")))?;
        let mut pn = txn
            .open_table(PROC_NAMES)
            .map_err(|e| MihomoError::Other(format!("cache open: {e}")))?;
        pn.retain(|_, _| false)
            .map_err(|e| MihomoError::Other(format!("cache clear: {e}")))?;
    }
    txn.commit()
        .map_err(|e| MihomoError::Other(format!("cache commit: {e}")))?;
    Ok(())
}

/// Encode `created_secs` as an 8-byte big-endian prefix on `bytes`.
pub fn stamp(created_secs: u64, bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + bytes.len());
    out.extend_from_slice(&created_secs.to_be_bytes());
    out.extend_from_slice(bytes);
    out
}

/// Split a stamped value into `(created_secs, bytes)`; `None` if malformed.
pub fn unstamp(value: &[u8]) -> Option<(u64, &[u8])> {
    if value.len() < 8 {
        return None;
    }
    let (head, rest) = value.split_at(8);
    let secs = u64::from_be_bytes(head.try_into().ok()?);
    Some((secs, rest))
}

pub fn age(created_secs: u64) -> Duration {
    Duration::from_secs(now_secs().saturating_sub(created_secs))
}
