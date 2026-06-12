mod insecure_tls;
mod ipc;
mod transport;
mod ws;

use std::time::Duration;

use hyper::body::Bytes;
use reqwest::{Client, Method, Url};
use serde_json::Value;

use crate::MihomoError;

pub use transport::AsyncStream;
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

    fn http(&self) -> &Client {
        self.http
            .as_ref()
            .expect("tcp client present for tcp transport")
    }

    /// One HTTP/1.1 request over an IPC transport (unix/pipe). No auth: local
    /// IPC backends run without a secret.
    async fn ipc_request(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, MihomoError> {
        let has_body = body.is_some();
        let body_bytes = body.map(|b| Bytes::from(b.to_string())).unwrap_or_default();
        let slot = ipc::slot(self.ipc_key()?).await;
        let mut sender = slot.lock().await;

        for attempt in 0..2 {
            if sender.as_ref().map_or(true, |sender| sender.is_closed()) {
                *sender = Some(self.open_ipc_sender().await?);
            }
            let req = ipc::request(method.clone(), path, body_bytes.clone(), has_body)?;
            let sent = {
                let tx = sender
                    .as_mut()
                    .expect("ipc sender was just created when missing");
                match tx.ready().await {
                    Ok(()) => tx
                        .send_request(req)
                        .await
                        .map_err(|error| format!("ipc send: {error}")),
                    Err(error) => Err(format!("ipc ready: {error}")),
                }
            };
            match sent {
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

    async fn open_ipc_sender(&self) -> Result<ipc::Sender, MihomoError> {
        let stream = self.connect_ipc().await?;
        let io = hyper_util::rt::TokioIo::new(stream);
        let (sender, conn) = hyper::client::conn::http1::handshake(io)
            .await
            .map_err(|e| MihomoError::Other(format!("ipc handshake: {e}")))?;
        tokio::spawn(async move {
            let _ = conn.await;
        });
        Ok(sender)
    }

    fn ipc_key(&self) -> Result<String, MihomoError> {
        match &self.transport {
            Transport::Unix { path } => Ok(format!("unix:{path}")),
            Transport::Pipe { name } => Ok(format!("pipe:{name}")),
            Transport::Tcp { .. } => Err(MihomoError::Other("ipc_key on tcp transport".into())),
        }
    }

    /// Connect the raw IPC stream for the current transport.
    async fn connect_ipc(&self) -> Result<Box<dyn AsyncStream>, MihomoError> {
        match &self.transport {
            #[cfg(unix)]
            Transport::Unix { path } => {
                let stream = tokio::net::UnixStream::connect(path)
                    .await
                    .map_err(|e| MihomoError::Network(format!("unix connect {path}: {e}")))?;
                Ok(Box::new(stream))
            }
            #[cfg(not(unix))]
            Transport::Unix { .. } => Err(MihomoError::Other(
                "unix sockets are not supported on this platform".into(),
            )),
            #[cfg(windows)]
            Transport::Pipe { name } => Ok(Box::new(ipc::open_named_pipe(name).await?)),
            #[cfg(not(windows))]
            Transport::Pipe { .. } => Err(MihomoError::Other(
                "named pipes are only supported on Windows".into(),
            )),
            Transport::Tcp { .. } => Err(MihomoError::Other("connect_ipc on tcp transport".into())),
        }
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
            _ => ws::open_ipc(self.connect_ipc().await?, path).await,
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
