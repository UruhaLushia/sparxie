//! JNI bridge between Kotlin platform services and the Rust engine.

use std::path::PathBuf;
use std::sync::OnceLock;

use jni::objects::{JClass, JObject, JString, JValue};
use jni::sys::{jboolean, jint, jlong};
use jni::{JNIEnv, JavaVM};

use crate::MihomoError;
use crate::backend::api::core::{AppInfo, AppWindow};
use crate::backend::api::core::{CoreConfig, TunSettings};

use super::go_bridge;
use super::{on_network_changed, on_vpn_error, on_vpn_fd, on_vpn_stopped};

impl From<jni::errors::Error> for MihomoError {
    fn from(value: jni::errors::Error) -> Self {
        MihomoError::Other(format!("JNI 错误:{value}"))
    }
}

const BRIDGE_CLASS: &str = "zip/atri/sparxie/EngineBridge";

struct JniState {
    vm: JavaVM,
    bridge: jni::objects::GlobalRef,
    files_dir: PathBuf,
}

static JNI_STATE: OnceLock<JniState> = OnceLock::new();
fn jni_state() -> Option<&'static JniState> {
    JNI_STATE.get()
}

fn with_vm<T>(f: impl FnOnce(&mut JNIEnv) -> Result<T, MihomoError>) -> Result<T, MihomoError> {
    let state = jni_state().ok_or_else(|| MihomoError::Other("引擎未初始化".into()))?;
    let mut guard = state
        .vm
        .attach_current_thread()
        .map_err(|e| MihomoError::Other(format!("JNI attach 失败:{e}")))?;
    let result = f(&mut guard);
    drop(guard);
    result
}

fn get_bridge_class<'local>() -> Result<JClass<'local>, MihomoError> {
    let state = jni_state().ok_or_else(|| MihomoError::Other("引擎未初始化".into()))?;
    // The stored GlobalRef owns a strong ref to the class; wrapping its raw
    // handle in a transient JClass for the duration of a single call is safe.
    Ok(unsafe { JClass::from_raw(state.bridge.as_raw()) })
}

fn call_bridge_static(
    env: &mut JNIEnv,
    method: &str,
    signature: &str,
    args: &[jni::objects::JValue],
) -> Result<(), MihomoError> {
    let class = get_bridge_class()?;
    env.call_static_method(class, method, signature, args)
        .map(|_| ())
        .map_err(|e| MihomoError::Other(format!("调用 Kotlin {method} 失败:{e}")))
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_zip_atri_sparxie_EngineBridge_nativeEngineInit(
    mut env: JNIEnv,
    _class: JClass,
    context: JObject,
) {
    let Ok(vm) = env.get_java_vm() else {
        return;
    };

    // Native threads cannot resolve app classes through FindClass.
    let loader = env
        .call_method(&context, "getClassLoader", "()Ljava/lang/ClassLoader;", &[])
        .and_then(|v| v.l());
    let Ok(loader) = loader else { return };
    let Ok(name) = env.new_string(BRIDGE_CLASS) else {
        return;
    };
    let bridge_class = env
        .call_method(
            &loader,
            "loadClass",
            "(Ljava/lang/String;)Ljava/lang/Class;",
            &[(&name).into()],
        )
        .and_then(|v| v.l());
    let Ok(bridge_class) = bridge_class else {
        return;
    };
    let Ok(bridge_ref) = env.new_global_ref(&bridge_class) else {
        return;
    };

    let files_dir = env
        .call_method(&context, "getFilesDir", "()Ljava/io/File;", &[])
        .and_then(|v| v.l())
        .and_then(|file| {
            env.call_method(&file, "getAbsolutePath", "()Ljava/lang/String;", &[])
                .and_then(|s| s.l())
                .and_then(|s| {
                    let jstr = JString::from(s);
                    env.get_string(&jstr)
                        .map(|r| r.to_string_lossy().to_string())
                })
        })
        .map(|s| PathBuf::from(s))
        .unwrap_or_default();

    let state = JniState {
        vm,
        bridge: bridge_ref,
        files_dir,
    };
    if JNI_STATE.set(state).is_err() {
        return;
    }

    if let Err(err) = go_bridge::ensure_loaded() {
        super::record_error(format!("内核加载失败:{err}"));
        return;
    }
    let Ok(core_dir) = core_files_dir() else {
        return;
    };
    let home = core_dir.join("mihomo-home");
    if let Err(error) = std::fs::create_dir_all(&home) {
        super::record_error(format!("创建内核目录失败:{error}"));
        return;
    }
    go_bridge::core_init(&home.to_string_lossy());
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_zip_atri_sparxie_EngineBridge_nativeOnVpnFd(
    _env: JNIEnv,
    _class: JClass,
    run_id: jlong,
    fd: jint,
    ipv6: jboolean,
) {
    on_vpn_fd(run_id as u64, fd as i32, ipv6 != 0);
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_zip_atri_sparxie_EngineBridge_nativeOnVpnError(
    mut env: JNIEnv,
    _class: JClass,
    run_id: jlong,
    message: JString,
) {
    let message = env
        .get_string(&message)
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    on_vpn_error(run_id as u64, message);
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_zip_atri_sparxie_EngineBridge_nativeOnVpnStopped(
    _env: JNIEnv,
    _class: JClass,
    run_id: jlong,
) {
    on_vpn_stopped(run_id as u64);
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_zip_atri_sparxie_EngineBridge_nativeOnNetworkChanged(
    mut env: JNIEnv,
    _class: JClass,
    run_id: jlong,
    name: JString,
) {
    let name = env
        .get_string(&name)
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    on_network_changed(run_id as u64, &name);
}

const LAN_EXCLUDES: [&str; 9] = [
    "10.0.0.0/8",
    "100.64.0.0/10",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "224.0.0.0/4",
    "fc00::/7",
    "fe80::/10",
    "ff00::/8",
];

pub(crate) fn core_files_dir() -> Result<PathBuf, MihomoError> {
    let base = jni_state()
        .map(|state| state.files_dir.clone())
        .filter(|path| !path.as_os_str().is_empty())
        .ok_or_else(|| MihomoError::Other("应用目录不可用".into()))?;
    Ok(base.join("core"))
}

pub(crate) async fn prepare_and_start(config: CoreConfig, run_id: u64) -> Result<(), MihomoError> {
    let dir = core_files_dir()?;
    std::fs::create_dir_all(&dir)
        .map_err(|e| MihomoError::Other(format!("创建内核目录失败:{e}")))?;

    go_bridge::set_override_config(&config)?;
    let config_path = super::configs::materialize_active()?;

    tokio::task::spawn_blocking(move || go_bridge::core_start(&config_path))
        .await
        .map_err(|e| MihomoError::Other(format!("内核启动任务失败:{e}")))??;

    if config.tun.enabled {
        start_vpn(run_id, &config.tun, config.mixed_port)?;
    }
    Ok(())
}

pub(crate) async fn teardown() {
    let _ = tokio::task::spawn_blocking(teardown_blocking).await;
}

pub(crate) fn teardown_blocking() {
    let _ = with_vm(|env| call_bridge_static(env, "stopVpn", "()V", &[]));
    go_bridge::core_stop();
}

pub(crate) fn start_vpn(
    run_id: u64,
    tun: &TunSettings,
    mixed_port: u16,
) -> Result<(), MihomoError> {
    let mut json = serde_json::json!({
        "run_id": run_id,
        "mixed_port": mixed_port,
        "tun": tun,
    });
    let excludes = match tun.bypass_mode.as_str() {
        "lan" => LAN_EXCLUDES
            .iter()
            .filter(|value| tun.ipv6 || !value.contains(':'))
            .map(|value| (*value).to_string())
            .collect(),
        "custom" => tun
            .bypass_custom
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .filter(|value| tun.ipv6 || !value.contains(':'))
            .map(str::to_string)
            .collect::<Vec<_>>(),
        _ => Vec::new(),
    };
    let ranges = if excludes.is_empty() {
        Vec::new()
    } else {
        let excludes = excludes.iter().map(String::as_str).collect::<Vec<_>>();
        go_bridge::compute_route_ranges(&excludes)?
    };
    json["tun"]["excluded_routes"] = serde_json::json!(excludes);
    json["tun"]["route_ranges"] = serde_json::json!(ranges);
    let json = json.to_string();
    with_vm(|env| {
        let arg = env
            .new_string(&json)
            .map_err(|e| MihomoError::Other(format!("JNI 字符串失败:{e}")))?;
        let class = get_bridge_class()?;
        let accepted = env
            .call_static_method(class, "startVpn", "(Ljava/lang/String;)Z", &[(&arg).into()])?
            .z()?;
        if accepted {
            Ok(())
        } else {
            Err(MihomoError::Other("VPN 启动命令未被平台接受".into()))
        }
    })
}

pub(crate) fn protect(fd: i32) -> bool {
    with_vm(|env| {
        let class = get_bridge_class()?;
        env.call_static_method(class, "protect", "(I)Z", &[JValue::Int(fd)])
            .and_then(|value| value.z())
            .map_err(|e| MihomoError::Other(format!("protect 失败:{e}")))
    })
    .unwrap_or(false)
}

pub(crate) fn query_package_name(uid: i32) -> String {
    let result = with_vm(|env| {
        let package = env
            .call_static_method(
                get_bridge_class()?,
                "queryPackage",
                "(I)Ljava/lang/String;",
                &[JValue::Int(uid)],
            )?
            .l()?;
        if package.is_null() {
            return Ok(String::new());
        }
        let jstr = JString::from(package);
        env.get_string(&jstr)
            .map(|s| s.to_string_lossy().to_string())
            .map_err(|e| MihomoError::Other(format!("queryPackage 失败:{e}")))
    });
    result.unwrap_or_default()
}

pub(crate) fn query_uid(protocol: i32, source: &str, target: &str) -> i32 {
    match with_vm(|env| {
        let src = env.new_string(source)?;
        let dst = env.new_string(target)?;
        let uid = env
            .call_static_method(
                get_bridge_class()?,
                "queryUid",
                "(ILjava/lang/String;Ljava/lang/String;)I",
                &[JValue::Int(protocol), (&src).into(), (&dst).into()],
            )?
            .i()
            .map_err(|e| MihomoError::Other(format!("queryUid 失败:{e}")))?;
        Ok(uid)
    }) {
        Ok(uid) => uid,
        Err(_) => -1,
    }
}

static APPS_CACHE: std::sync::OnceLock<std::sync::Mutex<Option<Vec<AppInfo>>>> =
    std::sync::OnceLock::new();

pub(crate) fn list_apps_window(query: &str, offset: u32, limit: u32) -> AppWindow {
    let cache = APPS_CACHE.get_or_init(|| std::sync::Mutex::new(None));
    let mut guard = cache.lock().unwrap_or_else(|e| e.into_inner());
    let all = guard.get_or_insert_with(list_all_apps);
    let q = query.trim().to_lowercase();
    let filtered: Vec<&AppInfo> = if q.is_empty() {
        all.iter().collect()
    } else {
        all.iter()
            .filter(|a| a.label.to_lowercase().contains(&q) || a.package.contains(&q))
            .collect()
    };
    let total = filtered.len() as u32;
    let start = (offset as usize).min(filtered.len());
    let end = start.saturating_add(limit as usize).min(filtered.len());
    AppWindow {
        apps: filtered[start..end].iter().map(|a| (*a).clone()).collect(),
        total,
    }
}

fn list_all_apps() -> Vec<AppInfo> {
    let result = with_vm(|env| {
        let json = env
            .call_static_method(get_bridge_class()?, "listApps", "()Ljava/lang/String;", &[])?
            .l()?;
        if json.is_null() {
            return Ok(Vec::new());
        }
        let jstr = JString::from(json);
        let text = env
            .get_string(&jstr)
            .map(|s| s.to_string_lossy().to_string())
            .map_err(|e| MihomoError::Other(format!("listApps 失败:{e}")))?;
        serde_json::from_str(&text).map_err(|e| MihomoError::InvalidJson(e.to_string()))
    });
    result.unwrap_or_default()
}

pub(crate) fn load_settings() -> Result<Option<CoreConfig>, MihomoError> {
    let dir = core_files_dir()?;
    let path = dir.join("core.json");
    if !path.exists() {
        return Ok(None);
    }
    let text = std::fs::read_to_string(path)
        .map_err(|error| MihomoError::Other(format!("读取设置失败:{error}")))?;
    serde_json::from_str(&text)
        .map(Some)
        .map_err(|error| MihomoError::InvalidJson(format!("本地引擎设置无效:{error}")))
}

pub(crate) fn persist_settings(
    dir: &std::path::Path,
    config: &CoreConfig,
) -> Result<(), MihomoError> {
    let json = serde_json::to_string_pretty(config)
        .map_err(|e| MihomoError::InvalidJson(e.to_string()))?;
    let path = dir.join("core.json");
    let temporary = dir.join("core.json.tmp");
    std::fs::write(&temporary, json)
        .and_then(|_| std::fs::rename(&temporary, &path))
        .map_err(|e| {
            let _ = std::fs::remove_file(temporary);
            MihomoError::Other(format!("保存设置失败:{e}"))
        })
}
