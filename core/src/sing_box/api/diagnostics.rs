use crate::MihomoError;
use crate::backend::api::diagnostics::{NetworkQualityProgress, OutboundEntry, StunTestProgress};
use crate::frb_generated::StreamSink;
use crate::sing_box::client::SingBoxTarget;
use crate::sing_box::proto::daemon::{
    NetworkQualityTestProgress as PbQualityProgress, NetworkQualityTestRequest,
    StunTestProgress as PbStunProgress, StunTestRequest,
};

pub async fn outbounds(target: SingBoxTarget) -> Result<Vec<OutboundEntry>, MihomoError> {
    let mut stream = target
        .client()
        .await?
        .subscribe_outbounds(())
        .await?
        .into_inner();
    let list = stream.message().await?.unwrap_or_default();
    Ok(list
        .outbounds
        .into_iter()
        .map(|item| OutboundEntry {
            tag: item.tag,
            outbound_type: item.r#type,
        })
        .collect())
}

pub async fn network_quality_test_stream(
    target: SingBoxTarget,
    config_url: String,
    outbound_tag: String,
    serial: bool,
    max_runtime_seconds: i32,
    http3: bool,
    sink: StreamSink<NetworkQualityProgress>,
) -> Result<(), MihomoError> {
    let mut stream = target
        .client()
        .await?
        .start_network_quality_test(NetworkQualityTestRequest {
            config_url,
            outbound_tag,
            serial,
            max_runtime_seconds,
            http3,
        })
        .await?
        .into_inner();
    while let Some(update) = stream.message().await? {
        let done = update.is_final;
        if sink.add(quality_from_proto(update)).is_err() || done {
            break;
        }
    }
    Ok(())
}

pub async fn stun_test_stream(
    target: SingBoxTarget,
    server: String,
    outbound_tag: String,
    sink: StreamSink<StunTestProgress>,
) -> Result<(), MihomoError> {
    let mut stream = target
        .client()
        .await?
        .start_stun_test(StunTestRequest {
            server,
            outbound_tag,
        })
        .await?
        .into_inner();
    while let Some(update) = stream.message().await? {
        let done = update.is_final;
        if sink.add(stun_from_proto(update)).is_err() || done {
            break;
        }
    }
    Ok(())
}

fn quality_from_proto(update: PbQualityProgress) -> NetworkQualityProgress {
    NetworkQualityProgress {
        phase: update.phase,
        download_capacity: update.download_capacity,
        upload_capacity: update.upload_capacity,
        download_rpm: update.download_rpm,
        upload_rpm: update.upload_rpm,
        idle_latency_ms: update.idle_latency_ms,
        elapsed_ms: update.elapsed_ms,
        is_final: update.is_final,
        error: update.error,
        download_capacity_accuracy: update.download_capacity_accuracy,
        upload_capacity_accuracy: update.upload_capacity_accuracy,
        download_rpm_accuracy: update.download_rpm_accuracy,
        upload_rpm_accuracy: update.upload_rpm_accuracy,
    }
}

fn stun_from_proto(update: PbStunProgress) -> StunTestProgress {
    StunTestProgress {
        phase: update.phase,
        external_addr: update.external_addr,
        latency_ms: update.latency_ms,
        nat_mapping: update.nat_mapping,
        nat_filtering: update.nat_filtering,
        is_final: update.is_final,
        error: update.error,
        nat_type_supported: update.nat_type_supported,
    }
}
