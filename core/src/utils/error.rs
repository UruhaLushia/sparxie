use std::fmt;

/// Errors crossing the FFI boundary. Variants are flat (no foreign types in
/// fields) so flutter_rust_bridge can mirror this enum into Dart and Dart
/// callers can `switch` on it instead of string-matching.
#[derive(Debug, Clone)]
pub enum MihomoError {
    InvalidUrl(String),
    InvalidRegex { pattern: String, message: String },
    Upstream { status: u16, body: String },
    Network(String),
    InvalidJson(String),
    Other(String),
}

impl fmt::Display for MihomoError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MihomoError::InvalidUrl(s) => write!(f, "无效的后端地址:{s}"),
            MihomoError::InvalidRegex { pattern, message } => {
                write!(f, "正则 `{pattern}` 无效:{message}")
            }
            MihomoError::Upstream { status, body } => {
                write!(f, "后端返回 {status}: {body}")
            }
            MihomoError::Network(msg) => write!(f, "网络错误:{msg}"),
            MihomoError::InvalidJson(msg) => write!(f, "返回 JSON 解析失败:{msg}"),
            MihomoError::Other(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for MihomoError {}

impl From<reqwest::Error> for MihomoError {
    fn from(value: reqwest::Error) -> Self {
        MihomoError::Network(value.to_string())
    }
}

impl From<serde_json::Error> for MihomoError {
    fn from(value: serde_json::Error) -> Self {
        MihomoError::InvalidJson(value.to_string())
    }
}

impl From<regex::Error> for MihomoError {
    fn from(value: regex::Error) -> Self {
        MihomoError::InvalidRegex {
            pattern: String::new(),
            message: value.to_string(),
        }
    }
}
