use flutter_rust_bridge::frb;

use crate::MihomoError;
use crate::frb_generated::StreamSink;

/// Rust-owned local engine lifecycle.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Default, serde::Serialize, serde::Deserialize)]
pub enum CoreState {
    #[default]
    Stopped,
    Starting,
    Running,
    Stopping,
    Error,
}

/// The platform creates the TUN device; the kernel only attaches to its fd.
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct TunSettings {
    pub enabled: bool,
    /// "system" | "gvisor" | "mixed" — kernel stack for the platform fd.
    pub stack: String,
    pub dns: String,
    pub ipv6: bool,
    pub mtu: u32,
    pub allow_bypass: bool,
    /// Bypass mode: "off" (tunnel everything), "lan" (all private subnets),
    /// "custom" (user-provided subnets).
    pub bypass_mode: String,
    pub bypass_custom: String,
    pub system_proxy: bool,
    /// VPN access control: "accept_all" | "accept_selected" | "reject_selected".
    pub access_mode: String,
    pub access_packages: Vec<String>,
}

impl Default for TunSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            stack: "system".into(),
            dns: "172.19.0.2".into(),
            ipv6: false,
            mtu: 9000,
            allow_bypass: false,
            bypass_mode: "lan".into(),
            bypass_custom: String::new(),
            system_proxy: false,
            access_mode: "accept_all".into(),
            access_packages: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct CoreConfig {
    pub mixed_port: u16,
    pub port: u16,
    pub socks_port: u16,
    pub allow_lan: bool,
    pub log_level: String,
    pub tun: TunSettings,
    pub external_controller: String,
    pub secret: String,
}

impl Default for CoreConfig {
    fn default() -> Self {
        Self {
            mixed_port: 7890,
            port: 0,
            socks_port: 0,
            allow_lan: false,
            log_level: "info".into(),
            tun: TunSettings::default(),
            external_controller: String::new(),
            secret: String::new(),
        }
    }
}

/// Complete Rust-owned state; subscribers may safely skip older snapshots.
#[derive(Clone, Debug, PartialEq)]
pub struct CoreSnapshot {
    pub state: CoreState,
    pub settings: CoreConfig,
    pub tun_attached: bool,
    pub tun_ipv6: bool,
    pub last_error: String,
}

/// A kernel config profile (the app only selects among these; the kernel
/// content is never rewritten by the app).
#[derive(Clone, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct CoreConfigProfile {
    pub id: String,
    pub name: String,
    pub kind: CoreProfileKind,
    pub source_url: String,
    #[serde(skip)]
    pub active: bool,
    pub user_agent: String,
    pub etag: String,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum CoreProfileKind {
    #[default]
    Builtin,
    Imported,
}

#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct AppInfo {
    pub package: String,
    pub label: String,
}

#[derive(Clone, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct AppWindow {
    pub apps: Vec<AppInfo>,
    pub total: u32,
}

#[frb(sync)]
pub fn core_snapshot() -> CoreSnapshot {
    crate::core::core_snapshot()
}

pub async fn core_list_apps_window(query: String, offset: u32, limit: u32) -> AppWindow {
    crate::core::list_apps_window(&query, offset, limit).await
}

pub async fn core_update_settings(config: CoreConfig) -> Result<(), MihomoError> {
    crate::core::core_update_settings(config).await
}

pub async fn core_start() -> Result<(), MihomoError> {
    crate::core::core_start().await
}

pub async fn core_stop() -> Result<(), MihomoError> {
    crate::core::core_stop().await
}

pub async fn core_events(sink: StreamSink<CoreSnapshot>) -> Result<(), MihomoError> {
    crate::core::core_events(sink).await
}

#[frb(sync)]
pub fn core_supported() -> bool {
    crate::core::core_supported()
}

pub async fn core_config_list() -> Result<Vec<CoreConfigProfile>, MihomoError> {
    crate::core::config_list().await
}

pub async fn core_config_import(
    url: String,
    text: String,
    name: String,
    user_agent: String,
) -> Result<CoreConfigProfile, MihomoError> {
    crate::core::config_import(&url, &text, &name, &user_agent).await
}

pub async fn core_config_set_active(id: String) -> Result<(), MihomoError> {
    crate::core::config_set_active(&id).await
}

pub async fn core_config_edit(
    id: String,
    name: String,
    url: String,
    user_agent: String,
) -> Result<(), MihomoError> {
    crate::core::config_edit(&id, &name, &url, &user_agent).await
}

pub async fn core_config_update(id: String) -> Result<(), MihomoError> {
    crate::core::config_update(&id).await
}

pub async fn core_config_delete(id: String) -> Result<(), MihomoError> {
    crate::core::config_delete(&id).await
}
