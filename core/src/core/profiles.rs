use crate::MihomoError;
use crate::backend::api::core::{AppWindow, CoreConfigProfile};

#[cfg(target_os = "android")]
use super::{android, configs, go_bridge, is_running};

#[cfg(not(target_os = "android"))]
fn unsupported<T>() -> Result<T, MihomoError> {
    Err(MihomoError::Other("当前平台暂不支持本地引擎".into()))
}

#[cfg(target_os = "android")]
async fn reload_active() -> Result<(), MihomoError> {
    let _operation = super::core().operation.lock().await;
    if !is_running() {
        return Ok(());
    }
    tokio::task::spawn_blocking(|| {
        let path = configs::active_path()?;
        let path = path
            .to_str()
            .ok_or_else(|| MihomoError::Other("配置路径无效".into()))?;
        go_bridge::reload_config(path)
    })
    .await
    .map_err(|error| MihomoError::Other(format!("重载配置任务失败:{error}")))?
}

#[cfg(target_os = "android")]
pub(crate) async fn config_reload_active() -> Result<(), MihomoError> {
    let _profiles = super::core().profile_operation.lock().await;
    reload_active().await
}

pub(crate) async fn config_list() -> Result<Vec<CoreConfigProfile>, MihomoError> {
    #[cfg(target_os = "android")]
    {
        let _profiles = super::core().profile_operation.lock().await;
        return tokio::task::spawn_blocking(configs::list)
            .await
            .map_err(|error| MihomoError::Other(format!("读取配置任务失败:{error}")))?;
    }
    #[cfg(not(target_os = "android"))]
    unsupported()
}

pub(crate) async fn config_import(
    url: &str,
    text: &str,
    name: &str,
    user_agent: &str,
) -> Result<CoreConfigProfile, MihomoError> {
    #[cfg(target_os = "android")]
    {
        let _profiles = super::core().profile_operation.lock().await;
        let profile = configs::import(url, text, name, user_agent).await?;
        if profile.active {
            reload_active().await?;
        }
        return Ok(profile);
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = (url, text, name, user_agent);
        unsupported()
    }
}

pub(crate) async fn config_set_active(id: &str) -> Result<(), MihomoError> {
    #[cfg(target_os = "android")]
    {
        let _profiles = super::core().profile_operation.lock().await;
        let id = id.to_string();
        tokio::task::spawn_blocking(move || configs::set_active(&id))
            .await
            .map_err(|error| MihomoError::Other(format!("切换配置任务失败:{error}")))??;
        return reload_active().await;
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = id;
        unsupported()
    }
}

pub(crate) async fn config_delete(id: &str) -> Result<(), MihomoError> {
    #[cfg(target_os = "android")]
    {
        let _profiles = super::core().profile_operation.lock().await;
        let id = id.to_string();
        let active_changed = tokio::task::spawn_blocking(move || configs::delete(&id))
            .await
            .map_err(|error| MihomoError::Other(format!("删除配置任务失败:{error}")))??;
        if active_changed {
            reload_active().await?;
        }
        return Ok(());
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = id;
        unsupported()
    }
}

pub(crate) async fn config_edit(
    id: &str,
    name: &str,
    url: &str,
    user_agent: &str,
) -> Result<(), MihomoError> {
    #[cfg(target_os = "android")]
    {
        let _profiles = super::core().profile_operation.lock().await;
        let (id, name, url, user_agent) = (
            id.to_string(),
            name.to_string(),
            url.to_string(),
            user_agent.to_string(),
        );
        return tokio::task::spawn_blocking(move || configs::edit(&id, &name, &url, &user_agent))
            .await
            .map_err(|error| MihomoError::Other(format!("编辑配置任务失败:{error}")))?;
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = (id, name, url, user_agent);
        unsupported()
    }
}

pub(crate) async fn config_update(id: &str) -> Result<(), MihomoError> {
    #[cfg(target_os = "android")]
    {
        let _profiles = super::core().profile_operation.lock().await;
        configs::update(id).await?;
        let active = configs::active_profile().map(|(profile, _)| profile.id)?;
        if active == id {
            reload_active().await?;
        }
        return Ok(());
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = id;
        unsupported()
    }
}

#[cfg(target_os = "android")]
pub(crate) async fn list_apps_window(query: &str, offset: u32, limit: u32) -> AppWindow {
    let query = query.to_string();
    tokio::task::spawn_blocking(move || android::list_apps_window(&query, offset, limit))
        .await
        .unwrap_or_default()
}

#[cfg(not(target_os = "android"))]
pub(crate) async fn list_apps_window(_query: &str, _offset: u32, _limit: u32) -> AppWindow {
    AppWindow::default()
}
