use crate::MihomoError;
use crate::backend::api::MemorySample;
use crate::surge_controller::client::SurgeControllerTarget;

pub(super) async fn memory_sample(
    target: SurgeControllerTarget,
) -> Result<MemorySample, MihomoError> {
    let performance = target.request(["dump", "performance"]).await?;
    let inuse = performance
        .get("memory-bytes")
        .and_then(serde_json::Value::as_u64)
        .ok_or_else(|| MihomoError::Other("Surge 性能指标缺少 memory-bytes".into()))?;
    Ok(MemorySample {
        inuse,
        ..Default::default()
    })
}
