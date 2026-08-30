use crate::MihomoError;
use crate::backend::api::MemorySample;
use crate::surge::client::SurgeTarget;

pub(super) async fn memory_sample(target: SurgeTarget) -> Result<MemorySample, MihomoError> {
    let metrics = target.client()?.get_text("v1/metrics").await?;
    parse_memory(&metrics)
}

pub(super) fn parse_memory(metrics: &str) -> Result<MemorySample, MihomoError> {
    let value = metrics
        .lines()
        .find_map(|line| {
            let mut fields = line.split_whitespace();
            match (fields.next(), fields.next()) {
                (Some("surge_memory_bytes"), Some(value)) => Some(value),
                _ => None,
            }
        })
        .ok_or_else(|| MihomoError::Other("Surge 指标缺少 surge_memory_bytes".into()))?
        .parse::<f64>()
        .map_err(|e| MihomoError::Other(format!("Surge 内存指标无效：{e}")))?;
    if !value.is_finite() || value < 0.0 || value > u64::MAX as f64 {
        return Err(MihomoError::Other("Surge 内存指标无效".into()));
    }
    Ok(MemorySample {
        inuse: value as u64,
        ..Default::default()
    })
}
