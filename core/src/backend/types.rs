use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TrafficSample {
    pub up: u64,
    pub down: u64,
    #[serde(default, rename = "upTotal")]
    pub up_total: u64,
    #[serde(default, rename = "downTotal")]
    pub down_total: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct MemorySample {
    #[serde(default)]
    pub inuse: u64,
    #[serde(default)]
    pub oslimit: u64,
    #[serde(default)]
    pub goroutines: u32,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LogEntry {
    #[serde(default)]
    pub id: u64,
    #[serde(default)]
    pub time: String,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub message: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LogWindow {
    pub total: u32,
    pub offset: u32,
    pub rows: Vec<LogEntry>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LogsFrame {
    pub total: u32,
    pub latest_id: u64,
    pub is_initial: bool,
}

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
    pub(crate) fn matches_query(&self, query: &str) -> bool {
        if query.is_empty() {
            return true;
        }
        let contains = |value: &str| value.to_lowercase().contains(query);
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
pub struct ConnectionWindow {
    pub total: u32,
    pub rows: Vec<Connection>,
}

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionStats {
    pub upload: u64,
    pub download: u64,
    pub upload_speed: u64,
    pub download_speed: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionsTotals {
    pub upload: u64,
    pub download: u64,
    pub memory: u64,
    pub connections_in: u32,
    pub connections_out: u32,
}

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
    pub is_initial: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ConnectionsListKind {
    Active,
    Closed,
}

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

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ProxyMemberSort {
    #[default]
    Original,
    Name,
    Delay,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyCatalog {
    pub groups: Vec<ProxyGroupEntry>,
    pub icon_urls: Vec<String>,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyGroupEntry {
    pub name: String,
    pub proxy_type: String,
    pub selectable: bool,
    pub icon: String,
    pub member_count: u32,
    pub members_hash: u32,
    pub now: String,
    pub now_delay: i32,
    pub test_url: String,
    pub fixed: String,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyMemberEntry {
    pub name: String,
    pub proxy_type: String,
    pub delay: i32,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyDelayEntry {
    pub name: String,
    pub delay: i32,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyDelayEvent {
    pub name: String,
    pub delay: i32,
    pub window_offset: u32,
    pub window_members_hash: u32,
    pub window_entries: Vec<ProxyMemberEntry>,
}

#[derive(Clone, Debug, Default)]
pub struct GroupDelayEntry {
    pub name: String,
    pub delay: i32,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyProviderEntry {
    pub name: String,
    pub vehicle_type: String,
    pub proxies: u32,
    pub updated_at: String,
    pub updatable: bool,
    pub has_subscription_info: bool,
    pub subscription_upload: u64,
    pub subscription_download: u64,
    pub subscription_total: u64,
    pub subscription_expire: u64,
}

#[derive(Clone, Debug, Default)]
pub struct RuleProviderEntry {
    pub name: String,
    pub vehicle_type: String,
    pub behavior: String,
    pub format: String,
    pub rule_count: u32,
    pub updated_at: String,
    pub updatable: bool,
}

#[derive(Clone, Debug, Default)]
pub struct RuleEntry {
    pub index: u32,
    pub rule_type: String,
    pub payload: String,
    pub proxy: String,
    pub extra_params: Vec<String>,
    pub disabled: bool,
    pub hit_count: u64,
    pub hit_at: String,
    pub miss_count: u64,
    pub miss_at: String,
    pub has_extra: bool,
}

#[derive(Clone, Debug, Default)]
pub struct RulesSummary {
    pub total: u32,
    pub filtered: u32,
}

#[derive(Clone, Debug, Default)]
pub struct CoreConfig {
    pub mode: Option<String>,
    pub mode_options: Vec<String>,
    pub log_level: Option<String>,
    pub tun_enabled: Option<bool>,
    pub allow_lan: Option<bool>,
    pub ipv6: Option<bool>,
    pub tcp_concurrent: Option<bool>,
    pub port: Option<u32>,
    pub socks_port: Option<u32>,
    pub mixed_port: Option<u32>,
}

#[derive(Clone, Debug, Default)]
pub struct VersionInfo {
    pub version: String,
    pub is_cmfa: bool,
    pub is_stash: bool,
    pub supports_core_config: bool,
    pub supports_core_actions: bool,
    pub supports_core_management: bool,
    pub supports_cache_flush: bool,
    pub supports_memory: bool,
    pub supports_tailscale: bool,
    pub supports_diagnostics: bool,
}
