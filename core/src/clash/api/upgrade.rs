use reqwest::Method;

use crate::MihomoError;

use super::{MihomoTarget, urlencode};

/// `POST /upgrade/` — pull the latest mihomo core for the requested release
/// channel and **restart the upstream process** on success. Forbidden when
/// the controller was started with `--embed`.
pub async fn upgrade_core(
    target: MihomoTarget,
    channel: Option<String>,
    force: bool,
) -> Result<(), MihomoError> {
    let mut path = String::from("upgrade");
    let mut params = Vec::new();
    if let Some(channel) = channel
        && !channel.is_empty()
    {
        params.push(format!("channel={}", urlencode(&channel)));
    }
    if force {
        params.push("force=true".into());
    }
    if !params.is_empty() {
        path.push('?');
        path.push_str(&params.join("&"));
    }
    target.client()?.forward(Method::POST, &path, None).await?;
    Ok(())
}

/// `POST /upgrade/ui` — fetch the latest dashboard bundle to mihomo's
/// `external-ui` directory.
pub async fn upgrade_ui(target: MihomoTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(Method::POST, "upgrade/ui", None)
        .await?;
    Ok(())
}

/// `POST /upgrade/geo` — refresh GeoIP / GeoSite databases. Forbidden on
/// `--embed`.
pub async fn upgrade_geo(target: MihomoTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(Method::POST, "upgrade/geo", None)
        .await?;
    Ok(())
}

/// `POST /restart` — restart the upstream mihomo process. Forbidden on
/// `--embed`. Returns immediately (the actual exec happens asynchronously),
/// so subsequent calls will fail until mihomo is reachable again.
pub async fn restart_core(target: MihomoTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(Method::POST, "restart", None)
        .await?;
    Ok(())
}
