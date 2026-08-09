use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use flutter_rust_bridge::frb;

use crate::MihomoError;
use crate::cache::target::ActiveTargetCache;
use crate::utils::text::contains_filter;

use super::{BackendTarget, BackendType, RuleEntry, RulesSummary};

struct RulesCache {
    all: Vec<CachedRuleEntry>,
    strings: Vec<Box<str>>,
    filter: String,
    // The common unfiltered view maps directly to `all`, avoiding one index
    // allocation per rule while the page is closed.
    filtered: Option<Vec<u32>>,
}

struct CachedRuleEntry {
    index: u32,
    rule_type: u32,
    payload: Box<str>,
    proxy: u32,
    extra_params: Box<[u32]>,
    disabled: bool,
    hit_count: u64,
    hit_at: Option<Box<str>>,
    miss_count: u64,
    miss_at: Option<Box<str>>,
    has_extra: bool,
}

impl RulesCache {
    fn new(all: Vec<RuleEntry>) -> Self {
        let mut interner = RuleStringInterner::default();
        let all = all
            .into_iter()
            .map(|entry| CachedRuleEntry::new(entry, &mut interner))
            .collect();
        Self {
            all,
            strings: interner.values,
            filter: String::new(),
            filtered: None,
        }
    }

    fn apply(&mut self, all: Vec<RuleEntry>) {
        let same_shape = self.all.len() == all.len()
            && self
                .all
                .iter()
                .zip(&all)
                .all(|(cached, fresh)| cached.same_shape(fresh, &self.strings));
        if same_shape {
            for (cached, fresh) in self.all.iter_mut().zip(all) {
                cached.apply_runtime(fresh);
            }
            return;
        }
        let filter = std::mem::take(&mut self.filter);
        *self = Self::new(all);
        self.set_filter(filter);
    }

    fn set_filter(&mut self, filter: String) {
        if self.filter == filter {
            return;
        }
        self.filter = filter;
        if self.filter.is_empty() {
            self.filtered = None;
            return;
        }
        let needle = self.filter.to_lowercase();
        self.filtered = Some(
            self.all
                .iter()
                .enumerate()
                .filter(|(_, entry)| rule_matches(entry, &self.strings, &needle))
                .map(|(index, _)| index as u32)
                .collect(),
        );
    }

    fn filtered_len(&self) -> usize {
        self.filtered.as_ref().map_or(self.all.len(), Vec::len)
    }

    fn summary(&self) -> RulesSummary {
        RulesSummary {
            total: self.all.len().min(u32::MAX as usize) as u32,
            filtered: self.filtered_len().min(u32::MAX as usize) as u32,
        }
    }

    fn entry(&self, index: usize) -> Option<RuleEntry> {
        self.all
            .get(index)
            .map(|entry| entry.to_entry(&self.strings))
    }
}

#[derive(Default)]
#[frb(ignore)]
struct RuleStringInterner {
    ids: HashMap<String, u32>,
    values: Vec<Box<str>>,
}

impl RuleStringInterner {
    fn intern(&mut self, value: String) -> u32 {
        if let Some(id) = self.ids.get(value.as_str()) {
            return *id;
        }
        let id = self.values.len().min(u32::MAX as usize) as u32;
        self.values.push(value.clone().into_boxed_str());
        self.ids.insert(value, id);
        id
    }
}

impl CachedRuleEntry {
    fn new(entry: RuleEntry, interner: &mut RuleStringInterner) -> Self {
        Self {
            index: entry.index,
            rule_type: interner.intern(entry.rule_type),
            payload: entry.payload.into_boxed_str(),
            proxy: interner.intern(entry.proxy),
            extra_params: entry
                .extra_params
                .into_iter()
                .map(|param| interner.intern(param))
                .collect::<Vec<_>>()
                .into_boxed_slice(),
            disabled: entry.disabled,
            hit_count: entry.hit_count,
            hit_at: boxed_non_empty(entry.hit_at),
            miss_count: entry.miss_count,
            miss_at: boxed_non_empty(entry.miss_at),
            has_extra: entry.has_extra,
        }
    }

    fn same_shape(&self, entry: &RuleEntry, strings: &[Box<str>]) -> bool {
        self.index == entry.index
            && string_at(strings, self.rule_type) == entry.rule_type.as_str()
            && self.payload.as_ref() == entry.payload.as_str()
            && string_at(strings, self.proxy) == entry.proxy.as_str()
            && self.extra_params.len() == entry.extra_params.len()
            && self
                .extra_params
                .iter()
                .zip(&entry.extra_params)
                .all(|(id, param)| string_at(strings, *id) == param.as_str())
    }

    fn apply_runtime(&mut self, entry: RuleEntry) {
        self.disabled = entry.disabled;
        self.hit_count = entry.hit_count;
        self.hit_at = boxed_non_empty(entry.hit_at);
        self.miss_count = entry.miss_count;
        self.miss_at = boxed_non_empty(entry.miss_at);
        self.has_extra = entry.has_extra;
    }

    fn to_entry(&self, strings: &[Box<str>]) -> RuleEntry {
        RuleEntry {
            index: self.index,
            rule_type: string_at(strings, self.rule_type).to_string(),
            payload: self.payload.to_string(),
            proxy: string_at(strings, self.proxy).to_string(),
            extra_params: self
                .extra_params
                .iter()
                .map(|id| string_at(strings, *id).to_string())
                .collect(),
            disabled: self.disabled,
            hit_count: self.hit_count,
            hit_at: self.hit_at.as_deref().unwrap_or_default().to_string(),
            miss_count: self.miss_count,
            miss_at: self.miss_at.as_deref().unwrap_or_default().to_string(),
            has_extra: self.has_extra,
        }
    }
}

fn string_at(strings: &[Box<str>], id: u32) -> &str {
    strings
        .get(id as usize)
        .map(|value| value.as_ref())
        .unwrap_or_default()
}

fn boxed_non_empty(value: String) -> Option<Box<str>> {
    (!value.is_empty()).then(|| value.into_boxed_str())
}

fn cache() -> &'static ActiveTargetCache<Arc<Mutex<RulesCache>>> {
    static C: OnceLock<ActiveTargetCache<Arc<Mutex<RulesCache>>>> = OnceLock::new();
    C.get_or_init(ActiveTargetCache::new)
}

pub async fn controller_rules_load(
    target: BackendTarget,
    filter: String,
    force: bool,
) -> Result<RulesSummary, MihomoError> {
    if target.backend_type == BackendType::SingBox {
        return Ok(RulesSummary::default());
    }
    let key = target.cache_key();
    let previous = cache().get(&key);
    let loaded = cache()
        .load(&key, force, || async move {
            let all: Vec<RuleEntry> = match target.backend_type {
                BackendType::Clash => crate::clash::api::fetch_rules(target.clash())
                    .await?
                    .into_iter()
                    .map(Into::into)
                    .collect(),
                BackendType::Surge => crate::surge::api::fetch_rules(target.surge()).await?,
                BackendType::SingBox => Vec::new(),
            };
            if let Some(previous) = previous {
                previous.lock().expect("rules cache poisoned").apply(all);
                Ok(previous)
            } else {
                Ok(Arc::new(Mutex::new(RulesCache::new(all))))
            }
        })
        .await?;
    let mut loaded = loaded.lock().expect("rules cache poisoned");
    loaded.set_filter(filter);
    Ok(loaded.summary())
}

pub async fn controller_rules_set_filter(target: BackendTarget, filter: String) -> RulesSummary {
    let Some(cache) = cache().get(&target.cache_key()) else {
        return RulesSummary::default();
    };
    let mut cache = cache.lock().expect("rules cache poisoned");
    cache.set_filter(filter);
    cache.summary()
}

pub async fn controller_rules_window(
    target: BackendTarget,
    offset: u32,
    limit: u32,
) -> Vec<RuleEntry> {
    let Some(cache) = cache().get(&target.cache_key()) else {
        return Vec::new();
    };
    let cache = cache.lock().expect("rules cache poisoned");
    let start = (offset as usize).min(cache.filtered_len());
    let end = start
        .saturating_add(limit as usize)
        .min(cache.filtered_len());
    match cache.filtered.as_ref() {
        Some(filtered) => filtered[start..end]
            .iter()
            .filter_map(|index| cache.entry(*index as usize))
            .collect(),
        None => (start..end)
            .filter_map(|index| cache.entry(index))
            .collect(),
    }
}

pub async fn controller_rules_disable(
    target: BackendTarget,
    index: u32,
    disabled: bool,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::rules_disable(target.clash(), index, disabled).await?
        }
        BackendType::Surge => return crate::surge::api::unsupported("禁用规则").await,
        BackendType::SingBox => return crate::sing_box::api::unsupported("禁用规则").await,
    }
    if let Some(cache) = cache().get(&target.cache_key())
        && let Some(entry) = cache
            .lock()
            .expect("rules cache poisoned")
            .all
            .iter_mut()
            .find(|entry| entry.index == index)
    {
        entry.disabled = disabled;
    }
    Ok(())
}

pub(super) fn release_target(target: &BackendTarget) {
    cache().clear(&target.cache_key());
}

fn rule_matches(entry: &CachedRuleEntry, strings: &[Box<str>], needle: &str) -> bool {
    contains_filter(entry.payload.as_ref(), needle)
        || contains_filter(string_at(strings, entry.rule_type), needle)
        || contains_filter(string_at(strings, entry.proxy), needle)
        || entry
            .extra_params
            .iter()
            .any(|param| contains_filter(string_at(strings, *param), needle))
}
