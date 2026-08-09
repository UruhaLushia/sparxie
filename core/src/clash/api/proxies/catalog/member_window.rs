use crate::MihomoError;
use crate::clash::api::MihomoTarget;

use super::{ProxyMemberEntry, ProxyMemberSort, ProxyMemberWindow, cache, proxy_catalog};

/// Windowed members for one proxy group. The full member list stays in Rust.
pub async fn proxy_group_members(
    target: MihomoTarget,
    group: String,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    ensure_cached_group(&target, &group).await?;
    Ok(cache::member_entries(
        &target,
        &group,
        offset,
        limit,
        member_sort,
        group_by_provider,
    )
    .unwrap_or_default())
}

pub async fn proxy_group_member_window(
    target: MihomoTarget,
    group: String,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
    current_name: Option<String>,
) -> Result<ProxyMemberWindow, MihomoError> {
    ensure_cached_group(&target, &group).await?;
    let mut window_offset = offset;
    let mut current_index = -1;
    if let Some(current_name) = current_name.as_deref().filter(|name| !name.is_empty())
        && let Some((index, total)) = cache::member_position(
            &target,
            &group,
            current_name,
            member_sort,
            group_by_provider,
        )
    {
        current_index = index.min(i32::MAX as usize) as i32;
        window_offset = centered_window_offset(index, total, limit);
    }
    let entries = cache::member_entries(
        &target,
        &group,
        window_offset,
        limit,
        member_sort,
        group_by_provider,
    )
    .unwrap_or_default();
    let sections = cache::member_sections(&target, &group, member_sort, group_by_provider);
    Ok(ProxyMemberWindow {
        offset: window_offset,
        current_index,
        entries,
        sections,
    })
}

pub(crate) async fn cached_group_member_names(
    target: MihomoTarget,
    group: &str,
) -> Result<Vec<String>, MihomoError> {
    if !cache::has_catalog(&target) {
        refresh_cached_catalog(&target).await?;
    }
    Ok(cache::member_names(&target, group))
}

async fn ensure_cached_group(target: &MihomoTarget, group: &str) -> Result<(), MihomoError> {
    if !cache::has_catalog(target) || !cache::has_group(target, group) {
        refresh_cached_catalog(target).await?;
    }
    Ok(())
}

fn centered_window_offset(index: usize, total: usize, limit: u32) -> u32 {
    let limit = (limit as usize).min(total);
    index
        .saturating_sub(limit / 2)
        .min(total.saturating_sub(limit))
        .min(u32::MAX as usize) as u32
}

pub(super) async fn refresh_cached_catalog(target: &MihomoTarget) -> Result<(), MihomoError> {
    let filter = cache::cached_filter(target).unwrap_or_default();
    let _ = proxy_catalog(target.clone(), true, false, filter).await?;
    Ok(())
}
