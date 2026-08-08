use crate::MihomoError;

use super::{BackendTarget, BackendType, RuleEntry, RulesSummary};

pub async fn controller_rules_count(target: BackendTarget) -> u32 {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::rules_count(target.clash()).await,
        BackendType::Surge => crate::surge::api::rules_count(target.surge()).await,
        BackendType::SingBox => 0,
    }
}

pub async fn controller_rules_load(
    target: BackendTarget,
    filter: String,
) -> Result<RulesSummary, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::rules_load(target.clash(), filter)
            .await?
            .into()),
        BackendType::Surge => crate::surge::api::rules_load(target.surge(), filter).await,
        BackendType::SingBox => Ok(RulesSummary::default()),
    }
}

pub async fn controller_rules_set_filter(target: BackendTarget, filter: String) -> RulesSummary {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::rules_set_filter(target.clash(), filter)
            .await
            .into(),
        BackendType::Surge => crate::surge::api::rules_set_filter(target.surge(), filter).await,
        BackendType::SingBox => RulesSummary::default(),
    }
}

pub async fn controller_rules_window(
    target: BackendTarget,
    offset: u32,
    limit: u32,
) -> Vec<RuleEntry> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::rules_window(target.clash(), offset, limit)
            .await
            .into_iter()
            .map(Into::into)
            .collect(),
        BackendType::Surge => crate::surge::api::rules_window(target.surge(), offset, limit).await,
        BackendType::SingBox => Vec::new(),
    }
}

pub async fn controller_rules_disable(
    target: BackendTarget,
    index: u32,
    disabled: bool,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::rules_disable(target.clash(), index, disabled).await
        }
        BackendType::Surge => crate::surge::api::unsupported("禁用规则").await,
        BackendType::SingBox => crate::sing_box::api::unsupported("禁用规则").await,
    }
}
