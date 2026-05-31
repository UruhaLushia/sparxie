use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use http_body_util::{BodyExt, Full};
use hyper::body::Bytes;
use reqwest::{Client, Method, Url};
use serde_json::Value;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio_tungstenite::{
    Connector, MaybeTlsStream, WebSocketStream, client_async, connect_async,
    connect_async_tls_with_config,
    tungstenite::{
        client::IntoClientRequest,
        http::{HeaderValue, Uri},
        protocol::Message,
    },
};

use crate::error::MihomoError;

/// Where a backend lives. `http`/`https` go over TCP via reqwest; `unix` and
/// `pipe` are local IPC transports spoken with hyper directly.
#[derive(Clone, Debug)]
enum Transport {
    /// http(s) — `base` is the parsed TCP URL.
    Tcp { base: Url },
    /// Unix domain socket at `path`.
    Unix {
        #[cfg_attr(not(unix), allow(dead_code))]
        path: String,
    },
    /// Windows named pipe at `name` (e.g. `\\.\pipe\mihomo`).
    Pipe {
        #[cfg_attr(not(windows), allow(dead_code))]
        name: String,
    },
}

impl Transport {
    fn parse(base_url: &str) -> Result<Self, MihomoError> {
        let trimmed = base_url.trim();
        if let Some(rest) = trimmed.strip_prefix("unix:") {
            // Optional `//` authority marker after the scheme; a real socket
            // path keeps its own leading slash (`unix:///run/x` → `/run/x`).
            let path = rest.strip_prefix("//").unwrap_or(rest);
            if path.is_empty() {
                return Err(MihomoError::InvalidUrl("empty unix socket path".into()));
            }
            return Ok(Self::Unix {
                path: path.to_string(),
            });
        }
        if let Some(rest) = trimmed.strip_prefix("pipe:") {
            let name = rest.strip_prefix("//").unwrap_or(rest);
            if name.is_empty() {
                return Err(MihomoError::InvalidUrl("empty pipe name".into()));
            }
            return Ok(Self::Pipe {
                name: name.to_string(),
            });
        }
        let base = Url::parse(trimmed).map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
        Ok(Self::Tcp { base })
    }

    fn is_tcp(&self) -> bool {
        matches!(self, Self::Tcp { .. })
    }
}

/// Internal mihomo controller client. Held only on the Rust side; Dart never
/// sees it. TCP backends use reqwest; IPC backends use hyper over a raw stream.
pub struct MihomoClient {
    transport: Transport,
    pub secret: Option<String>,
    http: Option<Client>,
    allow_insecure: bool,
}

/// Boxed transport stream so the IPC WebSocket covers Unix sockets and named
/// pipes with one type.
pub trait AsyncStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> AsyncStream for T {}

/// A WebSocket over either a TCP(-TLS) transport or a boxed IPC stream.
/// `connect_async` and `client_async` return different concrete stream types,
/// so we unify them here and delegate the read/send used by [`read_ws_text`].
pub enum WsStream {
    Tcp(WebSocketStream<MaybeTlsStream<TcpStream>>),
    Ipc(WebSocketStream<Box<dyn AsyncStream>>),
}

impl WsStream {
    async fn next_message(
        &mut self,
    ) -> Option<Result<Message, tokio_tungstenite::tungstenite::Error>> {
        match self {
            Self::Tcp(s) => s.next().await,
            Self::Ipc(s) => s.next().await,
        }
    }

    async fn send(&mut self, msg: Message) -> Result<(), tokio_tungstenite::tungstenite::Error> {
        match self {
            Self::Tcp(s) => s.send(msg).await,
            Self::Ipc(s) => s.send(msg).await,
        }
    }
}

impl MihomoClient {
    pub fn new(
        base_url: &str,
        secret: Option<String>,
        allow_insecure: bool,
    ) -> Result<Self, MihomoError> {
        let transport = Transport::parse(base_url)?;
        // reqwest is only used for TCP; IPC builds its own per-request conn.
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

    /// http(s)://host/<path> → ws(s)://host/<path>, preserving query string.
    fn ws_url(&self, path: &str) -> Result<Url, MihomoError> {
        let mut url = self.tcp_url(path)?;
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

    /// One HTTP/1.1 request over an IPC transport (unix/pipe). No auth — local
    /// IPC backends run without a secret.
    async fn ipc_request(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, MihomoError> {
        let stream = self.connect_ipc().await?;
        let io = hyper_util::rt::TokioIo::new(stream);
        let (mut sender, conn) = hyper::client::conn::http1::handshake(io)
            .await
            .map_err(|e| MihomoError::Other(format!("ipc handshake: {e}")))?;
        tokio::spawn(async move {
            let _ = conn.await;
        });

        let uri: Uri = format!("/{}", path.trim_start_matches('/'))
            .parse()
            .map_err(|e| MihomoError::InvalidUrl(format!("ipc uri: {e}")))?;
        let has_body = body.is_some();
        let body_bytes = body
            .map(|b| Bytes::from(b.to_string()))
            .unwrap_or_else(Bytes::new);
        let mut builder = hyper::Request::builder()
            .method(method)
            .uri(uri)
            // mihomo requires a non-empty Host even over IPC; the value is
            // irrelevant for a local socket.
            .header("host", "localhost");
        if has_body {
            builder = builder.header("content-type", "application/json");
        }
        let req = builder
            .body(Full::new(body_bytes))
            .map_err(|e| MihomoError::Other(format!("ipc request build: {e}")))?;

        let resp = sender
            .send_request(req)
            .await
            .map_err(|e| MihomoError::Network(format!("ipc send: {e}")))?;
        let status = resp.status();
        let bytes = resp
            .into_body()
            .collect()
            .await
            .map_err(|e| MihomoError::Network(format!("ipc body: {e}")))?
            .to_bytes();
        if !status.is_success() {
            return Err(MihomoError::Upstream {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        Ok(parse_body_or_ok(&bytes))
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
            Transport::Pipe { name } => {
                let client = tokio::net::windows::named_pipe::ClientOptions::new()
                    .open(name)
                    .map_err(|e| MihomoError::Network(format!("pipe open {name}: {e}")))?;
                Ok(Box::new(client))
            }
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
            Transport::Tcp { .. } => self.open_ws_tcp(path).await,
            _ => self.open_ws_ipc(path).await,
        }
    }

    async fn open_ws_tcp(&self, path: &str) -> Result<WsStream, MihomoError> {
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
            connect_async_tls_with_config(request, None, false, Some(insecure_ws_connector()))
                .await
                .map_err(|e| MihomoError::Other(format!("websocket connect: {e}")))?
        } else {
            connect_async(request)
                .await
                .map_err(|e| MihomoError::Other(format!("websocket connect: {e}")))?
        };
        check_ws_response(&response)?;
        Ok(WsStream::Tcp(stream))
    }

    async fn open_ws_ipc(&self, path: &str) -> Result<WsStream, MihomoError> {
        let stream = self.connect_ipc().await?;
        // A dummy authority is fine — the stream is already the IPC socket;
        // tungstenite fills in Host + all Sec-WebSocket-* handshake headers.
        let request = format!("ws://localhost/{}", path.trim_start_matches('/'))
            .into_client_request()
            .map_err(|e| MihomoError::InvalidUrl(format!("ipc ws request: {e}")))?;

        let (stream, response) = client_async(request, stream)
            .await
            .map_err(|e| MihomoError::Other(format!("ipc websocket connect: {e}")))?;
        check_ws_response(&response)?;
        Ok(WsStream::Ipc(stream))
    }
}

fn check_ws_response<T>(
    response: &tokio_tungstenite::tungstenite::http::Response<T>,
) -> Result<(), MihomoError> {
    if !response.status().is_informational() && !response.status().is_success() {
        return Err(MihomoError::Upstream {
            status: response.status().as_u16(),
            body: format!("ws handshake returned {}", response.status()),
        });
    }
    Ok(())
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
    while let Some(item) = stream.next_message().await {
        let msg = item.map_err(|e| MihomoError::Other(format!("ws read: {e}")))?;
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
