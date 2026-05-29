use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use reqwest::{Client, Method, Url};
use serde_json::Value;
use tokio::net::TcpStream;
use tokio_tungstenite::{
    Connector, MaybeTlsStream, WebSocketStream, connect_async,
    connect_async_tls_with_config,
    tungstenite::{client::IntoClientRequest, http::HeaderValue, protocol::Message},
};

use crate::error::MihomoError;

/// Internal mihomo HTTP client. Held only on the Rust side; Dart never sees it.
pub struct MihomoClient {
    pub base: Url,
    pub secret: Option<String>,
    pub http: Client,
    /// Skip TLS certificate validation (self-signed / mismatched-host https).
    allow_insecure: bool,
}

pub type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

impl MihomoClient {
    pub fn new(
        base_url: &str,
        secret: Option<String>,
        allow_insecure: bool,
    ) -> Result<Self, MihomoError> {
        let base =
            Url::parse(base_url).map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
        let http = Client::builder()
            .timeout(Duration::from_secs(15))
            .danger_accept_invalid_certs(allow_insecure)
            .build()
            .map_err(|e| MihomoError::Other(format!("client build: {e}")))?;
        Ok(Self {
            base,
            secret,
            http,
            allow_insecure,
        })
    }

    pub fn url(&self, path: &str) -> Result<Url, MihomoError> {
        self.base
            .join(path.trim_start_matches('/'))
            .map_err(|e| MihomoError::InvalidUrl(e.to_string()))
    }

    /// http(s)://host/<path> → ws(s)://host/<path>, preserving query string.
    fn ws_url(&self, path: &str) -> Result<Url, MihomoError> {
        let mut url = self.url(path)?;
        let new_scheme = match url.scheme() {
            "http" => "ws",
            "https" => "wss",
            "ws" | "wss" => return Ok(url),
            other => {
                return Err(MihomoError::InvalidUrl(format!(
                    "unsupported scheme `{other}` for websocket upgrade"
                )));
            }
        };
        url.set_scheme(new_scheme)
            .map_err(|_| MihomoError::InvalidUrl("scheme rewrite failed".into()))?;
        Ok(url)
    }

    fn auth(&self, mut req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        if let Some(secret) = &self.secret {
            req = req.bearer_auth(secret);
        }
        req
    }

    pub async fn get_json(&self, path: &str) -> Result<Value, MihomoError> {
        let req = self.auth(self.http.get(self.url(path)?));
        let resp = req.send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(MihomoError::Upstream {
                status: status.as_u16(),
                body,
            });
        }
        resp.json::<Value>()
            .await
            .map_err(|e| MihomoError::InvalidJson(e.to_string()))
    }

    pub async fn forward(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, MihomoError> {
        let mut req = self.http.request(method, self.url(path)?);
        if let Some(body) = body {
            req = req.json(&body);
        }
        let resp = self.auth(req).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(MihomoError::Upstream {
                status: status.as_u16(),
                body,
            });
        }
        if status == reqwest::StatusCode::NO_CONTENT {
            return Ok(serde_json::json!({"ok": true}));
        }
        resp.json::<Value>()
            .await
            .or_else(|_| Ok(serde_json::json!({"ok": true})))
    }

    /// Open a WebSocket connection to a mihomo streaming endpoint.
    ///
    /// `path` is the same path you'd pass to `get_json` (e.g. `traffic`,
    /// `connections?interval=1000`). The secret is forwarded both as a
    /// `?token=` query (the only auth Browser-WS allows) AND as an
    /// `Authorization: Bearer ...` header so non-browser servers also accept.
    pub async fn open_ws(&self, path: &str) -> Result<WsStream, MihomoError> {
        let mut url = self.ws_url(path)?;
        if let Some(secret) = &self.secret {
            url.query_pairs_mut().append_pair("token", secret);
        }

        let mut request = url
            .as_str()
            .into_client_request()
            .map_err(|e| MihomoError::InvalidUrl(format!("ws request: {e}")))?;
        if let Some(secret) = &self.secret {
            let value = HeaderValue::from_str(&format!("Bearer {secret}"))
                .map_err(|e| MihomoError::Other(format!("ws auth header: {e}")))?;
            request.headers_mut().insert("authorization", value);
        }

        let (stream, response) = if self.allow_insecure {
            connect_async_tls_with_config(
                request,
                None,
                false,
                Some(insecure_ws_connector()),
            )
            .await
            .map_err(|e| MihomoError::Other(format!("websocket connect: {e}")))?
        } else {
            connect_async(request)
                .await
                .map_err(|e| MihomoError::Other(format!("websocket connect: {e}")))?
        };
        if !response.status().is_informational() && !response.status().is_success() {
            return Err(MihomoError::Upstream {
                status: response.status().as_u16(),
                body: format!("ws handshake returned {}", response.status()),
            });
        }
        Ok(stream)
    }
}

/// A rustls connector that accepts any server certificate. Used only when a
/// backend is explicitly marked insecure.
fn insecure_ws_connector() -> Connector {
    // Pin the ring provider explicitly — relying on the process-default
    // provider is fragile when multiple crates pull rustls in.
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let config = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("ring provider supports default protocol versions")
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(NoCertVerify))
        .with_no_client_auth();
    Connector::Rustls(Arc::new(config))
}

#[derive(Debug)]
struct NoCertVerify;

impl rustls::client::danger::ServerCertVerifier for NoCertVerify {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        use rustls::SignatureScheme as S;
        vec![
            S::RSA_PKCS1_SHA256,
            S::RSA_PKCS1_SHA384,
            S::RSA_PKCS1_SHA512,
            S::ECDSA_NISTP256_SHA256,
            S::ECDSA_NISTP384_SHA384,
            S::ED25519,
            S::RSA_PSS_SHA256,
            S::RSA_PSS_SHA384,
            S::RSA_PSS_SHA512,
        ]
    }
}

/// Read the next JSON line from a websocket stream, ignoring pings & binary frames.
pub async fn read_ws_text(stream: &mut WsStream) -> Result<Option<String>, MihomoError> {
    while let Some(item) = stream.next().await {
        let msg = item
            .map_err(|e| MihomoError::Other(format!("ws read: {e}")))?;
        match msg {
            Message::Text(text) => return Ok(Some(text.to_string())),
            Message::Binary(bytes) => {
                if let Ok(text) = std::str::from_utf8(&bytes) {
                    return Ok(Some(text.to_owned()));
                }
            }
            Message::Ping(payload) => {
                if let Err(e) = stream.send(Message::Pong(payload)).await {
                    return Err(MihomoError::Other(format!("ws pong: {e}")));
                }
            }
            Message::Close(_) => return Ok(None),
            Message::Pong(_) | Message::Frame(_) => {}
        }
    }
    Ok(None)
}
