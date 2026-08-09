use crate::MihomoError;

use super::{BackendTarget, BackendType, ProxyCatalog, ProxyMemberSort, ProxyMemberWindow};

pub async fn controller_groups(target: BackendTarget) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::groups(target.clash()).await,
        BackendType::Surge => {
            Ok(
                crate::surge::api::proxy_catalog(target.surge(), true, String::new())
                    .await?
                    .groups
                    .into_iter()
                    .map(|group| group.name)
                    .collect::<Vec<_>>()
                    .join("\n"),
            )
        }
        BackendType::SingBox => {
            Ok(
                crate::sing_box::api::proxy_catalog(target.sing_box(), true, String::new())
                    .await?
                    .groups
                    .into_iter()
                    .map(|group| group.name)
                    .collect::<Vec<_>>()
                    .join("\n"),
            )
        }
    }
}

pub async fn controller_proxies(
    target: BackendTarget,
    name_pattern: Option<String>,
    type_pattern: Option<String>,
    groups_only: bool,
) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::proxies(target.clash(), name_pattern, type_pattern, groups_only)
                .await
        }
        BackendType::Surge => Ok(serde_json::to_string(
            &crate::surge::api::proxy_catalog(target.surge(), true, String::new())
                .await?
                .groups
                .into_iter()
                .map(|group| group.name)
                .collect::<Vec<_>>(),
        )?),
        BackendType::SingBox => Ok(serde_json::to_string(
            &crate::sing_box::api::proxy_catalog(target.sing_box(), true, String::new())
                .await?
                .groups
                .into_iter()
                .map(|group| group.name)
                .collect::<Vec<_>>(),
        )?),
    }
}

pub async fn controller_proxy_detail(
    target: BackendTarget,
    name: String,
) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::proxy_detail(target.clash(), name).await,
        BackendType::Surge => Ok(serde_json::json!({ "name": name }).to_string()),
        BackendType::SingBox => Ok(serde_json::json!({ "name": name }).to_string()),
    }
}

pub async fn controller_select_proxy(
    target: BackendTarget,
    group: String,
    name: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::select_proxy(target.clash(), group, name).await,
        BackendType::Surge => crate::surge::api::select_proxy(target.surge(), group, name).await,
        BackendType::SingBox => {
            crate::sing_box::api::select_proxy(target.sing_box(), group, name).await
        }
    }
}

pub async fn controller_unfix_proxy(
    target: BackendTarget,
    name: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::unfix_proxy(target.clash(), name).await,
        BackendType::Surge => crate::surge::api::unfix_proxy(target.surge(), name).await,
        BackendType::SingBox => crate::sing_box::api::unfix_proxy(target.sing_box(), name).await,
    }
}

pub async fn controller_proxy_catalog(
    target: BackendTarget,
    include_hidden: bool,
    resolve_provider_current_delay: bool,
    filter: String,
) -> Result<ProxyCatalog, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_catalog(
            target.clash(),
            include_hidden,
            resolve_provider_current_delay,
            filter,
        )
        .await?
        .into()),
        BackendType::Surge => {
            crate::surge::api::proxy_catalog(target.surge(), include_hidden, filter).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::proxy_catalog(target.sing_box(), include_hidden, filter).await
        }
    }
}

pub async fn controller_proxy_group_members(
    target: BackendTarget,
    group: String,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
    group_by_provider: bool,
    current_name: Option<String>,
) -> Result<ProxyMemberWindow, MihomoError> {
    let locate_current = current_name.as_deref().is_some_and(|name| !name.is_empty());
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_group_member_window(
            target.clash(),
            group,
            offset,
            limit,
            super::clash_member_sort(member_sort),
            group_by_provider,
            current_name,
        )
        .await?
        .into()),
        BackendType::Surge => Ok(member_window(
            crate::surge::api::proxy_group_members(
                target.surge(),
                group,
                if locate_current { 0 } else { offset },
                if locate_current { u32::MAX } else { limit },
                member_sort,
            )
            .await?,
            offset,
            limit,
            current_name.as_deref(),
        )),
        BackendType::SingBox => Ok(member_window(
            crate::sing_box::api::proxy_group_members(
                target.sing_box(),
                group,
                if locate_current { 0 } else { offset },
                if locate_current { u32::MAX } else { limit },
                member_sort,
            )
            .await?,
            offset,
            limit,
            current_name.as_deref(),
        )),
    }
}

fn member_window(
    entries: Vec<super::ProxyMemberEntry>,
    requested_offset: u32,
    limit: u32,
    current_name: Option<&str>,
) -> ProxyMemberWindow {
    let Some(current_name) = current_name.filter(|name| !name.is_empty()) else {
        return ProxyMemberWindow {
            offset: requested_offset,
            current_index: -1,
            entries,
            sections: Vec::new(),
        };
    };
    let Some(index) = entries.iter().position(|entry| entry.name == current_name) else {
        return ProxyMemberWindow {
            offset: requested_offset,
            current_index: -1,
            entries: entries
                .into_iter()
                .skip(requested_offset as usize)
                .take(limit as usize)
                .collect(),
            sections: Vec::new(),
        };
    };
    let offset = index.saturating_sub((limit as usize) / 2).min(
        entries
            .len()
            .saturating_sub((limit as usize).min(entries.len())),
    );
    ProxyMemberWindow {
        offset: offset.min(u32::MAX as usize) as u32,
        current_index: index.min(i32::MAX as usize) as i32,
        entries: entries
            .into_iter()
            .skip(offset)
            .take(limit as usize)
            .collect(),
        sections: Vec::new(),
    }
}
