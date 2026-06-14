use reqwest::Url;
use tokio::io::{AsyncRead, AsyncWrite};

use crate::MihomoError;

/// Where a backend lives. `http`/`https` go over TCP via reqwest; `unix` and
/// `pipe` are local IPC transports spoken with hyper directly.
#[derive(Clone, Debug)]
pub(super) enum Transport {
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
    pub(super) fn parse(base_url: &str) -> Result<Self, MihomoError> {
        let trimmed = base_url.trim();
        if let Some(rest) = trimmed.strip_prefix("unix:") {
            // Optional `//` authority marker after the scheme; a real socket
            // path keeps its own leading slash (`unix:///run/x` -> `/run/x`).
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

    pub(super) fn is_tcp(&self) -> bool {
        matches!(self, Self::Tcp { .. })
    }
}

/// Boxed transport stream so the IPC WebSocket covers Unix sockets and named
/// pipes with one type.
pub trait AsyncStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> AsyncStream for T {}
