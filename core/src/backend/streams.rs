use std::time::Duration;

use futures_util::StreamExt;
use tokio_stream::wrappers::BroadcastStream;

use crate::MihomoError;
use crate::frb_generated::StreamSink;

use super::{BackendTarget, BackendType, LogEntry, MemorySample, TrafficSample};

pub async fn traffic_stream(
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
    }
}

pub async fn memory_stream(
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
    }
}

pub async fn logs_stream(
    target: BackendTarget,
    level: String,
    sink: StreamSink<Vec<LogEntry>>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            let (snapshot, rx) =
                crate::clash::state::logs::subscribe(target.clash(), &level).await?;
            if !snapshot.is_empty()
                && sink
                    .add(snapshot.into_iter().map(Into::into).collect())
                    .is_err()
            {
                return Ok(());
            }
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(sample) = item else { continue };
                if sink.add(vec![sample.into()]).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::Surge => {
            let (snapshot, rx) =
                crate::surge::state::logs::subscribe(target.surge(), &level).await?;
            if !snapshot.is_empty() && sink.add(snapshot).is_err() {
                return Ok(());
            }
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(sample) = item else { continue };
                if sink.add(vec![sample]).is_err() {
                    break;
                }
            }
            Ok(())
        }
    }
}

pub async fn clear_logs(target: BackendTarget, level: String) {
    match target.backend_type {
        BackendType::Clash => crate::clash::state::logs::clear(target.clash(), &level).await,
        BackendType::Surge => crate::surge::state::logs::clear(target.surge(), &level).await,
    }
}
