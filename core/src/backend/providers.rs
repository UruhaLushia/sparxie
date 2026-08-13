use crate::MihomoError;

use super::{
    BackendTarget, BackendType, ProxyProviderEntry, ProxyProviderNodeWindow, RuleProviderEntry,
};

pub async fn controller_proxy_provider_catalog(
    target: BackendTarget,
    force: bool,
) -> Result<Vec<ProxyProviderEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(
            crate::clash::api::proxy_provider_catalog(target.clash(), force)
                .await?
                .into_iter()
                .map(Into::into)
                .collect(),
        ),
        BackendType::Surge => crate::surge::api::proxy_provider_catalog(target.surge()).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::proxy_provider_catalog(target.surge_controller(), force)
                .await
        }
        BackendType::SingBox => Ok(Vec::new()),
    }
}

pub async fn controller_proxy_provider_nodes(
    target: BackendTarget,
    name: String,
    filter: String,
    offset: u32,
    limit: u32,
) -> Result<ProxyProviderNodeWindow, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_provider_nodes(
            target.clash(),
            name,
            filter,
            offset,
            limit,
        )
        .await?
        .into()),
        BackendType::SurgeController => {
            crate::surge_controller::api::proxy_provider_nodes(
                target.surge_controller(),
                name,
                filter,
                offset,
                limit,
            )
            .await
        }
        BackendType::Surge | BackendType::SingBox => Ok(ProxyProviderNodeWindow::default()),
    }
}

pub async fn controller_proxy_provider_update(
    target: BackendTarget,
    name: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::proxy_provider_update(target.clash(), name).await,
        BackendType::Surge => crate::surge::api::unsupported("更新代理提供者").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::proxy_provider_update(target.surge_controller(), name)
                .await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("更新代理提供者").await,
    }
}

pub async fn controller_proxy_provider_healthcheck(
    target: BackendTarget,
    name: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::proxy_provider_healthcheck(target.clash(), name).await
        }
        BackendType::Surge => crate::surge::api::unsupported("代理提供者健康检查").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::unsupported("代理提供者健康检查").await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("代理提供者健康检查").await,
    }
}

pub async fn controller_rule_provider_catalog(
    target: BackendTarget,
    force: bool,
) -> Result<Vec<RuleProviderEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(
            crate::clash::api::rule_provider_catalog(target.clash(), force)
                .await?
                .into_iter()
                .map(Into::into)
                .collect(),
        ),
        BackendType::Surge => crate::surge::api::rule_provider_catalog(target.surge()).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::rule_provider_catalog(target.surge_controller(), force)
                .await
        }
        BackendType::SingBox => Ok(Vec::new()),
    }
}

pub async fn controller_rule_provider_update(
    target: BackendTarget,
    name: String,
) -> Result<(), MihomoError> {
    let cache_target = target.clone();
    let result = match target.backend_type {
        BackendType::Clash => crate::clash::api::rule_provider_update(target.clash(), name).await,
        BackendType::Surge => crate::surge::api::unsupported("更新规则提供者").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::rule_provider_update(target.surge_controller(), name)
                .await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("更新规则提供者").await,
    };
    if result.is_ok() {
        super::rules::release_target(&cache_target);
    }
    result
}

pub async fn controller_storage_get(
    target: BackendTarget,
    key: String,
) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::storage_get(target.clash(), key).await,
        BackendType::Surge => crate::surge::api::unsupported("持久化存储").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::unsupported("持久化存储").await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("持久化存储").await,
    }
}

pub async fn controller_storage_set(
    target: BackendTarget,
    key: String,
    value: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::storage_set(target.clash(), key, value).await,
        BackendType::Surge => crate::surge::api::unsupported("持久化存储").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::unsupported("持久化存储").await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("持久化存储").await,
    }
}

pub async fn controller_storage_delete(
    target: BackendTarget,
    key: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::storage_delete(target.clash(), key).await,
        BackendType::Surge => crate::surge::api::unsupported("持久化存储").await,
        BackendType::SurgeController => {
            crate::surge_controller::api::unsupported("持久化存储").await
        }
        BackendType::SingBox => crate::sing_box::api::unsupported("持久化存储").await,
    }
}
