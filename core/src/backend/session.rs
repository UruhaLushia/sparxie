use std::future::Future;
use std::sync::OnceLock;

use crate::MihomoError;
use crate::cache::target::ActiveTargetCache;

use super::diagnostics::OutboundEntry;
use super::{BackendTarget, BackendType, ControllerConfig, SessionBootstrap};

fn configs_cache() -> &'static ActiveTargetCache<ControllerConfig> {
    static C: OnceLock<ActiveTargetCache<ControllerConfig>> = OnceLock::new();
    C.get_or_init(ActiveTargetCache::new)
}

fn diagnostics_cache() -> &'static ActiveTargetCache<Vec<OutboundEntry>> {
    static C: OnceLock<ActiveTargetCache<Vec<OutboundEntry>>> = OnceLock::new();
    C.get_or_init(ActiveTargetCache::new)
}

pub(super) async fn configs<F, Fut>(
    target: &BackendTarget,
    loader: F,
) -> Result<ControllerConfig, MihomoError>
where
    F: FnOnce() -> Fut,
    Fut: Future<Output = Result<ControllerConfig, MihomoError>>,
{
    configs_cache()
        .load(&target.cache_key(), false, loader)
        .await
}

pub(super) fn invalidate_configs(target: &BackendTarget) {
    configs_cache().invalidate(&target.cache_key());
}

pub(super) async fn diagnostics_outbounds<F, Fut>(
    target: &BackendTarget,
    loader: F,
) -> Result<Vec<OutboundEntry>, MihomoError>
where
    F: FnOnce() -> Fut,
    Fut: Future<Output = Result<Vec<OutboundEntry>, MihomoError>>,
{
    diagnostics_cache()
        .load(&target.cache_key(), false, loader)
        .await
}

/// Fetch the immutable/low-frequency data for one controller as soon as it is
/// connected. Each getter below shares the same in-flight load, so a page that
/// opens during bootstrap waits for that request instead of starting another.
pub async fn controller_prepare_target(target: BackendTarget) -> SessionBootstrap {
    match target.backend_type {
        BackendType::Clash => {
            let (_, rules, _, _) = tokio::join!(
                super::control::controller_configs(target.clone()),
                super::rules::controller_rules_load(target.clone(), String::new(), false),
                super::providers::controller_proxy_provider_catalog(target.clone(), false),
                super::providers::controller_rule_provider_catalog(target, false),
            );
            SessionBootstrap {
                rule_count: rules.map(|summary| summary.total).unwrap_or_default(),
            }
        }
        BackendType::Surge => {
            let (_, rules) = tokio::join!(
                super::control::controller_configs(target.clone()),
                super::rules::controller_rules_load(target, String::new(), false),
            );
            SessionBootstrap {
                rule_count: rules.map(|summary| summary.total).unwrap_or_default(),
            }
        }
        BackendType::SingBox => {
            let _ = tokio::join!(
                super::control::controller_configs(target.clone()),
                super::diagnostics::controller_diagnostics_outbounds(target),
            );
            SessionBootstrap::default()
        }
    }
}

pub(crate) fn release_target(target: &BackendTarget) {
    let key = target.cache_key();
    configs_cache().clear(&key);
    diagnostics_cache().clear(&key);
    super::rules::release_target(target);
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::clear_provider_cache(&target.clash());
            crate::clash::api::clear_proxy_catalog_cache(&target.clash());
        }
        BackendType::Surge | BackendType::SingBox => {}
    }
}
