use crate::MihomoError;
use crate::backend::api::tailscale::{
    TailscaleEndpointStatus, TailscalePeer, TailscaleStatus, TailscaleUserGroup,
};
use crate::frb_generated::StreamSink;
use crate::sing_box::client::SingBoxTarget;
use crate::sing_box::proto::daemon::{
    SetTailscaleExitNodeRequest, TailscaleEndpointStatus as PbEndpointStatus,
    TailscaleLogoutRequest, TailscalePeer as PbPeer, TailscaleUserGroup as PbUserGroup,
};

pub async fn tailscale_status_stream(
    target: SingBoxTarget,
    sink: StreamSink<TailscaleStatus>,
) -> Result<(), MihomoError> {
    let response = match target.client().await?.subscribe_tailscale_status(()).await {
        Ok(response) => response,
        Err(status) if status.code() == tonic::Code::NotFound => {
            let _ = sink.add(TailscaleStatus::default());
            return Ok(());
        }
        Err(status) => return Err(status.into()),
    };
    let mut stream = response.into_inner();
    loop {
        match stream.message().await {
            Ok(Some(update)) => {
                if sink.add(status_from_proto(update.endpoints)).is_err() {
                    break;
                }
            }
            Ok(None) => break,
            Err(status) if status.code() == tonic::Code::NotFound => {
                let _ = sink.add(TailscaleStatus::default());
                break;
            }
            Err(status) => return Err(status.into()),
        }
    }
    Ok(())
}

pub async fn tailscale_set_exit_node(
    target: SingBoxTarget,
    endpoint_tag: String,
    stable_id: String,
) -> Result<(), MihomoError> {
    target
        .client()
        .await?
        .set_tailscale_exit_node(SetTailscaleExitNodeRequest {
            endpoint_tag,
            stable_id,
        })
        .await?;
    Ok(())
}

pub async fn tailscale_logout(
    target: SingBoxTarget,
    endpoint_tag: String,
) -> Result<(), MihomoError> {
    target
        .client()
        .await?
        .tailscale_logout(TailscaleLogoutRequest { endpoint_tag })
        .await?;
    Ok(())
}

fn status_from_proto(endpoints: Vec<PbEndpointStatus>) -> TailscaleStatus {
    TailscaleStatus {
        endpoints: endpoints.into_iter().map(endpoint_from_proto).collect(),
    }
}

fn endpoint_from_proto(endpoint: PbEndpointStatus) -> TailscaleEndpointStatus {
    TailscaleEndpointStatus {
        endpoint_tag: endpoint.endpoint_tag,
        backend_state: endpoint.backend_state,
        auth_url: endpoint.auth_url,
        network_name: endpoint.network_name,
        magic_dns_suffix: endpoint.magic_dns_suffix,
        self_peer: endpoint.self_.map(peer_from_proto),
        user_groups: endpoint
            .user_groups
            .into_iter()
            .map(user_group_from_proto)
            .collect(),
        exit_node: endpoint.exit_node.map(peer_from_proto),
        key_auth: endpoint.key_auth,
    }
}

fn user_group_from_proto(group: PbUserGroup) -> TailscaleUserGroup {
    TailscaleUserGroup {
        user_id: group.user_id,
        login_name: group.login_name,
        display_name: group.display_name,
        profile_pic_url: group.profile_pic_url,
        peers: group.peers.into_iter().map(peer_from_proto).collect(),
    }
}

fn peer_from_proto(peer: PbPeer) -> TailscalePeer {
    TailscalePeer {
        stable_id: peer.stable_id,
        host_name: peer.host_name,
        dns_name: peer.dns_name,
        os: peer.os,
        tailscale_ips: peer.tailscale_i_ps,
        online: peer.online,
        exit_node: peer.exit_node,
        exit_node_option: peer.exit_node_option,
        active: peer.active,
        rx_bytes: peer.rx_bytes,
        tx_bytes: peer.tx_bytes,
        key_expiry: peer.key_expiry,
        expired: peer.expired,
        ssh_host_keys: peer.ssh_host_keys,
        sharee_node: peer.sharee_node,
        last_seen: peer.last_seen,
    }
}
