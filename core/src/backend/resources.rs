use crate::MihomoError;

pub fn init_cache(
    cache_dir: String,
    allow_insecure_online_resources: bool,
) -> Result<(), MihomoError> {
    crate::clash::api::init_cache(cache_dir, allow_insecure_online_resources)
}

pub fn set_online_resource_allow_insecure(allow_insecure: bool) -> Result<(), MihomoError> {
    crate::clash::api::set_online_resource_allow_insecure(allow_insecure)
}

pub async fn fetch_icon(url: String) -> Result<Vec<u8>, MihomoError> {
    crate::clash::api::fetch_icon(url).await
}

pub async fn fetch_process_icon(
    path: String,
    size: Option<u32>,
) -> Result<Option<Vec<u8>>, MihomoError> {
    crate::clash::api::fetch_process_icon(path, size).await
}

pub async fn cached_process_icon(
    key: String,
    size: Option<u32>,
) -> Result<Option<Vec<u8>>, MihomoError> {
    crate::clash::api::cached_process_icon(key, size).await
}

pub async fn store_process_icon(key: String, bytes: Vec<u8>) -> Result<(), MihomoError> {
    crate::clash::api::store_process_icon(key, bytes).await
}

pub async fn fetch_process_name(path: String) -> Result<Option<String>, MihomoError> {
    crate::clash::api::fetch_process_name(path).await
}

pub async fn cached_process_name(key: String) -> Result<Option<String>, MihomoError> {
    crate::clash::api::cached_process_name(key).await
}

pub async fn store_process_name(key: String, name: String) -> Result<(), MihomoError> {
    crate::clash::api::store_process_name(key, name).await
}

pub fn reset_process_icon_misses() {
    crate::clash::api::reset_process_icon_misses()
}

pub async fn icon_cache_size() -> Result<u64, MihomoError> {
    crate::clash::api::icon_cache_size().await
}

pub async fn clear_icon_cache() -> Result<(), MihomoError> {
    crate::clash::api::clear_icon_cache().await
}

pub async fn system_font_families() -> Vec<String> {
    crate::clash::api::system_font_families().await
}
