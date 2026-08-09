use std::collections::{HashMap, HashSet};
use std::time::Instant;

use serde_json::Value;

use crate::MihomoError;
use crate::clash::api::{MihomoTarget, urlencode};

use super::super::value::{field_or, proxy_delay};
use super::cache::CachedNode;
use super::member_window::refresh_cached_catalog;
use super::{ProxyMemberEntry, ProxyMemberSort, cache, provider_nodes};

pub(crate) async fn refresh_cached_provider_nodes(
    target: &MihomoTarget,
) -> Result<(), MihomoError> {
    if let Ok(nodes) = provider_nodes(target, true).await {
        cache::mark_provider_nodes_checked(target, Instant::now());
        cache::merge_provider_nodes(target, nodes.summaries);
    }
    Ok(())
}

pub(crate) async fn cached_proxy_detail(
    target: &MihomoTarget,
    name: &str,
) -> Result<Option<String>, MihomoError> {
    if !cache::has_catalog(target) {
        refresh_cached_catalog(target).await?;
    }
    if let Some(detail) = cache::proxy_detail(target, name) {
        return Ok(Some(detail));
    }
    if let Some(detail) =
        crate::clash::api::providers::proxy_provider_detail(target, name, false).await?
    {
        return Ok(Some(detail));
    }
    refresh_cached_provider_nodes(target).await?;
    crate::clash::api::providers::proxy_provider_detail(target, name, false).await
}

pub(crate) async fn refresh_cached_node_detail(
    target: &MihomoTarget,
    name: &str,
    provider_backed: bool,
) -> Result<(), MihomoError> {
    if provider_backed {
        let _ = crate::clash::api::providers::proxy_provider_detail(target, name, true).await?;
        return Ok(());
    }
    let path = format!("proxies/{}", urlencode(name));
    let detail = target.client()?.get_json(&path).await?.to_string();
    cache::set_direct_detail(target, name.to_string(), detail);
    Ok(())
}

pub(crate) fn cache_proxy_detail(target: &MihomoTarget, name: String, detail: String) {
    cache::set_direct_detail(target, name, detail);
}

pub(super) fn cached_node(data: &Value) -> CachedNode {
    cached_node_with_provider(data, node_provider_name(data))
}

fn cached_node_with_provider(data: &Value, provider: Option<String>) -> CachedNode {
    CachedNode {
        proxy_type: field_or(data, "type", "Proxy").into_boxed_str(),
        delay: proxy_delay(data),
        provider: provider.map(String::into_boxed_str),
    }
}

fn node_provider_name(data: &Value) -> Option<String> {
    let provider = field_or(data, "provider-name", "");
    (!provider.is_empty()).then_some(provider)
}

pub(crate) async fn cached_node_providers(
    target: MihomoTarget,
    names: &[String],
) -> Result<HashMap<String, String>, MihomoError> {
    let names: HashSet<String> = names.iter().cloned().collect();
    if names.is_empty() {
        return Ok(HashMap::new());
    }
    if !cache::has_catalog(&target) {
        refresh_cached_catalog(&target).await?;
    }
    if cache::names_need_provider_nodes(&target, &names) {
        refresh_cached_provider_nodes(&target).await?;
    }
    Ok(cache::node_providers(&target, &names))
}

pub(crate) fn update_cached_node_delay(target: &MihomoTarget, name: &str, delay: i32) {
    cache::update_node_delays(target, [(name, delay)]);
    crate::clash::api::providers::update_proxy_provider_delays(target, [(name, delay)]);
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn update_cached_node_delay_window(
    target: &MihomoTarget,
    group: &str,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    _window_members_hash: u32,
    name: &str,
    delay: i32,
) -> Option<(bool, Vec<ProxyMemberEntry>)> {
    if window_limit == 0 {
        update_cached_node_delay(target, name, delay);
        return None;
    }
    let before = cache::member_entries(
        target,
        group,
        window_offset,
        window_limit,
        member_sort,
        false,
    )
    .unwrap_or_default();
    let visible_delay_changed = before
        .iter()
        .find(|entry| entry.name == name)
        .is_some_and(|entry| entry.delay != delay);

    if member_sort != ProxyMemberSort::Delay {
        update_cached_node_delay(target, name, delay);
        return visible_delay_changed.then(|| (true, Vec::new()));
    }

    update_cached_node_delay(target, name, delay);
    let after = cache::member_entries(
        target,
        group,
        window_offset,
        window_limit,
        member_sort,
        false,
    )
    .unwrap_or_default();
    if same_member_order(&before, &after) {
        visible_delay_changed.then(|| (true, Vec::new()))
    } else {
        Some((false, after))
    }
}

pub(crate) fn update_cached_node_delays<'a>(
    target: &MihomoTarget,
    delays: impl IntoIterator<Item = (&'a str, i32)>,
) {
    let delays: Vec<_> = delays.into_iter().collect();
    cache::update_node_delays(target, delays.iter().copied());
    crate::clash::api::providers::update_proxy_provider_delays(target, delays.iter().copied());
}

fn same_member_order(a: &[ProxyMemberEntry], b: &[ProxyMemberEntry]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(a, b)| a.name == b.name)
}
