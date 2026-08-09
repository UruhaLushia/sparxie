use serde_json::{Value, json};

use crate::MihomoError;
use crate::backend::api::VersionInfo;
use crate::sing_box::client::SingBoxTarget;
use crate::sing_box::proto::daemon::{ClashMode, CloseConnectionRequest};

mod diagnostics;
mod proxies;
mod tailscale;

pub use diagnostics::{network_quality_test_stream, outbounds, stun_test_stream};
pub use proxies::{
    group_delay, proxy_batch_delay, proxy_catalog, proxy_delay_window, proxy_group_batch_delay,
    proxy_group_members, select_proxy, unfix_proxy,
};
pub use tailscale::{
    tailscale_logout, tailscale_ping_stream, tailscale_set_exit_node, tailscale_status_stream,
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
    let supports_core_config = match target.client().await?.get_clash_mode_status(()).await {
        Ok(response) => !response.into_inner().mode_list.is_empty(),
        Err(_) => false,
    };
    Ok(VersionInfo {
        version,
        supports_core_config,
        supports_core_actions: false,
        supports_core_management: false,
        supports_cache_flush: false,
        supports_memory: true,
        supports_tailscale: true,
        supports_diagnostics: true,
        ..Default::default()
    })
}

pub async fn configs(target: SingBoxTarget) -> Result<Value, MihomoError> {
    let status = target
        .client()
        .await?
        .get_clash_mode_status(())
        .await?
        .into_inner();
    if status.mode_list.is_empty() {
        return Ok(json!({ "mode-options": [] }));
    }
    Ok(json!({
        "mode": status.current_mode,
        "mode-options": status.mode_list,
    }))
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
