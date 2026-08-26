use crate::MihomoError;

#[derive(Clone, Debug, serde::Deserialize)]
pub struct AppMemoryInfo {
    pub pss: u64,
    pub private_dirty: u64,
    pub private_clean: u64,
    pub shared_dirty: u64,
    pub shared_clean: u64,
    pub rss: Option<u64>,
    pub peak_rss: Option<u64>,
    pub virtual_size: Option<u64>,
    pub swap_pss: Option<u64>,
    pub java_heap: Option<u64>,
    pub native_heap: Option<u64>,
    pub graphics: Option<u64>,
    pub code: Option<u64>,
    pub stack: Option<u64>,
    pub private_other: Option<u64>,
    pub system: Option<u64>,
    pub java_allocated: u64,
    pub java_capacity: u64,
    pub java_limit: u64,
    pub native_allocated: u64,
    pub native_capacity: u64,
    pub native_free: u64,
}

#[derive(Clone, Debug, serde::Deserialize)]
pub struct KernelMemoryInfo {
    pub heap_alloc: u64,
    pub heap_inuse: u64,
    pub heap_idle: u64,
    pub heap_released: u64,
    pub stack_inuse: u64,
    pub sys: u64,
    pub gc_count: u32,
    pub goroutines: u32,
}

#[derive(Clone, Debug, Default)]
pub struct MemoryDetails {
    pub app: Option<AppMemoryInfo>,
    pub kernel: Option<KernelMemoryInfo>,
    pub app_error: Option<String>,
    pub kernel_error: Option<String>,
}

/// On-demand diagnostics. App process totals include the embedded Go runtime.
pub async fn memory_details(include_kernel: bool) -> Result<MemoryDetails, MihomoError> {
    tokio::task::spawn_blocking(move || crate::core::memory_details(include_kernel))
        .await
        .map_err(|error| MihomoError::Other(format!("读取内存信息失败:{error}")))
}
