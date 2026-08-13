use std::sync::Arc;
use std::time::Duration;

use crate::MihomoError;
use crate::surge_controller::client::SurgeControllerTarget;

use super::{command_ok, string_map};

mod catalog;
mod delay;
mod parse;
mod resources;
mod source;

pub use catalog::{proxy_catalog, proxy_group_members};
pub use delay::{group_delay, proxy_batch_delay, proxy_group_batch_delay};
use parse::is_auto_group;
pub(super) use resources::{ResourceGroup, ResourceMembers, resource_group_members};

const CACHE_TTL: Duration = Duration::from_secs(30);

pub(crate) fn clear_cache(target: &SurgeControllerTarget) {
    catalog::clear(target);
    source::clear(target);
}

pub(super) async fn resource_groups(
    target: &SurgeControllerTarget,
) -> Result<Vec<ResourceGroup>, MihomoError> {
    let source = source::load(target).await?;
    Ok(source
        .groups
        .iter()
        .map(|group| ResourceGroup {
            members: Arc::clone(&group.members),
            detail: group.meta.detail.clone(),
            name: group.name.clone(),
        })
        .collect())
}

pub async fn select_proxy(
    target: SurgeControllerTarget,
    group: String,
    name: String,
) -> Result<(), MihomoError> {
    let environment = target.request(["environment"]).await?;
    let environment = environment.get("environment").unwrap_or(&environment);
    let selections = string_map(environment.get("ProxyGroupSelection"));
    let overrides = string_map(environment.get("AutoPolicyGroupOverride"));
    let (selectable, auto) = source::load(&target)
        .await?
        .groups
        .iter()
        .find(|candidate| candidate.name == group)
        .map(|group| (group.meta.selectable, group.meta.auto))
        .unwrap_or_default();
    let key = if selectable || selections.contains_key(&group) {
        "ProxyGroupSelection"
    } else {
        let delays = target
            .request(["dump", "auto-test-group-result"])
            .await
            .unwrap_or_default();
        if !auto && !overrides.contains_key(&group) && !is_auto_group(&delays, &group) {
            return Err(MihomoError::Other(format!(
                "Surge 策略组 {group} 不支持手动选择或固定"
            )));
        }
        "AutoPolicyGroupOverride"
    };
    command_ok(&target, ["set".into(), format!("{key}.{group}={name}")]).await?;
    catalog::clear(&target);
    Ok(())
}

pub async fn unfix_proxy(target: SurgeControllerTarget, group: String) -> Result<(), MihomoError> {
    command_ok(
        &target,
        [
            "set".into(),
            format!("AutoPolicyGroupOverride.{group}=<nil>"),
        ],
    )
    .await?;
    catalog::clear(&target);
    Ok(())
}
