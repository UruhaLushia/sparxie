use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream,
    tungstenite::{http::Response, protocol::Message},
};

use crate::MihomoError;

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
