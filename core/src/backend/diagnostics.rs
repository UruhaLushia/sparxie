use crate::MihomoError;
use crate::frb_generated::StreamSink;

use super::{BackendTarget, BackendType};

#[derive(Clone, Debug, Default)]
pub struct OutboundEntry {
    pub tag: String,
    pub outbound_type: String,
}

#[derive(Clone, Debug, Default)]
pub struct NetworkQualityProgress {
    pub phase: i32,
    pub download_capacity: i64,
    pub upload_capacity: i64,
    pub download_rpm: i32,
    pub upload_rpm: i32,
    pub idle_latency_ms: i32,
    pub elapsed_ms: i64,
    pub is_final: bool,
    pub error: String,
    pub download_capacity_accuracy: i32,
    pub upload_capacity_accuracy: i32,
    pub download_rpm_accuracy: i32,
    pub upload_rpm_accuracy: i32,
}

#[derive(Clone, Debug, Default)]
pub struct StunTestProgress {
    pub phase: i32,
    pub external_addr: String,
    pub latency_ms: i32,
    pub nat_mapping: i32,
    pub nat_filtering: i32,
    pub is_final: bool,
    pub error: String,
    pub nat_type_supported: bool,
}

pub async fn controller_diagnostics_outbounds(
    target: BackendTarget,
) -> Result<Vec<OutboundEntry>, MihomoError> {
    let load_target = target.clone();
    super::session::diagnostics_outbounds(&target, move || async move {
        match load_target.backend_type {
            BackendType::SingBox => crate::sing_box::api::outbounds(load_target.sing_box()).await,
            _ => Err(unsupported()),
        }
    })
    .await
}

pub async fn controller_network_quality_test_stream(
    target: BackendTarget,
    config_url: String,
    outbound_tag: String,
    serial: bool,
    max_runtime_seconds: i32,
    http3: bool,
    sink: StreamSink<NetworkQualityProgress>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::SingBox => {
            crate::sing_box::api::network_quality_test_stream(
                target.sing_box(),
                config_url,
                outbound_tag,
                serial,
                max_runtime_seconds,
                http3,
                sink,
            )
            .await
        }
        _ => Err(unsupported()),
    }
}

pub async fn controller_stun_test_stream(
    target: BackendTarget,
    server: String,
    outbound_tag: String,
    sink: StreamSink<StunTestProgress>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::SingBox => {
            crate::sing_box::api::stun_test_stream(target.sing_box(), server, outbound_tag, sink)
                .await
        }
        _ => Err(unsupported()),
    }
}

fn unsupported() -> MihomoError {
    MihomoError::Other("当前后端不支持网络诊断工具".into())
}
