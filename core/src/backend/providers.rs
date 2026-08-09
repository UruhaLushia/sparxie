use crate::MihomoError;

use super::{BackendTarget, BackendType, ProxyMemberEntry, ProxyProviderEntry, RuleProviderEntry};

pub async fn controller_proxy_providers(target: BackendTarget) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::proxy_providers(target.clash()).await,
        BackendType::Surge => crate::surge::api::proxy_providers(target.surge()).await,
        BackendType::SingBox => Ok(serde_json::json!({ "providers": {} }).to_string()),
    }
}

pub async fn controller_proxy_provider_catalog(
    target: BackendTarget,
) -> Result<Vec<ProxyProviderEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_provider_catalog(target.clash())
            .await?
            .into_iter()
            .map(Into::into)
            .collect()),
        BackendType::Surge => crate::surge::api::proxy_provider_catalog(target.surge()).await,
        BackendType::SingBox => Ok(Vec::new()),
    }
}

pub async fn controller_proxy_provider_nodes(
    target: BackendTarget,
    name: String,
) -> Result<Vec<ProxyMemberEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(
            crate::clash::api::proxy_provider_nodes(target.clash(), name)
                .await?
                .into_iter()
                .map(Into::into)
                .collect(),
        ),
        BackendType::Surge | BackendType::SingBox => Ok(Vec::new()),
    }
}

pub async fn controller_proxy_provider_update(
    target: BackendTarget,
    name: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::proxy_provider_update(target.clash(), name).await,
        BackendType::Surge => crate::surge::api::unsupported("更新代理提供者").await,
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
        BackendType::SingBox => crate::sing_box::api::unsupported("代理提供者健康检查").await,
    }
}

pub async fn controller_rule_providers(target: BackendTarget) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::rule_providers(target.clash()).await,
        BackendType::Surge => crate::surge::api::rule_providers(target.surge()).await,
        BackendType::SingBox => Ok(serde_json::json!({ "providers": {} }).to_string()),
    }
}

pub async fn controller_rule_provider_catalog(
    target: BackendTarget,
) -> Result<Vec<RuleProviderEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::rule_provider_catalog(target.clash())
            .await?
            .into_iter()
            .map(Into::into)
            .collect()),
        BackendType::Surge => crate::surge::api::rule_provider_catalog(target.surge()).await,
        BackendType::SingBox => Ok(Vec::new()),
    }
}

pub async fn controller_rule_provider_update(
    target: BackendTarget,
    name: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::rule_provider_update(target.clash(), name).await,
        BackendType::Surge => crate::surge::api::unsupported("更新规则提供者").await,
        BackendType::SingBox => crate::sing_box::api::unsupported("更新规则提供者").await,
    }
}

pub async fn controller_storage_get(
    target: BackendTarget,
    key: String,
) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::storage_get(target.clash(), key).await,
        BackendType::Surge => crate::surge::api::unsupported("持久化存储").await,
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
        BackendType::SingBox => crate::sing_box::api::unsupported("持久化存储").await,
    }
}
