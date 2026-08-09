use std::collections::{HashMap, HashSet};

use crate::clash::api::MihomoTarget;

use super::{CachedGroup, CachedNode, with_catalog};

pub(in super::super) fn merge_provider_nodes(
    target: &MihomoTarget,
    incoming: HashMap<String, CachedNode>,
) {
    let _ = with_catalog(target, |catalog| {
        let mut changed = false;
        for (id, name) in catalog.names.iter().enumerate() {
            let Some(node) = incoming.get(name) else {
                continue;
            };
            let Some(slot) = catalog.nodes.get_mut(id) else {
                continue;
            };
            match slot {
                None => {
                    *slot = Some(node.clone());
                    changed = true;
                }
                Some(existing) => {
                    let mut node_changed = false;
                    if node.provider.is_some() && existing.provider != node.provider {
                        existing.provider = node.provider.clone();
                        node_changed = true;
                    }
                    if existing.proxy_type.as_ref() == "Proxy"
                        && existing.proxy_type.as_ref() != node.proxy_type.as_ref()
                    {
                        existing.proxy_type.clone_from(&node.proxy_type);
                        node_changed = true;
                    }
                    if existing.delay != node.delay {
                        existing.delay = node.delay;
                        node_changed = true;
                    }
                    changed |= node_changed;
                }
            }
        }
        if changed {
            for group in catalog.groups.values_mut() {
                group.clear_ordered_members();
            }
        }
    });
}

pub(in super::super) fn update_node_delays<'a>(
    target: &MihomoTarget,
    delays: impl IntoIterator<Item = (&'a str, i32)>,
) {
    let mut delays: HashMap<&str, i32> = delays.into_iter().collect();
    if delays.is_empty() {
        return;
    }
    let _ = with_catalog(target, |catalog| {
        let mut changed_ids = HashSet::new();
        for (id, name) in catalog.names.iter().enumerate() {
            let Some(delay) = delays.remove(name.as_str()) else {
                continue;
            };
            let Some(slot) = catalog.nodes.get_mut(id) else {
                continue;
            };
            match slot {
                Some(node) if node.delay != delay => {
                    node.delay = delay;
                    changed_ids.insert(id);
                }
                None => {
                    *slot = Some(CachedNode {
                        proxy_type: "Proxy".into(),
                        delay,
                        provider: None,
                    });
                    changed_ids.insert(id);
                }
                _ => {}
            }
            if delays.is_empty() {
                break;
            }
        }
        if changed_ids.is_empty() {
            return;
        }
        for group in catalog.groups.values_mut() {
            if group
                .members
                .iter()
                .any(|id| changed_ids.contains(&(*id as usize)))
            {
                group.clear_ordered_members();
            }
        }
    });
}

pub(in super::super) fn node_delays(
    target: &MihomoTarget,
    names: &HashSet<&str>,
) -> HashMap<String, i32> {
    if names.is_empty() {
        return HashMap::new();
    }
    with_catalog(target, |catalog| {
        catalog
            .names
            .iter()
            .zip(catalog.nodes.iter())
            .filter(|(name, _)| names.contains(name.as_str()))
            .filter_map(|(name, node)| node.as_ref().map(|node| (name.clone(), node.delay)))
            .collect()
    })
    .unwrap_or_default()
}

pub(in super::super) fn node_providers(
    target: &MihomoTarget,
    names: &HashSet<String>,
) -> HashMap<String, String> {
    with_catalog(target, |catalog| {
        catalog
            .names
            .iter()
            .enumerate()
            .filter(|(_, name)| names.contains(*name))
            .filter_map(|(id, name)| {
                catalog
                    .nodes
                    .get(id)
                    .and_then(Option::as_ref)
                    .and_then(|node| node.provider.clone())
                    .map(|provider| (name.clone(), provider.to_string()))
            })
            .collect()
    })
    .unwrap_or_default()
}

pub(in super::super) fn names_need_provider_nodes(
    target: &MihomoTarget,
    names: &HashSet<String>,
) -> bool {
    with_catalog(target, |catalog| {
        catalog
            .names
            .iter()
            .enumerate()
            .filter(|(_, name)| names.contains(*name))
            .any(|(id, _)| {
                needs_provider_node(
                    catalog.nodes.get(id).and_then(Option::as_ref),
                    &catalog.groups,
                )
            })
    })
    .unwrap_or(false)
}

fn needs_provider_node(node: Option<&CachedNode>, groups: &HashMap<String, CachedGroup>) -> bool {
    match node {
        None => true,
        Some(node) => {
            if node
                .provider
                .as_deref()
                .is_some_and(|provider| groups.contains_key(provider))
            {
                return true;
            }
            node.provider.is_none() && node.proxy_type.as_ref() == "Proxy"
        }
    }
}
