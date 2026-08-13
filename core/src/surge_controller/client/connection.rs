use std::time::Duration;

use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::timeout;
use url::Url;

use crate::MihomoError;

use super::{SurgeControllerTarget, Welcome};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const IO_TIMEOUT: Duration = Duration::from_secs(15);
const MAX_FRAME_SIZE: usize = 32 * 1024 * 1024;
const MIN_PROTOCOL: u32 = 22;

pub struct SurgeControllerConnection {
    stream: TcpStream,
    read_buffer: Vec<u8>,
    pub(super) welcome: Welcome,
}

impl SurgeControllerConnection {
    pub(super) async fn connect(target: &SurgeControllerTarget) -> Result<Self, MihomoError> {
        let address = parse_address(&target.address)?;
        let stream = timeout(CONNECT_TIMEOUT, TcpStream::connect(address))
            .await
            .map_err(|_| MihomoError::Network("连接 Surge 控制器超时".into()))?
            .map_err(|error| MihomoError::Network(error.to_string()))?;
        stream
            .set_nodelay(true)
            .map_err(|error| MihomoError::Network(error.to_string()))?;
        let mut connection = Self {
            stream,
            read_buffer: Vec::with_capacity(8192),
            welcome: Welcome::default(),
        };
        let password = target.password.as_deref().unwrap_or_default();
        if password.contains(['\r', '\n']) {
            return Err(MihomoError::Other("Surge 控制器密码不能包含换行符".into()));
        }
        connection.write_line(password.as_bytes()).await?;
        let raw = connection.read_value().await?;
        if let Some(message) = response_error(&raw) {
            return Err(MihomoError::Other(format!(
                "Surge 控制器认证失败：{message}"
            )));
        }
        let welcome: Welcome = serde_json::from_value(raw)
            .map_err(|error| MihomoError::InvalidJson(error.to_string()))?;
        if welcome.protocol < MIN_PROTOCOL {
            return Err(MihomoError::Other(format!(
                "Surge 控制器协议版本 {} 过低，需要 {MIN_PROTOCOL} 或更高版本",
                welcome.protocol
            )));
        }
        connection.welcome = welcome;
        Ok(connection)
    }

    pub async fn request<I, S>(&mut self, argv: I) -> Result<Value, MihomoError>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        self.send(argv).await?;
        self.next_value().await
    }

    pub async fn send<I, S>(&mut self, argv: I) -> Result<(), MihomoError>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let argv = argv.into_iter().map(Into::into).collect::<Vec<_>>();
        if argv.is_empty() {
            return Err(MihomoError::Other("Surge 控制器命令不能为空".into()));
        }
        let payload = serde_json::to_vec(&json!({ "argv": argv }))?;
        if payload.len() > MAX_FRAME_SIZE {
            return Err(MihomoError::Other(
                "Surge 控制器请求超过 32 MiB 限制".into(),
            ));
        }
        self.write_line(&payload).await
    }

    pub async fn next_value(&mut self) -> Result<Value, MihomoError> {
        let value = self.read_value().await?;
        checked_response(value)
    }

    pub async fn next_stream_value(&mut self) -> Result<Value, MihomoError> {
        let frame = self.read_frame().await?;
        let value: Value = serde_json::from_slice(&frame)
            .map_err(|error| MihomoError::InvalidJson(error.to_string()))?;
        checked_response(value)
    }

    async fn write_line(&mut self, bytes: &[u8]) -> Result<(), MihomoError> {
        timeout(IO_TIMEOUT, async {
            self.stream.write_all(bytes).await?;
            self.stream.write_all(b"\r\n").await?;
            self.stream.flush().await
        })
        .await
        .map_err(|_| MihomoError::Network("写入 Surge 控制器超时".into()))?
        .map_err(|error| MihomoError::Network(error.to_string()))
    }

    async fn read_value(&mut self) -> Result<Value, MihomoError> {
        let frame = timeout(IO_TIMEOUT, self.read_frame())
            .await
            .map_err(|_| MihomoError::Network("读取 Surge 控制器响应超时".into()))??;
        serde_json::from_slice(&frame).map_err(|error| MihomoError::InvalidJson(error.to_string()))
    }

    async fn read_frame(&mut self) -> Result<Vec<u8>, MihomoError> {
        let mut search_from = 0;
        loop {
            if let Some(relative_index) = self.read_buffer[search_from..]
                .windows(2)
                .position(|window| window == b"\r\n")
            {
                let index = search_from + relative_index;
                if index > MAX_FRAME_SIZE {
                    return Err(frame_too_large());
                }
                let frame = self.read_buffer[..index].to_vec();
                self.read_buffer.drain(..index + 2);
                if frame.is_empty() {
                    continue;
                }
                return Ok(frame);
            }
            if self.read_buffer.len() >= MAX_FRAME_SIZE {
                return Err(frame_too_large());
            }
            search_from = self.read_buffer.len().saturating_sub(1);
            let mut chunk = [0_u8; 8192];
            let read = self
                .stream
                .read(&mut chunk)
                .await
                .map_err(|error| MihomoError::Network(error.to_string()))?;
            if read == 0 {
                return Err(MihomoError::Network(
                    "Surge 控制器在响应完成前关闭了连接".into(),
                ));
            }
            self.read_buffer.extend_from_slice(&chunk[..read]);
        }
    }
}

fn checked_response(value: Value) -> Result<Value, MihomoError> {
    if let Some(message) = response_error(&value) {
        return Err(MihomoError::Other(format!(
            "Surge 控制器返回错误：{message}"
        )));
    }
    Ok(value)
}

fn parse_address(raw: &str) -> Result<String, MihomoError> {
    let raw = raw.trim();
    let normalized = if raw.contains("://") {
        raw.to_string()
    } else {
        format!("tcp://{raw}")
    };
    let url =
        Url::parse(&normalized).map_err(|error| MihomoError::InvalidUrl(error.to_string()))?;
    if url.scheme() != "tcp" {
        return Err(MihomoError::InvalidUrl(
            "Surge 控制器仅支持 tcp:// 地址".into(),
        ));
    }
    if !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || !matches!(url.path(), "" | "/")
    {
        return Err(MihomoError::InvalidUrl(
            "Surge 控制器地址不能包含认证信息、路径、查询参数或片段".into(),
        ));
    }
    let host = url
        .host_str()
        .filter(|host| !host.is_empty())
        .ok_or_else(|| MihomoError::InvalidUrl("缺少主机名".into()))?;
    let port = url
        .port()
        .ok_or_else(|| MihomoError::InvalidUrl("缺少端口".into()))?;
    if host.contains(':') {
        Ok(format!("[{host}]:{port}"))
    } else {
        Ok(format!("{host}:{port}"))
    }
}

fn response_error(value: &Value) -> Option<String> {
    let error = value.get("error")?;
    match error {
        Value::Null => None,
        Value::String(message) if message.is_empty() => None,
        Value::String(message) => Some(message.clone()),
        other => Some(other.to_string()),
    }
}

fn frame_too_large() -> MihomoError {
    MihomoError::InvalidJson("Surge 控制器响应超过 32 MiB 限制".into())
}
