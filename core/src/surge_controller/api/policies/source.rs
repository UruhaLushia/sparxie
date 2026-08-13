use std::sync::{Arc, OnceLock};
use std::time::Instant;

use serde_json::Value;

use crate::MihomoError;
use crate::cache::target::ActiveTargetCache;
use crate::surge_controller::api::value_string;
use crate::surge_controller::client::{SurgeControllerTarget, target_key, with_unary_connection};

use super::CACHE_TTL;
use super::parse::{group_meta, policy_group_names, source_members};

pub(super) struct CatalogSource {
    pub(super) groups: Vec<SourceGroup>,
    expires_at: Instant,
}

pub(super) struct SourceGroup {
    pub(super) name: String,
    pub(super) meta: GroupMeta,
    pub(super) members: Arc<[SourceMember]>,
}

pub(crate) struct SourceMember {
    pub(crate) name: String,
    pub(crate) proxy_type: String,
    pub(crate) delay_key: Option<String>,
    pub(crate) test_key: String,
    pub(crate) usage: Option<i32>,
}

#[derive(Default)]
pub(super) struct GroupMeta {
    pub(super) proxy_type: String,
    pub(super) selectable: bool,
    pub(super) auto: bool,
    pub(super) hidden: bool,
    pub(super) icon: String,
    pub(super) detail: String,
}

fn cache() -> &'static ActiveTargetCache<Arc<CatalogSource>> {
    static CACHE: OnceLock<ActiveTargetCache<Arc<CatalogSource>>> = OnceLock::new();
    CACHE.get_or_init(ActiveTargetCache::new)
}

pub(super) fn clear(target: &SurgeControllerTarget) {
    cache().clear(&target_key(target));
}

pub(super) async fn load(
    target: &SurgeControllerTarget,
) -> Result<Arc<CatalogSource>, MihomoError> {
    let key = target_key(target);
    cache().invalidate_if(&key, |source| source.expires_at <= Instant::now());
    let load_target = target.clone();
    cache()
        .load(&key, false, move || async move {
            with_unary_connection(&load_target, |connection| {
                Box::pin(async move {
                    let policies = connection.request(["dump", "policy"]).await?;
                    let member_map = connection
                        .request(["dump", "policy-group-sub-policies"])
                        .await?;
                    let smart_info = connection
                        .request(["dump", "smart-group-info"])
                        .await
                        .unwrap_or_default();
                    let map = member_map.get("map").unwrap_or(&member_map);
                    let local_proxies = super::parse::proxy_names(&policies);
                    let mut groups = Vec::new();
                    for name in policy_group_names(&policies) {
                        let raw = connection
                            .request(["show-policy".into(), name.clone()])
                            .await?;
                        let detail = value_string(raw.get("result")).unwrap_or_default();
                        let members = map
                            .get(&name)
                            .and_then(Value::as_array)
                            .map(|items| {
                                source_members(items, &local_proxies, smart_info.get(&name))
                            })
                            .unwrap_or_default()
                            .into();
                        groups.push(SourceGroup {
                            name,
                            meta: group_meta(detail),
                            members,
                        });
                    }
                    Ok(Arc::new(CatalogSource {
                        groups,
                        expires_at: Instant::now() + CACHE_TTL,
                    }))
                })
            })
            .await
        })
        .await
}
