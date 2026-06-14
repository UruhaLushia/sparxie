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

impl From<tonic::Status> for MihomoError {
    fn from(value: tonic::Status) -> Self {
        MihomoError::Upstream {
            status: grpc_status_code(value.code()),
            body: value.message().to_string(),
        }
    }
}

impl From<tonic::transport::Error> for MihomoError {
    fn from(value: tonic::transport::Error) -> Self {
        MihomoError::Network(value.to_string())
    }
}

fn grpc_status_code(code: tonic::Code) -> u16 {
    match code {
        tonic::Code::Ok => 200,
        tonic::Code::Cancelled => 499,
        tonic::Code::Unknown => 500,
        tonic::Code::InvalidArgument => 400,
        tonic::Code::DeadlineExceeded => 504,
        tonic::Code::NotFound => 404,
        tonic::Code::AlreadyExists => 409,
        tonic::Code::PermissionDenied => 403,
        tonic::Code::ResourceExhausted => 429,
        tonic::Code::FailedPrecondition => 412,
        tonic::Code::Aborted => 409,
        tonic::Code::OutOfRange => 400,
        tonic::Code::Unimplemented => 501,
        tonic::Code::Internal => 500,
        tonic::Code::Unavailable => 503,
        tonic::Code::DataLoss => 500,
        tonic::Code::Unauthenticated => 401,
    }
}
