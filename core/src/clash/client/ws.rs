use futures_util::{SinkExt, StreamExt};
use reqwest::Url;
use tokio::net::TcpStream;
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, client_async, connect_async, connect_async_tls_with_config,
    tungstenite::{
        client::IntoClientRequest,
        http::{HeaderValue, Response},
        protocol::Message,
    },
};

use crate::MihomoError;

use super::insecure_tls::insecure_ws_connector;
use super::transport::AsyncStream;

/// A WebSocket over either a TCP(-TLS) transport or a boxed IPC stream.
/// `connect_async` and `client_async` return different concrete stream types,
/// so we unify them here and delegate the read/send used by [`read_ws_text`].
pub enum WsStream {
    Tcp(Box<WebSocketStream<MaybeTlsStream<TcpStream>>>),
    Ipc(Box<WebSocketStream<Box<dyn AsyncStream>>>),
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

pub(super) fn check_ws_response<T>(response: &Response<T>) -> Result<(), MihomoError> {
    if !response.status().is_informational() && !response.status().is_success() {
        return Err(MihomoError::Upstream {
            status: response.status().as_u16(),
            body: format!("ws handshake returned {}", response.status()),
        });
    }
    Ok(())
}

pub(super) async fn open_tcp(
    base: &Url,
    path: &str,
    secret: Option<&str>,
    allow_insecure: bool,
) -> Result<WsStream, MihomoError> {
    let mut url = ws_url(base, path)?;
    if let Some(secret) = secret {
        url.query_pairs_mut().append_pair("token", secret);
    }

    let mut request = url
        .as_str()
        .into_client_request()
        .map_err(|e| MihomoError::InvalidUrl(format!("ws request: {e}")))?;
    if let Some(secret) = secret {
        let value = HeaderValue::from_str(&format!("Bearer {secret}"))
            .map_err(|e| MihomoError::Other(format!("ws auth header: {e}")))?;
        request.headers_mut().insert("authorization", value);
    }

    let (stream, response) = if allow_insecure {
        connect_async_tls_with_config(request, None, false, Some(insecure_ws_connector()))
            .await
            .map_err(|e| MihomoError::Other(format!("websocket connect: {e}")))?
    } else {
        connect_async(request)
            .await
            .map_err(|e| MihomoError::Other(format!("websocket connect: {e}")))?
    };
    check_ws_response(&response)?;
    Ok(WsStream::Tcp(Box::new(stream)))
}

fn ws_url(base: &Url, path: &str) -> Result<Url, MihomoError> {
    let mut url = base
        .join(path.trim_start_matches('/'))
        .map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
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

pub(super) async fn open_ipc(
    stream: Box<dyn AsyncStream>,
    path: &str,
) -> Result<WsStream, MihomoError> {
    let request = format!("ws://localhost/{}", path.trim_start_matches('/'))
        .into_client_request()
        .map_err(|e| MihomoError::InvalidUrl(format!("ipc ws request: {e}")))?;

    let (stream, response) = client_async(request, stream)
        .await
        .map_err(|e| MihomoError::Other(format!("ipc websocket connect: {e}")))?;
    check_ws_response(&response)?;
    Ok(WsStream::Ipc(Box::new(stream)))
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
