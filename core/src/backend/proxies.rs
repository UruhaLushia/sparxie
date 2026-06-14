use crate::MihomoError;

use super::{BackendTarget, BackendType, ProxyCatalog, ProxyMemberEntry, ProxyMemberSort};

pub async fn groups(target: BackendTarget) -> Result<String, MihomoError> {
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

pub async fn proxies(
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

pub async fn proxy_detail(target: BackendTarget, name: String) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::proxy_detail(target.clash(), name).await,
        BackendType::Surge => Ok(serde_json::json!({ "name": name }).to_string()),
        BackendType::SingBox => Ok(serde_json::json!({ "name": name }).to_string()),
    }
}

pub async fn select_proxy(
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

pub async fn unfix_proxy(target: BackendTarget, name: String) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::unfix_proxy(target.clash(), name).await,
        BackendType::Surge => crate::surge::api::unfix_proxy(target.surge(), name).await,
        BackendType::SingBox => crate::sing_box::api::unfix_proxy(target.sing_box(), name).await,
    }
}

pub async fn proxy_catalog(
    target: BackendTarget,
    include_hidden: bool,
    filter: String,
) -> Result<ProxyCatalog, MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            Ok(
                crate::clash::api::proxy_catalog(target.clash(), include_hidden, filter)
                    .await?
                    .into(),
            )
        }
        BackendType::Surge => {
            crate::surge::api::proxy_catalog(target.surge(), include_hidden, filter).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::proxy_catalog(target.sing_box(), include_hidden, filter).await
        }
    }
}

pub async fn proxy_group_members(
    target: BackendTarget,
    group: String,
    offset: u32,
    limit: u32,
    member_sort: ProxyMemberSort,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_group_members(
            target.clash(),
            group,
            offset,
            limit,
            super::clash_member_sort(member_sort),
        )
        .await?
        .into_iter()
        .map(Into::into)
        .collect()),
        BackendType::Surge => {
            crate::surge::api::proxy_group_members(
                target.surge(),
                group,
                offset,
                limit,
                member_sort,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::api::proxy_group_members(
                target.sing_box(),
                group,
                offset,
                limit,
                member_sort,
            )
            .await
        }
    }
}
