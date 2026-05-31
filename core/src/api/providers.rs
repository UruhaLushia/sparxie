use reqwest::Method;

use crate::error::MihomoError;

use super::{MihomoTarget, urlencode};

// ---------- proxy providers ----------------------------------------------

pub async fn proxy_providers(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target
        .client()?
        .get_json("providers/proxies")
        .await?
        .to_string())
}

pub async fn proxy_provider_update(target: MihomoTarget, name: String) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::PUT,
            &format!("providers/proxies/{}", urlencode(&name)),
            None,
        )
        .await?;
    Ok(())
}

pub async fn proxy_provider_healthcheck(
    target: MihomoTarget,
    name: String,
) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::GET,
            &format!("providers/proxies/{}/healthcheck", urlencode(&name)),
            None,
        )
        .await?;
    Ok(())
}

// ---------- rule providers -----------------------------------------------

pub async fn rule_providers(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target
        .client()?
        .get_json("providers/rules")
        .await?
        .to_string())
}

pub async fn rule_provider_update(target: MihomoTarget, name: String) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::PUT,
            &format!("providers/rules/{}", urlencode(&name)),
            None,
        )
        .await?;
    Ok(())
}
