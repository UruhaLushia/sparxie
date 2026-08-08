use std::time::Duration;

use futures_util::StreamExt;
use tokio_stream::wrappers::BroadcastStream;

use crate::MihomoError;
use crate::frb_generated::StreamSink;

use super::{BackendTarget, BackendType, LogWindow, LogsFrame, MemorySample, TrafficSample};

pub async fn controller_traffic_stream(
    target: BackendTarget,
    sink: StreamSink<TrafficSample>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            let rx = crate::clash::state::traffic::traffic_subscribe(target.clash()).await?;
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(sample) = item else { continue };
                if sink.add(sample.into()).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::Surge => loop {
            let sample = crate::surge::api::traffic_sample(target.surge()).await?;
            if sink.add(sample).is_err() {
                break Ok(());
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        },
        BackendType::SingBox => {
            let rx = crate::sing_box::state::status::subscribe(target.sing_box(), 1000).await?;
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok((traffic, _)) = item else { continue };
                if sink.add(traffic).is_err() {
                    break;
                }
            }
            Ok(())
        }
    }
}

pub async fn controller_memory_stream(
    target: BackendTarget,
    sink: StreamSink<MemorySample>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            let rx = crate::clash::state::traffic::memory_subscribe(target.clash()).await?;
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(sample) = item else { continue };
                if sink.add(sample.into()).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::Surge => {
            let _ = sink;
            crate::surge::api::unsupported("内存流").await
        }
        BackendType::SingBox => {
            let rx = crate::sing_box::state::status::subscribe(target.sing_box(), 1000).await?;
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok((_, memory)) = item else { continue };
                if sink.add(memory).is_err() {
                    break;
                }
            }
            Ok(())
        }
    }
}

pub async fn controller_logs_stream(
    target: BackendTarget,
    info_capacity: u32,
    sink: StreamSink<LogsFrame>,
) -> Result<(), MihomoError> {
    let info_capacity = info_capacity.max(1) as usize;
    match target.backend_type {
        BackendType::Clash => {
            let (frame, rx) =
                crate::clash::state::logs::subscribe(target.clash(), info_capacity).await?;
            if sink.add(frame).is_err() {
                return Ok(());
            }
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(frame) = item else { continue };
                if sink.add(frame).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::Surge => {
            let (frame, rx) =
                crate::surge::state::logs::subscribe(target.surge(), info_capacity).await?;
            if sink.add(frame).is_err() {
                return Ok(());
            }
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(frame) = item else { continue };
                if sink.add(frame).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::SingBox => {
            let (frame, rx) =
                crate::sing_box::state::logs::subscribe(target.sing_box(), info_capacity).await?;
            if sink.add(frame).is_err() {
                return Ok(());
            }
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(frame) = item else { continue };
                if sink.add(frame).is_err() {
                    break;
                }
            }
            Ok(())
        }
    }
}

pub async fn controller_fetch_logs_window(
    target: BackendTarget,
    level: String,
    query: String,
    offset: u32,
    limit: u32,
    from_end: bool,
    anchor_id: u64,
) -> LogWindow {
    let offset = offset as usize;
    let limit = limit.max(1) as usize;
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::state::logs::fetch_window(
                target.clash(),
                &level,
                &query,
                offset,
                limit,
                from_end,
                anchor_id,
            )
            .await
        }
        BackendType::Surge => {
            crate::surge::state::logs::fetch_window(
                target.surge(),
                &level,
                &query,
                offset,
                limit,
                from_end,
                anchor_id,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::state::logs::fetch_window(
                target.sing_box(),
                &level,
                &query,
                offset,
                limit,
                from_end,
                anchor_id,
            )
            .await
        }
    }
}

pub async fn controller_clear_logs(target: BackendTarget) {
    match target.backend_type {
        BackendType::Clash => crate::clash::state::logs::clear(target.clash()).await,
        BackendType::Surge => crate::surge::state::logs::clear(target.surge()).await,
        BackendType::SingBox => {
            let _ = crate::sing_box::state::logs::clear(target.sing_box()).await;
        }
    }
}
