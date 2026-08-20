mod insecure_tls;
mod ipc;
mod service;
mod transport;
mod ws;

use std::time::Duration;

use hyper::body::Bytes;
use reqwest::{Client, Method, Url};
use serde_json::Value;

use crate::MihomoError;

use transport::Transport;
pub use ws::{WsStream, read_ws_text};

/// Internal mihomo controller client. Held only on the Rust side; Dart never
/// sees it. TCP backends use reqwest; IPC backends use hyper over a raw stream.
pub struct MihomoClient {
    transport: Transport,
    pub secret: Option<String>,
    http: Option<Client>,
    allow_insecure: bool,
}

impl MihomoClient {
    pub fn new(
        base_url: &str,
        secret: Option<String>,
        allow_insecure: bool,
    ) -> Result<Self, MihomoError> {
        let transport = Transport::parse(base_url)?;
        // reqwest is only used for TCP; IPC uses a small HTTP/1 sender pool.
        let http = if transport.is_tcp() {
            Some(
                Client::builder()
                    .timeout(Duration::from_secs(15))
                    .danger_accept_invalid_certs(allow_insecure)
                    .gzip(true)
                    .brotli(true)
                    .deflate(true)
                    .zstd(true)
                    .build()
                    .map_err(|e| MihomoError::Other(format!("client build: {e}")))?,
            )
        } else {
            None
        };
        Ok(Self {
            transport,
            secret,
            http,
            allow_insecure,
        })
    }

    fn tcp_url(&self, path: &str) -> Result<Url, MihomoError> {
        let Transport::Tcp { base } = &self.transport else {
            return Err(MihomoError::Other("tcp_url on non-tcp transport".into()));
        };
        base.join(path.trim_start_matches('/'))
            .map_err(|e| MihomoError::InvalidUrl(e.to_string()))
    }

    fn auth(&self, mut req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        if let Some(secret) = &self.secret {
            req = req.bearer_auth(secret);
        }
        req
    }

    pub async fn get_json(&self, path: &str) -> Result<Value, MihomoError> {
        match &self.transport {
            Transport::Tcp { .. } => {
                let req = self.auth(self.http().get(self.tcp_url(path)?));
                let bytes = send_tcp(req).await?;
                serde_json::from_slice(&bytes).map_err(|e| MihomoError::InvalidJson(e.to_string()))
            }
            _ => self.ipc_request(Method::GET, path, None).await,
        }
    }

    /// Like [`get_json`], but IPC transports open a one-off HTTP/1 connection
    /// instead of using the shared sender. Delay healthchecks can legitimately
    /// run for seconds; sharing one IPC sender makes batch tests serialize.
    pub async fn get_json_isolated(&self, path: &str) -> Result<Value, MihomoError> {
        match &self.transport {
            Transport::Tcp { .. } => self.get_json(path).await,
            _ => self.ipc_request_isolated(Method::GET, path, None).await,
        }
    }

    pub async fn forward(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, MihomoError> {
        match &self.transport {
            Transport::Tcp { .. } => {
                let mut req = self.http().request(method, self.tcp_url(path)?);
                if let Some(body) = body {
                    req = req.json(&body);
                }
                let bytes = send_tcp(self.auth(req)).await?;
                Ok(parse_body_or_ok(&bytes))
            }
            _ => self.ipc_request(method, path, body).await,
        }
    }

    async fn ipc_request_isolated(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, MihomoError> {
        let request_path = self.transport.request_path(path);
        let has_body = body.is_some();
        let body_bytes = body.map(|b| Bytes::from(b.to_string())).unwrap_or_default();

        for attempt in 0..2 {
            let mut sender = self.open_ipc_sender().await?;
            match self
                .send_ipc_request(
                    &mut sender,
                    &method,
                    &request_path,
                    body_bytes.clone(),
                    has_body,
                )
                .await
            {
                Ok(resp) => return ipc::response(resp).await,
                Err(_) if attempt == 0 => continue,
                Err(message) => return Err(MihomoError::Network(message)),
            }
        }
        unreachable!("ipc isolated request retry loop always returns")
    }

    fn http(&self) -> &Client {
        self.http
            .as_ref()
            .expect("tcp client present for tcp transport")
    }

    /// One HTTP/1.1 request over an IPC transport (unix/pipe/service).
    /// Direct IPC runs without mihomo secret; Sparkle service adds its own
    /// signed headers below.
    async fn ipc_request(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, MihomoError> {
        let request_path = self.transport.request_path(path);
        let has_body = body.is_some();
        let body_bytes = body.map(|b| Bytes::from(b.to_string())).unwrap_or_default();
        let slot = ipc::slot(self.transport.ipc_key()?).await;
        let mut sender = slot.lock().await;

        for attempt in 0..2 {
            if sender.as_ref().is_none_or(|sender| sender.is_closed()) {
                *sender = Some(self.open_ipc_sender().await?);
            }
            let headers = self
                .send_ipc_request(
                    sender
                        .as_mut()
                        .expect("ipc sender was just created when missing"),
                    &method,
                    &request_path,
                    body_bytes.clone(),
                    has_body,
                )
                .await;
            match headers {
                Ok(resp) => return ipc::response(resp).await,
                Err(message) => {
                    *sender = None;
                    if attempt == 0 {
                        continue;
                    }
                    return Err(MihomoError::Network(message));
                }
            }
        }
        unreachable!("ipc request retry loop always returns")
    }

    async fn send_ipc_request(
        &self,
        sender: &mut ipc::Sender,
        method: &Method,
        request_path: &str,
        body_bytes: Bytes,
        has_body: bool,
    ) -> Result<hyper::Response<hyper::body::Incoming>, String> {
        let headers = self
            .transport
            .auth_headers(method, request_path, &body_bytes)
            .map_err(|error| error.to_string())?;
        let req = ipc::request(method.clone(), request_path, body_bytes, has_body, headers)
            .map_err(|error| error.to_string())?;
        match sender.ready().await {
            Ok(()) => sender
                .send_request(req)
                .await
                .map_err(|error| format!("ipc send: {error}")),
            Err(error) => Err(format!("ipc ready: {error}")),
        }
    }

    async fn open_ipc_sender(&self) -> Result<ipc::Sender, MihomoError> {
        let stream = self.transport.open_ipc().await?;
        let io = hyper_util::rt::TokioIo::new(stream);
        let (sender, conn) = hyper::client::conn::http1::handshake(io)
            .await
            .map_err(|e| MihomoError::Other(format!("ipc handshake: {e}")))?;
        tokio::spawn(async move {
            let _ = conn.await;
        });
        Ok(sender)
    }

    /// Open a WebSocket connection to a mihomo streaming endpoint.
    ///
    /// `path` is the same path you'd pass to `get_json` (e.g. `traffic`,
    /// `connections?interval=1000`). For TCP the secret is forwarded both as a
    /// `?token=` query and an `Authorization: Bearer ...` header; IPC backends
    /// run without a secret.
    pub async fn open_ws(&self, path: &str) -> Result<WsStream, MihomoError> {
        match &self.transport {
            Transport::Tcp { base } => {
                ws::open_tcp(base, path, self.secret.as_deref(), self.allow_insecure).await
            }
            _ => {
                let path = self.transport.request_path(path);
                let headers = self.transport.auth_headers(&Method::GET, &path, &[])?;
                ws::open_ipc(self.transport.open_ipc().await?, &path, headers).await
            }
        }
    }
}

/// Send a TCP request, mapping a non-2xx status to [`MihomoError::Upstream`],
/// and return the raw response body.
async fn send_tcp(req: reqwest::RequestBuilder) -> Result<Bytes, MihomoError> {
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
    Ok(bytes)
}

/// Decode a JSON body, falling back to `{"ok": true}` for empty or
/// non-JSON responses (mihomo's mutating endpoints often return 204/empty).
fn parse_body_or_ok(bytes: &[u8]) -> Value {
    if bytes.is_empty() {
        return serde_json::json!({"ok": true});
    }
    serde_json::from_slice(bytes).unwrap_or_else(|_| serde_json::json!({"ok": true}))
}
