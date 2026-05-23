use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use reqwest::{Client, Method, Url};
use serde_json::Value;
use tokio::net::TcpStream;
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{client::IntoClientRequest, http::HeaderValue, protocol::Message},
};

use crate::error::MihomoError;

/// Internal mihomo HTTP client. Held only on the Rust side; Dart never sees it.
pub struct MihomoClient {
    pub base: Url,
    pub secret: Option<String>,
    pub http: Client,
}

pub type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

impl MihomoClient {
    pub fn new(base_url: &str, secret: Option<String>) -> Result<Self, MihomoError> {
        let base =
            Url::parse(base_url).map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
        let http = Client::builder()
            .timeout(Duration::from_secs(15))
            .build()
            .map_err(|e| MihomoError::Other(format!("client build: {e}")))?;
        Ok(Self {
            base,
            secret,
            http,
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

        let (stream, response) = connect_async(request)
            .await
            .map_err(|e| MihomoError::Other(format!("websocket connect: {e}")))?;
        if !response.status().is_informational() && !response.status().is_success() {
            return Err(MihomoError::Upstream {
                status: response.status().as_u16(),
                body: format!("ws handshake returned {}", response.status()),
            });
        }
        Ok(stream)
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
