pub(crate) mod catalog;
pub(crate) mod delay;
mod value;

pub use catalog::*;
pub use delay::*;

use reqwest::Method;
use serde_json::json;

use crate::MihomoError;
use crate::utils::regex;

use super::{MihomoTarget, urlencode};

/// `GET /proxies` — full proxy + group catalog. Optional regex filters keep
/// the wire small when the controller is remote.
pub async fn proxies(
    target: MihomoTarget,
    name_pattern: Option<String>,
    type_pattern: Option<String>,
    groups_only: bool,
) -> Result<String, MihomoError> {
    let mut raw = target.client()?.get_json("proxies").await?;
    let name_re = regex::compile(name_pattern.as_deref())?;
    let type_re = regex::compile(type_pattern.as_deref())?;
    if let Some(map) = raw.get_mut("proxies").and_then(|v| v.as_object_mut()) {
        map.retain(|key, value| {
            if let Some(re) = &name_re
                && !re.is_match(key)
            {
                return false;
            }
            let ty = value
                .get("type")
                .and_then(|t| t.as_str())
                .unwrap_or_default();
            if let Some(re) = &type_re
                && !re.is_match(ty)
            {
                return false;
            }
            if groups_only {
                let has_all = value
                    .get("all")
                    .and_then(|v| v.as_array())
                    .map(|a| !a.is_empty())
                    .unwrap_or(false);
                if !has_all {
                    return false;
                }
            }
            true
        });
    }
    Ok(raw.to_string())
}

pub async fn proxy_detail(target: MihomoTarget, name: String) -> Result<String, MihomoError> {
    if let Some(detail) = catalog::cached_proxy_detail(&target, &name).await? {
        return Ok(detail);
    }
    let path = format!("proxies/{}", urlencode(&name));
    Ok(target.client()?.get_json(&path).await?.to_string())
}

pub async fn select_proxy(
    target: MihomoTarget,
    group: String,
    name: String,
) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::PUT,
            &format!("proxies/{}", urlencode(&group)),
            Some(json!({ "name": name })),
        )
        .await?;
    Ok(())
}

/// `DELETE /proxies/{name}` — clears the "fixed" selection on a non-Selector group.
pub async fn unfix_proxy(target: MihomoTarget, name: String) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::DELETE,
            &format!("proxies/{}", urlencode(&name)),
            None,
        )
        .await?;
    Ok(())
}
