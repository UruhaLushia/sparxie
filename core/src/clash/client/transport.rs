use reqwest::{Method, Url};
use tokio::io::{AsyncRead, AsyncWrite};

use crate::MihomoError;

use super::service::ServiceAuth;

#[derive(Clone)]
pub(super) enum IpcEndpoint {
    Unix {
        #[cfg_attr(not(unix), allow(dead_code))]
        path: String,
    },
    #[cfg_attr(not(windows), allow(dead_code))]
    Pipe {
        #[cfg_attr(not(windows), allow(dead_code))]
        name: String,
    },
}

impl IpcEndpoint {
    fn key(&self) -> String {
        match self {
            Self::Unix { path } => format!("unix:{path}"),
            Self::Pipe { name } => format!("pipe:{name}"),
        }
    }

    async fn connect(&self) -> Result<Box<dyn AsyncStream>, MihomoError> {
        match self {
            Self::Unix { path } => connect_unix(path).await,
            Self::Pipe { name } => connect_pipe(name).await,
        }
    }
}

/// Where a backend lives. `http`/`https` go over TCP via reqwest; `unix` and
/// `pipe` are local IPC transports spoken with hyper directly.
#[derive(Clone)]
pub(super) enum Transport {
    /// http(s) — `base` is the parsed TCP URL.
    Tcp { base: Url },
    /// Direct mihomo IPC transport.
    Ipc(IpcEndpoint),
    /// Sparkle service IPC. Requests are signed and proxied through
    /// `/core/controller` to the service-managed mihomo instance.
    SparkleService {
        endpoint: IpcEndpoint,
        auth: ServiceAuth,
    },
}

impl Transport {
    pub(super) fn parse(base_url: &str) -> Result<Self, MihomoError> {
        let trimmed = base_url.trim();
        if trimmed == "sparkle-service" {
            return Self::sparkle_service(None);
        }
        if let Some(rest) = trimmed.strip_prefix("sparkle-service:") {
            let path = rest.strip_prefix("//").unwrap_or(rest);
            let auth_path = if path.is_empty() {
                None
            } else {
                Some(path.to_string())
            };
            return Self::sparkle_service(auth_path);
        }
        if let Some(rest) = trimmed.strip_prefix("unix:") {
            // Optional `//` authority marker after the scheme; a real socket
            // path keeps its own leading slash (`unix:///run/x` -> `/run/x`).
            let path = rest.strip_prefix("//").unwrap_or(rest);
            if path.is_empty() {
                return Err(MihomoError::InvalidUrl("empty unix socket path".into()));
            }
            return Ok(Self::Ipc(IpcEndpoint::Unix {
                path: path.to_string(),
            }));
        }
        if let Some(rest) = trimmed.strip_prefix("pipe:") {
            let name = rest.strip_prefix("//").unwrap_or(rest);
            if name.is_empty() {
                return Err(MihomoError::InvalidUrl("empty pipe name".into()));
            }
            return Ok(Self::Ipc(IpcEndpoint::Pipe {
                name: name.to_string(),
            }));
        }
        let base = Url::parse(trimmed).map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
        Ok(Self::Tcp { base })
    }

    pub(super) fn is_tcp(&self) -> bool {
        matches!(self, Self::Tcp { .. })
    }

    pub(super) fn ipc_key(&self) -> Result<String, MihomoError> {
        match self {
            Self::Ipc(endpoint) => Ok(endpoint.key()),
            Self::SparkleService { endpoint, auth } => Ok(format!(
                "sparkle-service:{}:{}",
                endpoint.key(),
                auth.key_id()
            )),
            Self::Tcp { .. } => Err(MihomoError::Other("ipc_key on tcp transport".into())),
        }
    }

    pub(super) async fn open_ipc(&self) -> Result<Box<dyn AsyncStream>, MihomoError> {
        match self {
            Self::Ipc(endpoint) => endpoint.connect().await,
            Self::SparkleService { endpoint, .. } => endpoint.connect().await,
            Self::Tcp { .. } => Err(MihomoError::Other("connect_ipc on tcp transport".into())),
        }
    }

    pub(super) fn request_path(&self, path: &str) -> String {
        let path = path.trim_start_matches('/');
        match self {
            Self::SparkleService { .. } if path.is_empty() => "core/controller".into(),
            Self::SparkleService { .. } => format!("core/controller/{path}"),
            _ => path.to_string(),
        }
    }

    pub(super) fn auth_headers(
        &self,
        method: &Method,
        path: &str,
        body: &[u8],
    ) -> Result<Vec<(&'static str, String)>, MihomoError> {
        match self {
            Self::SparkleService { auth, .. } => auth.headers(method.as_str(), path, body),
            _ => Ok(Vec::new()),
        }
    }

    fn sparkle_service(auth_path: Option<String>) -> Result<Self, MihomoError> {
        Ok(Self::SparkleService {
            endpoint: default_service_endpoint(),
            auth: ServiceAuth::load(auth_path)?,
        })
    }
}

/// Boxed transport stream so the IPC WebSocket covers Unix sockets and named
/// pipes with one type.
pub(crate) trait AsyncStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> AsyncStream for T {}

#[cfg(unix)]
async fn connect_unix(path: &str) -> Result<Box<dyn AsyncStream>, MihomoError> {
    let stream = tokio::net::UnixStream::connect(path)
        .await
        .map_err(|e| MihomoError::Network(format!("unix connect {path}: {e}")))?;
    Ok(Box::new(stream))
}

#[cfg(not(unix))]
async fn connect_unix(_path: &str) -> Result<Box<dyn AsyncStream>, MihomoError> {
    Err(MihomoError::Other(
        "unix sockets are not supported on this platform".into(),
    ))
}

#[cfg(windows)]
async fn connect_pipe(name: &str) -> Result<Box<dyn AsyncStream>, MihomoError> {
    Ok(Box::new(super::ipc::open_named_pipe(name).await?))
}

#[cfg(not(windows))]
async fn connect_pipe(_name: &str) -> Result<Box<dyn AsyncStream>, MihomoError> {
    Err(MihomoError::Other(
        "named pipes are only supported on Windows".into(),
    ))
}

#[cfg(windows)]
fn default_service_endpoint() -> IpcEndpoint {
    IpcEndpoint::Pipe {
        name: r"\\.\pipe\sparkle\service".into(),
    }
}

#[cfg(not(windows))]
fn default_service_endpoint() -> IpcEndpoint {
    IpcEndpoint::Unix {
        path: "/tmp/sparkle-service.sock".into(),
    }
}
