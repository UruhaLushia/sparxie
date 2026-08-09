use std::collections::HashMap;

use crate::clash::api::MihomoTarget;

use super::super::{ProxyMemberEntry, ProxyMemberSection, ProxyMemberSort};
use super::sort::sort_members;
use super::{CachedCatalog, CachedGroup, CachedNode, with_catalog};

impl CachedCatalog {
    fn ensure_lower_names(&mut self) {
        if self.lower_names.is_none() {
            self.lower_names = Some(self.names.iter().map(|name| name.to_lowercase()).collect());
        }
    }
}

impl CachedGroup {
    pub(super) fn member_ids(
        &mut self,
        sort: ProxyMemberSort,
        group_by_provider: bool,
        lower_names: &[String],
        nodes: &[Option<CachedNode>],
    ) -> &[u32] {
        let stale =
            self.ordered_members
                .as_ref()
                .is_none_or(|(cached_sort, cached_grouping, _)| {
                    *cached_sort != sort || *cached_grouping != group_by_provider
                });
        if stale {
            let mut ids = self.members.clone();
            if group_by_provider {
                let mut provider_positions = HashMap::<String, usize>::from([(String::new(), 0)]);
                let mut provider_members = vec![Vec::<u32>::new()];
                for id in ids {
                    let provider = provider_of(nodes, id).to_string();
                    let position = match provider_positions.get(&provider) {
                        Some(position) => *position,
                        None => {
                            let position = provider_members.len();
                            provider_positions.insert(provider, position);
                            provider_members.push(Vec::new());
                            position
                        }
                    };
                    provider_members[position].push(id);
                }

                ids = Vec::with_capacity(self.members.len());
                for mut members in provider_members {
                    sort_members(&mut members, sort, lower_names, nodes);
                    ids.extend(members);
                }
            } else {
                sort_members(&mut ids, sort, lower_names, nodes);
            }
            self.ordered_members = Some((sort, group_by_provider, ids));
        }
        self.ordered_members
            .as_ref()
            .map(|(_, _, ids)| ids.as_slice())
            .unwrap_or(&self.members)
    }
}

pub(in super::super) fn member_entries(
    target: &MihomoTarget,
    group_name: &str,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
) -> Option<Vec<ProxyMemberEntry>> {
    with_catalog(target, |catalog| {
        if needs_lower_names(member_sort) {
            catalog.ensure_lower_names();
        }
        let CachedCatalog {
            names,
            lower_names,
            nodes,
            groups,
            ..
        } = catalog;
        let group = groups.get_mut(group_name)?;
        let ids = group.member_ids(
            member_sort,
            group_by_provider,
            lower_names.as_deref().unwrap_or(&[]),
            nodes,
        );
        let start = (offset as usize).min(ids.len());
        let end = start.saturating_add(limit as usize).min(ids.len());
        Some(
            ids[start..end]
                .iter()
                .map(|id| member_entry(*id, names, nodes))
                .collect(),
        )
    })
    .flatten()
}

pub(in super::super) fn member_sections(
    target: &MihomoTarget,
    group_name: &str,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
) -> Vec<ProxyMemberSection> {
    if !group_by_provider {
        return Vec::new();
    }
    with_catalog(target, |catalog| {
        if needs_lower_names(member_sort) {
            catalog.ensure_lower_names();
        }
        let CachedCatalog {
            lower_names,
            nodes,
            groups,
            ..
        } = catalog;
        let Some(group) = groups.get_mut(group_name) else {
            return Vec::new();
        };
        let ids = group.member_ids(
            member_sort,
            true,
            lower_names.as_deref().unwrap_or(&[]),
            nodes,
        );
        let mut has_provider = false;
        let mut sections = Vec::<ProxyMemberSection>::new();
        for (index, id) in ids.iter().enumerate() {
            let provider = provider_of(nodes, *id);
            has_provider |= !provider.is_empty();
            if let Some(section) = sections.last_mut()
                && section.provider == provider
            {
                section.count = section.count.saturating_add(1);
                continue;
            }
            sections.push(ProxyMemberSection {
                provider: provider.to_string(),
                offset: index.min(u32::MAX as usize) as u32,
                count: 1,
            });
        }
        if has_provider { sections } else { Vec::new() }
    })
    .unwrap_or_default()
}

pub(in super::super) fn member_position(
    target: &MihomoTarget,
    group_name: &str,
    name: &str,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
) -> Option<(usize, usize)> {
    with_catalog(target, |catalog| {
        if needs_lower_names(member_sort) {
            catalog.ensure_lower_names();
        }
        let CachedCatalog {
            names,
            lower_names,
            nodes,
            groups,
            ..
        } = catalog;
        let group = groups.get_mut(group_name)?;
        let ids = group.member_ids(
            member_sort,
            group_by_provider,
            lower_names.as_deref().unwrap_or(&[]),
            nodes,
        );
        let index = ids
            .iter()
            .position(|id| names.get(*id as usize).is_some_and(|member| member == name))?;
        Some((index, ids.len()))
    })
    .flatten()
}

pub(in super::super) fn member_names(target: &MihomoTarget, group_name: &str) -> Vec<String> {
    with_catalog(target, |catalog| {
        let CachedCatalog {
            names,
            nodes,
            groups,
            ..
        } = catalog;
        let Some(group) = groups.get_mut(group_name) else {
            return Vec::new();
        };
        group
            .member_ids(ProxyMemberSort::Original, false, &[], nodes)
            .iter()
            .filter_map(|id| names.get(*id as usize).cloned())
            .collect()
    })
    .unwrap_or_default()
}

fn member_entry(id: u32, names: &[String], nodes: &[Option<CachedNode>]) -> ProxyMemberEntry {
    let id = id as usize;
    let node = nodes.get(id).and_then(Option::as_ref);
    ProxyMemberEntry {
        name: names.get(id).cloned().unwrap_or_default(),
        proxy_type: node
            .map(|node| node.proxy_type.to_string())
            .unwrap_or_else(|| "Proxy".to_string()),
        delay: node.map(|node| node.delay).unwrap_or(-1),
    }
}

fn provider_of(nodes: &[Option<CachedNode>], id: u32) -> &str {
    nodes
        .get(id as usize)
        .and_then(Option::as_ref)
        .and_then(|node| node.provider.as_deref())
        .unwrap_or_default()
}

fn needs_lower_names(sort: ProxyMemberSort) -> bool {
    matches!(sort, ProxyMemberSort::Name | ProxyMemberSort::Delay)
}
