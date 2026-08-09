use serde::{Deserialize, Serialize};

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

impl Connection {
    pub(super) fn matches_query(&self, query: &str) -> bool {
        if query.is_empty() {
            return true;
        }
        let contains = |value: &str| crate::utils::text::contains_filter(value, query);
        contains(&self.host)
            || contains(&self.network)
            || contains(&self.conn_type)
            || contains(&self.source_ip)
            || self.source_port.to_string().contains(query)
            || format!("{}:{}", self.source_ip, self.source_port).contains(query)
            || contains(&self.destination_ip)
            || self.destination_port.to_string().contains(query)
            || format!("{}:{}", self.destination_ip, self.destination_port).contains(query)
            || contains(&self.inbound_ip)
            || self.inbound_port.to_string().contains(query)
            || format!("{}:{}", self.inbound_ip, self.inbound_port).contains(query)
            || contains(&self.inbound_name)
            || contains(&self.dns_mode)
            || self.uid.to_string().contains(query)
            || contains(&self.process)
            || contains(&self.process_path)
            || contains(&self.special_proxy)
            || contains(&self.special_rules)
            || contains(&self.remote_destination)
            || contains(&self.sniff_host)
            || contains(&self.rule)
            || contains(&self.rule_payload)
            || contains(&self.start)
            || self.chains.iter().any(|value| contains(value))
            || self.connection_logs.iter().any(|value| contains(value))
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionsTotals {
    pub upload: u64,
    pub download: u64,
    pub memory: u64,
}

/// Aggregate of connections sharing one process or source IP.
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
