use serde::{Deserialize, Serialize};

/// Closed-connections retention. Approximately 250-500 KB at full capacity.
pub const CLOSED_CAP: usize = 500;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Connection {
    pub id: String,
    pub host: String,
    pub network: String,
    pub conn_type: String,
    pub source_ip: String,
    pub source_port: u32,
    pub destination_ip: String,
    pub destination_port: u32,
    pub inbound_ip: String,
    pub inbound_port: u32,
    pub inbound_name: String,
    pub dns_mode: String,
    pub uid: u32,
    pub process: String,
    pub process_path: String,
    pub special_proxy: String,
    pub special_rules: String,
    pub remote_destination: String,
    pub sniff_host: String,
    pub rule: String,
    pub rule_payload: String,
    pub chains: Vec<String>,
    pub connection_logs: Vec<String>,
    pub upload: u64,
    pub download: u64,
    pub upload_speed: u64,
    pub download_speed: u64,
    pub start: String,
    pub is_closed: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionsTotals {
    pub upload: u64,
    pub download: u64,
    pub memory: u64,
}

/// Aggregate of all active connections sharing one process or source IP.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionGroup {
    pub key: String,
    pub label: String,
    pub process: String,
    pub process_path: String,
    pub source_ip: String,
    pub count: u32,
    pub upload: u64,
    pub download: u64,
    pub upload_speed: u64,
    pub download_speed: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionsFrame {
    pub active_count: u32,
    pub closed_count: u32,
    pub totals: ConnectionsTotals,
    /// True for the first frame after each WS connect or reconnect.
    pub is_initial: bool,
}

/// Which list a window slice is drawn from.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionsListKind {
    Active,
    Closed,
}

/// Sort key for the connections list. Mirrors Dart's `ConnectionsSort`.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionsSort {
    #[default]
    Time,
    Upload,
    Download,
    UploadSpeed,
    DownloadSpeed,
    Process,
}

/// Sort key for the process-group list. Mirrors Dart's `ConnectionGroupSort`.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionGroupSort {
    #[default]
    Name,
    Count,
    Upload,
    Download,
    UploadSpeed,
    DownloadSpeed,
}
