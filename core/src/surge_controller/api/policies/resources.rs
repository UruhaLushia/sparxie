use std::collections::HashSet;
use std::sync::Arc;

use crate::backend::api::ProxyMemberEntry;
use crate::utils::text::contains_filter;

use super::source::SourceMember;

pub(crate) struct ResourceGroup {
    pub(crate) name: String,
    pub(crate) detail: String,
    pub(crate) members: Arc<[SourceMember]>,
}

#[derive(Clone)]
pub(crate) struct ResourceMembers {
    members: Arc<[SourceMember]>,
    positions: Arc<[u32]>,
}

impl ResourceMembers {
    pub(crate) fn len(&self) -> usize {
        self.positions.len()
    }

    pub(crate) fn window(
        &self,
        filter: &str,
        offset: u32,
        limit: u32,
    ) -> (usize, usize, Vec<ProxyMemberEntry>) {
        let needle = filter.trim().to_lowercase();
        let matches = |member: &SourceMember| {
            needle.is_empty()
                || contains_filter(&member.name, &needle)
                || contains_filter(&member.proxy_type, &needle)
        };
        let members = self
            .positions
            .iter()
            .filter_map(|position| self.members.get(*position as usize));
        let filtered = members.clone().filter(|member| matches(member)).count();
        let start = (offset as usize).min(filtered);
        let entries = members
            .filter(|member| matches(member))
            .skip(start)
            .take(limit.clamp(1, 512) as usize)
            .map(|member| ProxyMemberEntry {
                name: member.name.clone(),
                proxy_type: member.proxy_type.clone(),
                delay: -1,
            })
            .collect();
        (filtered, start, entries)
    }
}

pub(crate) fn resource_group_members(group: &ResourceGroup) -> ResourceMembers {
    let mut seen = HashSet::new();
    let positions = group
        .members
        .iter()
        .enumerate()
        .filter(|(_, member)| seen.insert(member.name.as_str()))
        .map(|(position, _)| position.min(u32::MAX as usize) as u32)
        .collect::<Vec<_>>()
        .into();
    ResourceMembers {
        members: Arc::clone(&group.members),
        positions,
    }
}
