//! Routing-rules state with backend-side filtering and on-demand paging.
//!
//! Unlike `/connections`, `/rules` isn't streamed — the ruleset only changes
//! on a config reload. But large rulesets run to thousands of entries, so we
//! keep the parsed list authoritative on the Rust side (one slot for the
//! active target) and let Dart hold only a sliding window:
//!
//! - [`rules_load`] fetches `/rules` once, parses it, applies the filter, and
//!   returns counts.
//! - [`rules_set_filter`] re-filters the cached list without hitting the
//!   backend (cheap per-keystroke).
//! - [`rules_window`] slices the filtered view at `[offset, offset + limit)`.
//! - [`rules_disable`] toggles rules and patches the cache in place.

use std::sync::{Mutex, OnceLock};

use reqwest::Method;
use serde_json::Value;

use crate::MihomoError;

use super::MihomoTarget;

/// One routing rule. `has_extra` is true when the core returned the `extra`
/// block (hit stats + disable support); it gates the per-rule toggle in the UI.
#[derive(Clone, Debug, Default)]
pub struct RuleEntry {
    pub index: u32,
    pub rule_type: String,
    pub payload: String,
    pub proxy: String,
    pub extra_params: Vec<String>,
    pub disabled: bool,
    pub hit_count: u64,
    pub miss_count: u64,
    pub has_extra: bool,
}

/// Counts returned to Dart after a load or filter change. `total` is the full
/// ruleset size; `filtered` is how many survive the current filter.
#[derive(Clone, Debug, Default)]
pub struct RulesSummary {
    pub total: u32,
    pub filtered: u32,
}

struct RulesCache {
    key: String,
    all: Vec<RuleEntry>,
    filter: String,
    /// Indices into `all` that match `filter`, in original order.
    filtered: Vec<u32>,
}

impl RulesCache {
    fn summary(&self) -> RulesSummary {
        RulesSummary {
            total: self.all.len() as u32,
            filtered: self.filtered.len() as u32,
        }
    }

    fn recompute(&mut self) {
        let needle = self.filter.to_lowercase();
        self.filtered = self
            .all
            .iter()
            .enumerate()
            .filter(|(_, e)| rule_matches(e, &needle))
            .map(|(i, _)| i as u32)
            .collect();
    }
}

fn cache() -> &'static Mutex<Option<RulesCache>> {
    static C: OnceLock<Mutex<Option<RulesCache>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(None))
}

fn target_key(target: &MihomoTarget) -> String {
    format!(
        "{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or(""),
    )
}

fn rule_matches(entry: &RuleEntry, needle: &str) -> bool {
    if needle.is_empty() {
        return true;
    }
    entry.payload.to_lowercase().contains(needle)
        || entry.rule_type.to_lowercase().contains(needle)
        || entry.proxy.to_lowercase().contains(needle)
}

/// `GET /rules` — count only. Fetches the ruleset and returns its length
/// without touching the paging cache, so a session-level badge probe can't
/// clobber the rules screen's active filter. Returns 0 on any error.
pub async fn rules_count(target: MihomoTarget) -> u32 {
    let Ok(client) = target.client() else {
        return 0;
    };
    match client.get_json("rules").await {
        Ok(raw) => raw
            .get("rules")
            .and_then(Value::as_array)
            .map(|a| a.len() as u32)
            .unwrap_or(0),
        Err(_) => 0,
    }
}

/// `GET /rules` — fetch the full ruleset, cache it for `target`, apply
/// `filter`, and return counts. Replaces any previously cached ruleset.
pub async fn rules_load(target: MihomoTarget, filter: String) -> Result<RulesSummary, MihomoError> {
    let raw = target.client()?.get_json("rules").await?;
    let mut all = Vec::new();
    if let Some(arr) = raw.get("rules").and_then(Value::as_array) {
        all.reserve(arr.len());
        for item in arr {
            all.push(parse_rule(item));
        }
    }
    let mut cache = RulesCache {
        key: target_key(&target),
        all,
        filter,
        filtered: Vec::new(),
    };
    cache.recompute();
    let summary = cache.summary();
    *self::cache().lock().expect("rules cache poisoned") = Some(cache);
    Ok(summary)
}

/// Re-filter the cached ruleset for `target` without re-fetching. Returns the
/// updated counts, or zeros if no ruleset is cached for this target.
pub async fn rules_set_filter(target: MihomoTarget, filter: String) -> RulesSummary {
    let key = target_key(&target);
    let mut guard = cache().lock().expect("rules cache poisoned");
    match guard.as_mut() {
        Some(c) if c.key == key => {
            c.filter = filter;
            c.recompute();
            c.summary()
        }
        _ => RulesSummary::default(),
    }
}

/// Slice the filtered view at `[offset, offset + limit)`. Bounds-checked;
/// returns fewer than `limit` near the tail, or empty if no matching cache.
pub async fn rules_window(target: MihomoTarget, offset: u32, limit: u32) -> Vec<RuleEntry> {
    let key = target_key(&target);
    let guard = cache().lock().expect("rules cache poisoned");
    let Some(c) = guard.as_ref().filter(|c| c.key == key) else {
        return Vec::new();
    };
    let start = (offset as usize).min(c.filtered.len());
    let end = start.saturating_add(limit as usize).min(c.filtered.len());
    c.filtered[start..end]
        .iter()
        .filter_map(|&i| c.all.get(i as usize).cloned())
        .collect()
}

/// `PATCH /rules/disable` — toggle rules by index. Body is `{<index>: bool}`.
/// On success the cache is patched so the next window reflects the change
/// without a reload. mihomo rejects this under `--embed`; treat 404 as a
/// feature gate, not a bug.
pub async fn rules_disable(
    target: MihomoTarget,
    index: u32,
    disabled: bool,
) -> Result<(), MihomoError> {
    let body = serde_json::json!({ index.to_string(): disabled });
    target
        .client()?
        .forward(Method::PATCH, "rules/disable", Some(body.clone()))
        .await?;

    // Rule index == position in the slice (mihomo enumerates in order), so
    // we can patch the cached entry directly.
    if let Some(obj) = body.as_object() {
        let key = target_key(&target);
        let mut guard = cache().lock().expect("rules cache poisoned");
        if let Some(c) = guard.as_mut().filter(|c| c.key == key) {
            for (idx, disabled) in obj {
                if let (Ok(i), Some(d)) = (idx.parse::<usize>(), disabled.as_bool())
                    && let Some(entry) = c.all.get_mut(i)
                {
                    entry.disabled = d;
                }
            }
        }
    }
    Ok(())
}

fn parse_rule(item: &Value) -> RuleEntry {
    let extra = item.get("extra").filter(|v| v.is_object());
    let has_extra = extra.is_some();
    let extra_field = |key: &str| extra.and_then(|e| e.get(key));
    RuleEntry {
        index: item.get("index").and_then(Value::as_u64).unwrap_or(0) as u32,
        rule_type: take_str(item, "type"),
        payload: take_str(item, "payload"),
        proxy: take_str(item, "proxy"),
        extra_params: Vec::new(),
        disabled: extra_field("disabled")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        hit_count: extra_field("hitCount").and_then(Value::as_u64).unwrap_or(0),
        miss_count: extra_field("missCount")
            .and_then(Value::as_u64)
            .unwrap_or(0),
        has_extra,
    }
}

fn take_str(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}
