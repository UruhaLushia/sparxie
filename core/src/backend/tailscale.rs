use crate::MihomoError;
use crate::frb_generated::StreamSink;

use super::{BackendTarget, BackendType};

#[derive(Clone, Debug, Default)]
pub struct TailscaleStatus {
    pub endpoints: Vec<TailscaleEndpointStatus>,
}

#[derive(Clone, Debug, Default)]
pub struct TailscaleEndpointStatus {
    pub endpoint_tag: String,
    pub backend_state: String,
    pub auth_url: String,
    pub network_name: String,
    pub magic_dns_suffix: String,
    pub self_peer: Option<TailscalePeer>,
    pub user_groups: Vec<TailscaleUserGroup>,
    pub exit_node: Option<TailscalePeer>,
    pub key_auth: bool,
}

#[derive(Clone, Debug, Default)]
pub struct TailscaleUserGroup {
    pub user_id: i64,
    pub login_name: String,
    pub display_name: String,
    pub profile_pic_url: String,
    pub peers: Vec<TailscalePeer>,
}

#[derive(Clone, Debug, Default)]
pub struct TailscalePeer {
    pub stable_id: String,
    pub host_name: String,
    pub dns_name: String,
    pub os: String,
    pub tailscale_ips: Vec<String>,
    pub online: bool,
    pub exit_node: bool,
    pub exit_node_option: bool,
    pub active: bool,
    pub rx_bytes: i64,
    pub tx_bytes: i64,
    pub key_expiry: i64,
    pub expired: bool,
    pub ssh_host_keys: Vec<String>,
    pub sharee_node: bool,
    pub last_seen: i64,
}

pub async fn tailscale_status_stream(
    target: BackendTarget,
    sink: StreamSink<TailscaleStatus>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::SingBox => {
            crate::sing_box::api::tailscale_status_stream(target.sing_box(), sink).await
        }
        _ => Err(MihomoError::Other("当前后端不支持 Tailscale".into())),
    }
}

pub async fn tailscale_logout(
    target: BackendTarget,
    endpoint_tag: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::SingBox => {
            crate::sing_box::api::tailscale_logout(target.sing_box(), endpoint_tag).await
        }
        _ => Err(MihomoError::Other("当前后端不支持 Tailscale".into())),
    }
}

pub async fn tailscale_set_exit_node(
    target: BackendTarget,
    endpoint_tag: String,
    stable_id: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::SingBox => {
            crate::sing_box::api::tailscale_set_exit_node(
                target.sing_box(),
                endpoint_tag,
                stable_id,
            )
            .await
        }
        _ => Err(MihomoError::Other("当前后端不支持 Tailscale".into())),
    }
}
