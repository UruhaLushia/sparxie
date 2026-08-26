//! Rust-owned lifecycle and state for the embedded kernel and platform VPN.

use std::collections::HashSet;
use std::net::{IpAddr, SocketAddr};
use std::sync::{Mutex, MutexGuard, OnceLock};

#[cfg(target_os = "android")]
use serde_json::Value;
use tokio::sync::{broadcast, watch};

use crate::MihomoError;
use crate::backend::api::core::{CoreConfig, CoreSnapshot, CoreState};

#[cfg(target_os = "android")]
mod android;
#[cfg(target_os = "android")]
pub(crate) mod configs;
#[cfg(target_os = "android")]
pub(crate) mod go_bridge;
mod profiles;
#[cfg(not(target_os = "android"))]
mod stub;

pub(crate) use profiles::*;

#[cfg(not(target_os = "android"))]
use stub as platform;

#[cfg(target_os = "android")]
use android as platform;

#[cfg(target_os = "android")]
const TUN_GATEWAY4: &str = "172.19.0.1/30";
#[cfg(target_os = "android")]
const VPN_START_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(120);

struct Inner {
    state: CoreState,
    settings: CoreConfig,
    settings_loaded: bool,
    tun_attached: bool,
    tun_ipv6: bool,
    platform_vpn_active: bool,
    last_error: String,
    run_id: u64,
}

pub(crate) struct Core {
    inner: Mutex<Inner>,
    events: watch::Sender<CoreSnapshot>,
    operation: tokio::sync::Mutex<()>,
    profile_operation: tokio::sync::Mutex<()>,
    telemetry: Telemetry,
}

#[derive(Clone)]
struct Telemetry {
    traffic: broadcast::Sender<String>,
    memory: broadcast::Sender<String>,
    logs: broadcast::Sender<String>,
}

fn telemetry_channel() -> broadcast::Sender<String> {
    broadcast::channel(128).0
}

static CORE: OnceLock<Core> = OnceLock::new();

fn core() -> &'static Core {
    CORE.get_or_init(|| {
        let settings = CoreConfig::default();
        let snapshot = CoreSnapshot {
            state: CoreState::Stopped,
            settings: settings.clone(),
            tun_attached: false,
            tun_ipv6: false,
            last_error: String::new(),
        };
        Core {
            inner: Mutex::new(Inner {
                state: CoreState::Stopped,
                settings,
                settings_loaded: false,
                tun_attached: false,
                tun_ipv6: false,
                platform_vpn_active: false,
                last_error: String::new(),
                run_id: 0,
            }),
            events: watch::channel(snapshot).0,
            operation: tokio::sync::Mutex::new(()),
            profile_operation: tokio::sync::Mutex::new(()),
            telemetry: Telemetry {
                traffic: telemetry_channel(),
                memory: telemetry_channel(),
                logs: telemetry_channel(),
            },
        }
    })
}

fn inner() -> MutexGuard<'static, Inner> {
    core()
        .inner
        .lock()
        .unwrap_or_else(|error| error.into_inner())
}

fn snapshot_locked(inner: &Inner) -> CoreSnapshot {
    CoreSnapshot {
        state: inner.state,
        settings: inner.settings.clone(),
        tun_attached: inner.tun_attached,
        tun_ipv6: inner.tun_ipv6,
        last_error: inner.last_error.clone(),
    }
}

fn publish() {
    let snapshot = snapshot_locked(&inner());
    core().events.send_replace(snapshot);
}

#[cfg(target_os = "android")]
fn is_running() -> bool {
    inner().state == CoreState::Running
}

#[cfg(target_os = "android")]
pub(crate) fn require_running() -> Result<(), MihomoError> {
    if is_running() {
        Ok(())
    } else {
        Err(MihomoError::Other("本地引擎未运行".into()))
    }
}

fn load_settings_once() -> bool {
    let should_load = {
        let mut state = inner();
        if state.settings_loaded {
            false
        } else {
            state.settings_loaded = true;
            true
        }
    };
    if !should_load {
        return false;
    }
    #[cfg(target_os = "android")]
    match android::load_settings() {
        Ok(Some(saved)) => match normalize_config(saved) {
            Ok(settings) => inner().settings = settings,
            Err(error) => inner().last_error = error.to_string(),
        },
        Ok(None) => {}
        Err(error) => inner().last_error = error.to_string(),
    }
    true
}

#[cfg(target_os = "android")]
pub(crate) fn push_log(line: String) {
    let frame = serde_json::json!({ "level": "info", "payload": line }).to_string();
    let _ = core().telemetry.logs.send(frame);
}

pub(crate) fn core_snapshot() -> CoreSnapshot {
    if load_settings_once() {
        publish();
    }
    snapshot_locked(&inner())
}

fn record_error(message: impl Into<String>) {
    inner().last_error = message.into();
    publish();
}

fn normalize_config(mut config: CoreConfig) -> Result<CoreConfig, MihomoError> {
    config.log_level = config.log_level.trim().to_ascii_lowercase();
    if !matches!(
        config.log_level.as_str(),
        "silent" | "error" | "warning" | "info" | "debug"
    ) {
        return Err(MihomoError::Other("日志级别无效".into()));
    }

    let tun = &mut config.tun;
    tun.stack = tun.stack.trim().to_ascii_lowercase();
    if !matches!(tun.stack.as_str(), "system" | "gvisor" | "mixed") {
        return Err(MihomoError::Other("TUN 协议栈无效".into()));
    }
    if !(576..=20_000).contains(&tun.mtu) {
        return Err(MihomoError::Other("MTU 必须在 576 到 20000 之间".into()));
    }
    let dns = tun
        .dns
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| {
            value
                .parse::<IpAddr>()
                .map(|_| value.to_string())
                .map_err(|_| MihomoError::Other(format!("DNS 地址无效:{value}")))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if dns.is_empty() {
        return Err(MihomoError::Other("至少需要一个 TUN DNS 地址".into()));
    }
    tun.dns = dns.join(",");

    tun.bypass_mode = tun.bypass_mode.trim().to_ascii_lowercase();
    if !matches!(tun.bypass_mode.as_str(), "off" | "lan" | "custom") {
        return Err(MihomoError::Other("绕过模式无效".into()));
    }
    let mut cidrs = Vec::new();
    for value in tun
        .bypass_custom
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let Some((address, prefix)) = value.split_once('/') else {
            return Err(MihomoError::Other(format!("绕过网段无效:{value}")));
        };
        let address = address
            .parse::<IpAddr>()
            .map_err(|_| MihomoError::Other(format!("绕过网段无效:{value}")))?;
        let prefix = prefix
            .parse::<u8>()
            .map_err(|_| MihomoError::Other(format!("绕过网段无效:{value}")))?;
        let max_prefix = if address.is_ipv4() { 32 } else { 128 };
        if prefix > max_prefix {
            return Err(MihomoError::Other(format!("绕过网段无效:{value}")));
        }
        cidrs.push(format!("{address}/{prefix}"));
    }
    tun.bypass_custom = cidrs.join(",");

    tun.access_mode = tun.access_mode.trim().to_ascii_lowercase();
    if !matches!(
        tun.access_mode.as_str(),
        "accept_all" | "accept_selected" | "reject_selected"
    ) {
        return Err(MihomoError::Other("应用访问模式无效".into()));
    }
    let mut seen = HashSet::new();
    tun.access_packages = std::mem::take(&mut tun.access_packages)
        .into_iter()
        .map(|package| package.trim().to_string())
        .filter(|package| !package.is_empty() && seen.insert(package.clone()))
        .collect();
    config.external_controller = config.external_controller.trim().to_string();
    config.secret = config.secret.trim().to_string();
    if !config.external_controller.is_empty()
        && config.external_controller.parse::<SocketAddr>().is_err()
    {
        return Err(MihomoError::Other("外部控制器地址无效".into()));
    }
    if tun.system_proxy && config.mixed_port == 0 {
        return Err(MihomoError::Other(
            "启用系统代理前需要设置 Mixed 端口".into(),
        ));
    }
    Ok(config)
}

pub(crate) async fn core_update_settings(config: CoreConfig) -> Result<(), MihomoError> {
    let config = match normalize_config(config) {
        Ok(config) => config,
        Err(error) => {
            record_error(error.to_string());
            return Err(error);
        }
    };
    let _operation = core().operation.lock().await;
    let state = inner().state;
    if !matches!(state, CoreState::Stopped | CoreState::Error) {
        let error = MihomoError::Other("请先停止本地引擎再修改设置".into());
        record_error(error.to_string());
        return Err(error);
    }
    #[cfg(target_os = "android")]
    {
        let result: Result<(), MihomoError> = (|| {
            let dir = android::core_files_dir()?;
            std::fs::create_dir_all(&dir)
                .map_err(|e| MihomoError::Other(format!("创建引擎目录失败:{e}")))?;
            android::persist_settings(&dir, &config)?;
            let mut state = inner();
            state.settings = config;
            state.settings_loaded = true;
            state.last_error.clear();
            drop(state);
            publish();
            Ok(())
        })();
        if let Err(error) = &result {
            record_error(error.to_string());
        }
        result
    }
    #[cfg(not(target_os = "android"))]
    {
        drop(config);
        let error = MihomoError::Other("当前平台暂不支持本地引擎".into());
        record_error(error.to_string());
        Err(error)
    }
}

pub(crate) fn core_supported() -> bool {
    cfg!(target_os = "android")
}

pub(crate) fn telemetry_subscribe(kind: &str) -> broadcast::Receiver<String> {
    match kind {
        "traffic" => core().telemetry.traffic.subscribe(),
        "memory" => core().telemetry.memory.subscribe(),
        _ => core().telemetry.logs.subscribe(),
    }
}

pub(crate) async fn core_start() -> Result<(), MihomoError> {
    if !core_supported() {
        return Err(MihomoError::Other("当前平台暂不支持本地引擎".into()));
    }
    let _profiles = core().profile_operation.lock().await;
    let _operation = core().operation.lock().await;
    let config = normalize_config(core_snapshot().settings)?;
    let run_id = {
        let mut state = inner();
        if !matches!(state.state, CoreState::Stopped | CoreState::Error) {
            return Err(MihomoError::Other("引擎已在运行".into()));
        }
        state.run_id = state.run_id.wrapping_add(1).max(1);
        state.state = CoreState::Starting;
        state.settings = config.clone();
        state.tun_attached = false;
        state.tun_ipv6 = false;
        state.platform_vpn_active = false;
        state.last_error.clear();
        state.run_id
    };
    publish();

    #[cfg(target_os = "android")]
    let tun_enabled = config.tun.enabled;
    match platform::prepare_and_start(config, run_id).await {
        Ok(()) => {
            let mut state = inner();
            if state.run_id == run_id
                && state.state == CoreState::Starting
                && !state.settings.tun.enabled
            {
                state.state = CoreState::Running;
                drop(state);
                publish();
            }
            #[cfg(target_os = "android")]
            if tun_enabled {
                tokio::spawn(async move {
                    tokio::time::sleep(VPN_START_TIMEOUT).await;
                    let _operation = core().operation.lock().await;
                    let state = inner();
                    let timed_out = state.run_id == run_id && state.state == CoreState::Starting;
                    drop(state);
                    if timed_out {
                        fail_run(run_id, "VPN 启动超时".into());
                    }
                });
            }
            Ok(())
        }
        Err(error) => {
            platform::teardown().await;
            finish_error(run_id, error.to_string());
            Err(error)
        }
    }
}

pub(crate) async fn core_stop() -> Result<(), MihomoError> {
    if !core_supported() {
        return Ok(());
    }
    let _operation = core().operation.lock().await;
    let run_id = {
        let mut state = inner();
        match state.state {
            CoreState::Stopped | CoreState::Stopping => return Ok(()),
            CoreState::Error => {
                state.state = CoreState::Stopped;
                drop(state);
                publish();
                return Ok(());
            }
            CoreState::Starting | CoreState::Running => {}
        }
        state.run_id = state.run_id.wrapping_add(1).max(1);
        state.state = CoreState::Stopping;
        state.tun_attached = false;
        state.tun_ipv6 = false;
        state.platform_vpn_active = false;
        state.run_id
    };
    publish();

    platform::teardown().await;

    let mut state = inner();
    if state.run_id == run_id {
        state.state = CoreState::Stopped;
        state.platform_vpn_active = false;
        drop(state);
        publish();
    }
    Ok(())
}

pub(crate) async fn core_events(
    sink: crate::frb_generated::StreamSink<CoreSnapshot>,
) -> Result<(), MihomoError> {
    core_snapshot();
    let mut receiver = core().events.subscribe();
    tokio::spawn(async move {
        loop {
            if sink.add(receiver.borrow_and_update().clone()).is_err() {
                break;
            }
            if receiver.changed().await.is_err() {
                break;
            }
        }
    });
    Ok(())
}

#[cfg(target_os = "android")]
pub(crate) fn on_go_event(json: &str) {
    let Ok(value) = serde_json::from_str::<Value>(json) else {
        return;
    };
    let Some(typ) = value.get("type").and_then(|v| v.as_str()) else {
        return;
    };
    match typ {
        "traffic" | "memory" | "logs" => {
            if let Some(data) = value.get("data") {
                let frame = data.to_string();
                let sender = match typ {
                    "traffic" => &core().telemetry.traffic,
                    "memory" => &core().telemetry.memory,
                    _ => &core().telemetry.logs,
                };
                let _ = sender.send(frame);
            }
        }
        _ => {}
    }
}

#[cfg(target_os = "android")]
pub(crate) fn on_network_changed(run_id: u64, name: &str) {
    let name = name.to_string();
    std::thread::spawn(move || {
        let state = inner();
        if state.run_id == run_id && matches!(state.state, CoreState::Starting | CoreState::Running)
        {
            let _ = go_bridge::set_default_interface(&name);
        }
    });
}

#[cfg(target_os = "android")]
pub(crate) fn on_vpn_fd(run_id: u64, fd: i32, platform_ipv6: bool) {
    let (stack, dns, gateway, mtu) = {
        let mut state = inner();
        if state.run_id != run_id || state.state != CoreState::Starting {
            return;
        }
        let tun = &state.settings.tun;
        let gateway = if tun.ipv6 && platform_ipv6 {
            format!("{TUN_GATEWAY4},fdfe:dcba:9876::1/126")
        } else {
            TUN_GATEWAY4.to_string()
        };
        let result = (tun.stack.clone(), tun.dns.clone(), gateway, tun.mtu);
        state.platform_vpn_active = true;
        result
    };
    std::thread::spawn(move || {
        let _operation = core().operation.blocking_lock();
        let state = inner();
        if state.run_id != run_id || state.state != CoreState::Starting {
            return;
        }
        drop(state);
        let result = go_bridge::start_tun(fd, &stack, &gateway, &dns, mtu);
        match result {
            Ok(()) => {
                let mut state = inner();
                if state.run_id != run_id || state.state != CoreState::Starting {
                    drop(state);
                    go_bridge::stop_tun();
                    return;
                }
                state.tun_attached = true;
                state.tun_ipv6 = platform_ipv6;
                state.state = CoreState::Running;
                drop(state);
                publish();
            }
            Err(error) => fail_run(run_id, format!("TUN 启动失败:{error}")),
        }
    });
}

#[cfg(target_os = "android")]
pub(crate) fn on_vpn_error(run_id: u64, message: String) {
    fail_run(run_id, message);
}

#[cfg(target_os = "android")]
pub(crate) fn on_vpn_stopped(run_id: u64) {
    let mut state = inner();
    if state.run_id != run_id {
        return;
    }
    let expected = state.settings.tun.enabled
        && matches!(state.state, CoreState::Starting | CoreState::Running);
    state.platform_vpn_active = false;
    drop(state);
    if expected {
        fail_run(run_id, "VPN 服务已停止".into());
    }
}

#[cfg(target_os = "android")]
fn fail_run(run_id: u64, message: String) {
    let mut state = inner();
    if state.run_id != run_id || !matches!(state.state, CoreState::Starting | CoreState::Running) {
        return;
    }
    state.state = CoreState::Stopping;
    state.tun_attached = false;
    state.tun_ipv6 = false;
    state.platform_vpn_active = false;
    state.last_error = message.clone();
    drop(state);
    publish();
    std::thread::spawn(move || {
        let _operation = core().operation.blocking_lock();
        platform::teardown_blocking();
        finish_error(run_id, message);
    });
}

fn finish_error(run_id: u64, message: String) {
    let mut state = inner();
    if state.run_id != run_id {
        return;
    }
    state.state = CoreState::Error;
    state.tun_attached = false;
    state.tun_ipv6 = false;
    state.platform_vpn_active = false;
    state.last_error = message;
    drop(state);
    publish();
}

#[cfg(target_os = "android")]
pub(crate) fn protect_socket(fd: i32) -> bool {
    let state = inner();
    if state.state == CoreState::Stopping {
        return false;
    }
    let required = state.platform_vpn_active;
    drop(state);
    !required || platform::protect(fd)
}
