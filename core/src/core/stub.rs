use crate::MihomoError;
use crate::backend::api::core::CoreConfig;

pub(crate) async fn prepare_and_start(
    _config: CoreConfig,
    _run_id: u64,
) -> Result<(), MihomoError> {
    Err(MihomoError::Other("当前平台暂不支持本地引擎".into()))
}

pub(crate) async fn teardown() {}
