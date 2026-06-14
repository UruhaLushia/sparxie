use serde::{Deserialize, Serialize};

pub const CLOSED_CAP: usize = 500;

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
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LogEntry {
    #[serde(default)]
    pub time: String,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub message: String,
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

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ConnectionsTotals {
    pub upload: u64,
    pub download: u64,
    pub memory: u64,
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
    pub miss_count: u64,
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
}
