use serde_json::{Value, json};

use crate::MihomoError;
use crate::backend::api::VersionInfo;
use crate::sing_box::client::SingBoxTarget;
use crate::sing_box::proto::daemon::{ClashMode, CloseConnectionRequest};

mod proxies;

pub use proxies::{
    group_delay, proxy_batch_delay, proxy_catalog, proxy_delay_window, proxy_group_batch_delay,
    proxy_group_members, select_proxy, unfix_proxy,
};

pub async fn version(target: SingBoxTarget) -> Result<String, MihomoError> {
    Ok(target
        .client()
        .await?
        .get_version(())
        .await?
        .into_inner()
        .version)
}

pub async fn version_info(target: SingBoxTarget) -> Result<VersionInfo, MihomoError> {
    let version = version(target.clone()).await?;
    let supports_core_config = target
        .client()
        .await?
        .get_clash_mode_status(())
        .await
        .is_ok();
    Ok(VersionInfo {
        version,
        supports_core_config,
        supports_core_actions: false,
        supports_core_management: false,
        supports_cache_flush: false,
        supports_memory: true,
        ..Default::default()
    })
}

pub async fn configs(target: SingBoxTarget) -> Result<Value, MihomoError> {
    Ok(json!({ "mode": config_mode(target).await? }))
}

pub async fn config_mode(target: SingBoxTarget) -> Result<String, MihomoError> {
    Ok(target
        .client()
        .await?
        .get_clash_mode_status(())
        .await?
        .into_inner()
        .current_mode)
}

pub async fn set_config_mode(target: SingBoxTarget, mode: String) -> Result<(), MihomoError> {
    target
        .client()
        .await?
        .set_clash_mode(ClashMode { mode })
        .await?;
    Ok(())
}

pub async fn patch_configs(_: SingBoxTarget, _: String) -> Result<(), MihomoError> {
    unsupported("修改核心配置").await
}

pub async fn close_connection(target: SingBoxTarget, id: String) -> Result<(), MihomoError> {
    target
        .client()
        .await?
        .close_connection(CloseConnectionRequest { id })
        .await?;
    Ok(())
}

pub async fn close_all_connections(target: SingBoxTarget) -> Result<(), MihomoError> {
    target.client().await?.close_all_connections(()).await?;
    Ok(())
}

pub async fn close_connections_by_chain(_: SingBoxTarget, _: String) -> Result<(), MihomoError> {
    unsupported("按链路关闭连接").await
}

pub async fn close_connections_by_group(_: SingBoxTarget, _: String) -> Result<(), MihomoError> {
    unsupported("按分组关闭连接").await
}

pub async fn unsupported<T>(message: &str) -> Result<T, MihomoError> {
    Err(MihomoError::Other(format!("sing-box 不支持{message}")))
}
