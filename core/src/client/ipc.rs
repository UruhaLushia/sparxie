use std::collections::HashMap;
use std::sync::{Arc, OnceLock};

#[cfg(windows)]
use std::time::Duration;

use http_body_util::{BodyExt, Full};
use hyper::body::Bytes;
use hyper::client::conn::http1::SendRequest;
use reqwest::Method;
use serde_json::Value;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::http::Uri;

use crate::MihomoError;

pub(super) type Sender = SendRequest<Full<Bytes>>;
pub(super) type Slot = Arc<Mutex<Option<Sender>>>;

pub(super) async fn slot(key: String) -> Slot {
    let mut pool = pool().lock().await;
    pool.entry(key)
        .or_insert_with(|| Arc::new(Mutex::new(None)))
        .clone()
}

fn pool() -> &'static Mutex<HashMap<String, Slot>> {
    static POOL: OnceLock<Mutex<HashMap<String, Slot>>> = OnceLock::new();
    POOL.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(super) fn request(
    method: Method,
    path: &str,
    body_bytes: Bytes,
    has_body: bool,
) -> Result<hyper::Request<Full<Bytes>>, MihomoError> {
    let uri: Uri = format!("/{}", path.trim_start_matches('/'))
        .parse()
        .map_err(|e| MihomoError::InvalidUrl(format!("ipc uri: {e}")))?;
    let mut builder = hyper::Request::builder()
        .method(method)
        .uri(uri)
        // mihomo requires a non-empty Host even over IPC; the value is
        // irrelevant for a local socket.
        .header("host", "localhost");
    if has_body {
        builder = builder.header("content-type", "application/json");
    }
    builder
        .body(Full::new(body_bytes))
        .map_err(|e| MihomoError::Other(format!("ipc request build: {e}")))
}

pub(super) async fn response(
    resp: hyper::Response<hyper::body::Incoming>,
) -> Result<Value, MihomoError> {
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
    Ok(super::parse_body_or_ok(&bytes))
}

#[cfg(windows)]
pub(super) async fn open_named_pipe(
    name: &str,
) -> Result<tokio::net::windows::named_pipe::NamedPipeClient, MihomoError> {
    const ERROR_PIPE_BUSY: i32 = 231;
    const MAX_RETRIES: usize = 10;

    let mut delay = Duration::from_millis(20);
    let mut last_busy = None;

    for _ in 0..=MAX_RETRIES {
        match tokio::net::windows::named_pipe::ClientOptions::new().open(name) {
            Ok(client) => return Ok(client),
            Err(error) if error.raw_os_error() == Some(ERROR_PIPE_BUSY) => {
                last_busy = Some(error);
                tokio::time::sleep(delay).await;
                delay = (delay * 2).min(Duration::from_millis(250));
            }
            Err(error) => {
                return Err(MihomoError::Network(format!("pipe open {name}: {error}")));
            }
        }
    }

    let error = last_busy
        .map(|e| e.to_string())
        .unwrap_or_else(|| "pipe busy".into());
    Err(MihomoError::Network(format!("pipe open {name}: {error}")))
}
