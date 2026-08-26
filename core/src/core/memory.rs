use crate::backend::api::memory::MemoryDetails;

pub(crate) fn memory_details(include_kernel: bool) -> MemoryDetails {
    let mut details = MemoryDetails::default();
    #[cfg(target_os = "android")]
    {
        match super::android::memory_info() {
            Ok(info) => details.app = Some(info),
            Err(error) => details.app_error = Some(error.to_string()),
        }
        if include_kernel {
            if super::is_running() {
                let result = super::go_bridge::query_state("memoryDetails").and_then(|raw| {
                    serde_json::from_value(raw)
                        .map_err(|error| crate::MihomoError::InvalidJson(error.to_string()))
                });
                match result {
                    Ok(info) => details.kernel = Some(info),
                    Err(error) => details.kernel_error = Some(error.to_string()),
                }
            } else {
                details.kernel_error = Some("内核未运行".into());
            }
        }
    }
    #[cfg(not(target_os = "android"))]
    {
        details.app_error = Some("当前平台暂不支持 App 内存明细".into());
        if include_kernel {
            details.kernel_error = Some("当前平台暂不支持内嵌内核".into());
        }
    }
    details
}
