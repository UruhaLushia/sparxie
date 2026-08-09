use std::time::Duration;

use reqwest::{Client, Method, Url};
use serde_json::Value;

use crate::MihomoError;

#[derive(Clone, Debug)]
pub struct SurgeTarget {
    pub base_url: String,
    pub key: Option<String>,
    pub allow_insecure: bool,
}

pub struct SurgeClient {
    base: Url,
    key: Option<String>,
    http: Client,
}

impl SurgeTarget {
    pub fn client(&self) -> Result<SurgeClient, MihomoError> {
        SurgeClient::new(&self.base_url, self.key.clone(), self.allow_insecure)
    }
}

impl SurgeClient {
    fn new(base_url: &str, key: Option<String>, allow_insecure: bool) -> Result<Self, MihomoError> {
        let mut base = base_url.trim().to_string();
        if !base.ends_with('/') {
            base.push('/');
        }
        let base = Url::parse(&base).map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
        let http = Client::builder()
            .timeout(Duration::from_secs(15))
            .danger_accept_invalid_certs(allow_insecure)
            .gzip(true)
            .brotli(true)
            .deflate(true)
            .zstd(true)
            .build()
            .map_err(|e| MihomoError::Other(format!("client build: {e}")))?;
        Ok(Self { base, key, http })
    }

    pub async fn get_json(&self, path: &str) -> Result<Value, MihomoError> {
        self.request(Method::GET, path, None).await
    }

    pub async fn post_json(&self, path: &str, body: Value) -> Result<Value, MihomoError> {
        self.request(Method::POST, path, Some(body)).await
    }

    async fn request(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, MihomoError> {
        let url = self
            .base
            .join(path.trim_start_matches('/'))
            .map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
        let mut req = self.http.request(method, url);
        if let Some(key) = self.key.as_deref().filter(|s| !s.is_empty()) {
            req = req.header("X-Key", key);
        }
        if let Some(body) = body {
            req = req.json(&body);
        }
        let resp = req.send().await?;
        let status = resp.status();
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| MihomoError::Network(format!("read body: {e}")))?;
        if !status.is_success() {
            return Err(MihomoError::Upstream {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        if bytes.is_empty() {
            return Ok(serde_json::json!({"ok": true}));
        }
        serde_json::from_slice(&bytes).map_err(|e| MihomoError::InvalidJson(e.to_string()))
    }
}

pub fn target_key(target: &SurgeTarget) -> String {
    format!(
        "{}|{}",
        target.base_url.trim_end_matches('/'),
        target.key.as_deref().unwrap_or("")
    )
}
