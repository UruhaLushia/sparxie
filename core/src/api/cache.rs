use reqwest::Method;

use crate::MihomoError;

use super::MihomoTarget;

/// `POST /cache/fakeip/flush` — clear the FakeIP pool.
pub async fn flush_fakeip(target: MihomoTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(Method::POST, "cache/fakeip/flush", None)
        .await?;
    Ok(())
}

/// `POST /cache/dns/flush` — clear the DNS cache.
pub async fn flush_dns(target: MihomoTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(Method::POST, "cache/dns/flush", None)
        .await?;
    Ok(())
}
