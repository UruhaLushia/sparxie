use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, Mutex, OnceLock, RwLock};

use serde_json::Value;

use crate::cache::target::ActiveTargetCache;
use crate::utils::text::contains_filter;

use super::super::proxies::value::proxy_delay;
use super::{ProxyProviderEntry, RuleProviderEntry, field_or};
use crate::clash::api::{MihomoTarget, ProxyMemberEntry};

const DETAIL_CACHE_LIMIT: usize = 16;

pub(crate) struct ProviderNode {
    pub(crate) name: Box<str>,
    pub(crate) proxy_type: Box<str>,
    pub(crate) delay: AtomicI32,
    pub(crate) provider_override: Option<Box<str>>,
}

pub(crate) struct ProxyProviderData {
    pub(super) snapshot: RwLock<ProxyProviderSnapshot>,
    pub(super) details: Mutex<ProviderDetailCache>,
    pub(super) filter: Mutex<ProviderNodeFilter>,
}

#[derive(Default)]
pub(super) struct ProxyProviderSnapshot {
    pub(super) catalog: Vec<ProxyProviderEntry>,
    pub(super) nodes: HashMap<String, Vec<ProviderNode>>,
}

#[derive(Default)]
pub(super) struct ProviderDetailCache {
    entries: VecDeque<((String, String), String)>,
}

#[derive(Default)]
pub(super) struct ProviderNodeFilter {
    provider: String,
    needle: String,
    pub(super) indices: Vec<u32>,
}

pub(super) fn proxy_cache() -> &'static ActiveTargetCache<Arc<ProxyProviderData>> {
    static C: OnceLock<ActiveTargetCache<Arc<ProxyProviderData>>> = OnceLock::new();
    C.get_or_init(ActiveTargetCache::new)
}

pub(super) fn rule_cache() -> &'static ActiveTargetCache<Arc<Vec<RuleProviderEntry>>> {
    static C: OnceLock<ActiveTargetCache<Arc<Vec<RuleProviderEntry>>>> = OnceLock::new();
    C.get_or_init(ActiveTargetCache::new)
}

pub(super) fn parse_proxy_provider_snapshot(
    raw: &Value,
    mut previous_nodes: HashMap<String, Vec<ProviderNode>>,
) -> ProxyProviderSnapshot {
    let Some(providers) = raw.get("providers").and_then(Value::as_object) else {
        return ProxyProviderSnapshot::default();
    };
    let mut catalog = Vec::with_capacity(providers.len());
    let mut provider_nodes = HashMap::with_capacity(providers.len());
    for (name, data) in providers {
        let vehicle_type = field_or(data, "vehicleType", "");
        if vehicle_type.eq_ignore_ascii_case("compatible") {
            continue;
        }
        let subscription_info = data.get("subscriptionInfo").and_then(Value::as_object);
        let subscription_value = |key| {
            subscription_info
                .and_then(|info| info.get(key))
                .map(super::value_to_u64)
                .unwrap_or_default()
        };
        catalog.push(ProxyProviderEntry {
            name: name.clone(),
            proxies: data
                .get("proxies")
                .and_then(Value::as_array)
                .map_or(0, |items| items.len().min(u32::MAX as usize) as u32),
            updatable: vehicle_type.eq_ignore_ascii_case("http"),
            vehicle_type,
            updated_at: field_or(data, "updatedAt", ""),
            has_subscription_info: subscription_info.is_some(),
            subscription_upload: subscription_value("Upload"),
            subscription_download: subscription_value("Download"),
            subscription_total: subscription_value("Total"),
            subscription_expire: subscription_value("Expire"),
        });
        let nodes = data
            .get("proxies")
            .and_then(Value::as_array)
            .map(|nodes| merge_provider_nodes(previous_nodes.remove(name), nodes, name))
            .unwrap_or_default();
        provider_nodes.insert(name.clone(), nodes);
    }
    catalog.sort_by(|a, b| a.name.cmp(&b.name));
    ProxyProviderSnapshot {
        catalog,
        nodes: provider_nodes,
    }
}

fn provider_node(value: &Value, provider: &str) -> Option<ProviderNode> {
    let name = field_or(value, "name", "");
    if name.is_empty() {
        return None;
    }
    let explicit_provider = field_or(value, "provider-name", "");
    Some(ProviderNode {
        name: name.into_boxed_str(),
        proxy_type: field_or(value, "type", "Proxy").into_boxed_str(),
        delay: AtomicI32::new(proxy_delay(value)),
        provider_override: (!explicit_provider.is_empty() && explicit_provider != provider)
            .then(|| explicit_provider.into_boxed_str()),
    })
}

fn merge_provider_nodes(
    previous: Option<Vec<ProviderNode>>,
    values: &[Value],
    provider: &str,
) -> Vec<ProviderNode> {
    let values: Vec<_> = values
        .iter()
        .filter(|value| !field_or(value, "name", "").is_empty())
        .collect();
    if let Some(mut nodes) = previous
        && nodes.len() == values.len()
        && nodes
            .iter()
            .zip(&values)
            .all(|(node, value)| node.name.as_ref() == field_or(value, "name", ""))
    {
        for (node, value) in nodes.iter_mut().zip(values) {
            update_provider_node(node, value, provider);
        }
        return nodes;
    }
    values
        .into_iter()
        .filter_map(|value| provider_node(value, provider))
        .collect()
}

fn update_provider_node(node: &mut ProviderNode, value: &Value, provider: &str) {
    let proxy_type = field_or(value, "type", "Proxy");
    if node.proxy_type.as_ref() != proxy_type {
        node.proxy_type = proxy_type.into_boxed_str();
    }
    node.delay.store(proxy_delay(value), Ordering::Relaxed);
    let explicit_provider = field_or(value, "provider-name", "");
    let provider_override = (!explicit_provider.is_empty() && explicit_provider != provider)
        .then(|| explicit_provider.into_boxed_str());
    if node.provider_override != provider_override {
        node.provider_override = provider_override;
    }
}

pub(super) fn provider_node_entry(node: &ProviderNode) -> ProxyMemberEntry {
    ProxyMemberEntry {
        name: node.name.to_string(),
        proxy_type: node.proxy_type.to_string(),
        delay: node.delay.load(Ordering::Relaxed),
    }
}

pub(super) fn provider_node_detail(mut value: Value, provider: &str) -> String {
    if field_or(&value, "provider-name", "").is_empty()
        && let Some(object) = value.as_object_mut()
    {
        object.insert(
            "provider-name".to_string(),
            Value::String(provider.to_string()),
        );
    }
    value.to_string()
}

impl ProviderDetailCache {
    pub(super) fn get(&mut self, provider: &str, name: &str) -> Option<String> {
        let position = self
            .entries
            .iter()
            .position(|((entry_provider, entry_name), _)| {
                entry_provider == provider && entry_name == name
            })?;
        let entry = self.entries.remove(position)?;
        let detail = entry.1.clone();
        self.entries.push_back(entry);
        Some(detail)
    }

    pub(super) fn insert(&mut self, provider: String, name: String, detail: String) {
        if let Some(position) = self
            .entries
            .iter()
            .position(|((entry_provider, entry_name), _)| {
                entry_provider == &provider && entry_name == &name
            })
        {
            self.entries.remove(position);
        }
        self.entries.push_back(((provider, name), detail));
        if self.entries.len() > DETAIL_CACHE_LIMIT {
            self.entries.pop_front();
        }
    }

    fn clear(&mut self) {
        self.entries.clear();
    }
}

impl ProviderNodeFilter {
    pub(super) fn update(&mut self, provider: &str, needle: String, nodes: &[ProviderNode]) {
        if self.provider == provider && self.needle == needle {
            return;
        }
        self.provider.clear();
        self.provider.push_str(provider);
        self.needle = needle;
        self.indices.clear();
        self.indices.extend(
            nodes
                .iter()
                .enumerate()
                .filter(|(_, node)| {
                    contains_filter(node.name.as_ref(), &self.needle)
                        || contains_filter(node.proxy_type.as_ref(), &self.needle)
                })
                .map(|(index, _)| index.min(u32::MAX as usize) as u32),
        );
    }
}

impl Default for ProxyProviderData {
    fn default() -> Self {
        Self {
            snapshot: RwLock::new(ProxyProviderSnapshot::default()),
            details: Mutex::new(ProviderDetailCache::default()),
            filter: Mutex::new(ProviderNodeFilter::default()),
        }
    }
}

impl ProxyProviderData {
    pub(super) fn apply(&self, raw: &Value) {
        let mut snapshot = self
            .snapshot
            .write()
            .expect("proxy provider snapshot poisoned");
        let previous_nodes = std::mem::take(&mut snapshot.nodes);
        *snapshot = parse_proxy_provider_snapshot(raw, previous_nodes);
        self.details
            .lock()
            .expect("provider detail cache poisoned")
            .clear();
        *self.filter.lock().expect("provider filter cache poisoned") =
            ProviderNodeFilter::default();
    }

    pub(crate) fn for_each_node(&self, mut f: impl FnMut(&str, &ProviderNode)) {
        let snapshot = self
            .snapshot
            .read()
            .expect("proxy provider snapshot poisoned");
        for (provider, nodes) in &snapshot.nodes {
            for node in nodes {
                f(provider, node);
            }
        }
    }

    pub(super) fn update_delays<'a>(&self, delays: impl IntoIterator<Item = (&'a str, i32)>) {
        let delays: HashMap<&str, i32> = delays.into_iter().collect();
        if delays.is_empty() {
            return;
        }
        let snapshot = self
            .snapshot
            .read()
            .expect("proxy provider snapshot poisoned");
        for node in snapshot.nodes.values().flatten() {
            if let Some(delay) = delays.get(node.name.as_ref()) {
                node.delay.store(*delay, Ordering::Relaxed);
            }
        }
    }
}

pub(super) fn clear_proxy_cache(target: &MihomoTarget) {
    proxy_cache().clear(&target.identity_key());
}

pub(super) fn clear_rule_cache(target: &MihomoTarget) {
    rule_cache().clear(&target.identity_key());
}

pub(super) fn invalidate_rule_cache(target: &MihomoTarget) {
    rule_cache().invalidate(&target.identity_key());
}
