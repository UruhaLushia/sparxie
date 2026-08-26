//! Dynamic cgo bridge for `libmihomo.so`.

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::sync::OnceLock;

use libc::{RTLD_NOW, dlerror, dlopen, dlsym};

use crate::MihomoError;

use super::on_go_event;

type FnVoid = unsafe extern "C" fn();
type FnStrC = unsafe extern "C" fn(*const c_char) -> c_int;
type FnOverrideConfig = unsafe extern "C" fn(
    c_int,
    c_int,
    c_int,
    c_int,
    *const c_char,
    *const c_char,
    *const c_char,
) -> c_int;
type FnC = unsafe extern "C" fn() -> c_int;
type FnTun =
    unsafe extern "C" fn(c_int, *const c_char, *const c_char, *const c_char, c_int) -> *mut c_char;
type FnCallbacks = unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void, *mut c_void);
type FnInit = unsafe extern "C" fn(*const c_char);
type FnStrPtr = unsafe extern "C" fn(*const c_char) -> *mut c_char;
type FnStrStr = unsafe extern "C" fn(*const c_char, *const c_char) -> c_int;
type FnDelay =
    unsafe extern "C" fn(*const c_char, *const c_char, c_int, *const c_char) -> *mut c_char;

struct Symbols {
    set_callbacks: FnCallbacks,
    core_init: FnInit,
    core_start: FnStrPtr,
    core_stop: FnVoid,
    start_tun: FnTun,
    stop_tun: FnVoid,
    query_state: FnStrPtr,
    change_proxy: FnStrStr,
    close_connection: FnStrC,
    close_all_connections: FnC,
    patch_config: FnStrC,
    reload_config: FnStrPtr,
    set_default_interface: FnStrC,
    set_override_config: FnOverrideConfig,
    compute_route_ranges: FnStrPtr,
    test_delay: FnDelay,
    validate_config: FnStrPtr,
    update_provider: FnStrC,
    update_rule_provider: FnStrC,
    unfix_proxy: FnStrC,
    flush_fake_ip: FnC,
    flush_dns: FnC,
}

static GO: OnceLock<Result<Symbols, String>> = OnceLock::new();

fn symbols() -> Result<&'static Symbols, MihomoError> {
    match GO.get_or_init(|| load().map_err(|e| e.to_string())) {
        Ok(s) => Ok(s),
        Err(e) => Err(MihomoError::Other(e.clone())),
    }
}

unsafe fn sym<T>(handle: *mut libc::c_void, name: &[u8]) -> Result<T, MihomoError> {
    // SAFETY: handle came from dlopen; name is a NUL-terminated C string.
    let ptr = unsafe { dlsym(handle, name.as_ptr().cast()) };
    if ptr.is_null() {
        return Err(MihomoError::Other(format!(
            "内核缺少导出符号 {}",
            String::from_utf8_lossy(&name[..name.len() - 1])
        )));
    }
    // SAFETY: dlsym returned a valid function pointer of type T.
    Ok(unsafe { std::mem::transmute_copy(&ptr) })
}

fn load() -> Result<Symbols, MihomoError> {
    unsafe {
        dlerror();
        let handle = dlopen(c"libmihomo.so".as_ptr(), RTLD_NOW);
        if handle.is_null() {
            let error = dlerror();
            let message = if error.is_null() {
                "未知错误".into()
            } else {
                CStr::from_ptr(error).to_string_lossy().into_owned()
            };
            return Err(MihomoError::Other(format!(
                "加载 libmihomo.so 失败:{message}"
            )));
        }
        let result = Symbols {
            set_callbacks: sym(handle, b"setCallbacks\0")?,
            core_init: sym(handle, b"coreInit\0")?,
            core_start: sym(handle, b"coreStart\0")?,
            core_stop: sym(handle, b"coreStop\0")?,
            start_tun: sym(handle, b"startTun\0")?,
            stop_tun: sym(handle, b"stopTun\0")?,
            query_state: sym(handle, b"queryState\0")?,
            change_proxy: sym(handle, b"changeProxy\0")?,
            close_connection: sym(handle, b"closeConnection\0")?,
            close_all_connections: sym(handle, b"closeAllConnections\0")?,
            patch_config: sym(handle, b"patchConfig\0")?,
            reload_config: sym(handle, b"reloadConfig\0")?,
            set_default_interface: sym(handle, b"setDefaultInterface\0")?,
            set_override_config: sym(handle, b"setOverrideConfig\0")?,
            compute_route_ranges: sym(handle, b"computeRouteRanges\0")?,
            test_delay: sym(handle, b"testDelay\0")?,
            validate_config: sym(handle, b"validateConfig\0")?,
            update_provider: sym(handle, b"updateProvider\0")?,
            update_rule_provider: sym(handle, b"updateRuleProvider\0")?,
            unfix_proxy: sym(handle, b"unfixProxy\0")?,
            flush_fake_ip: sym(handle, b"flushFakeIp\0")?,
            flush_dns: sym(handle, b"flushDns\0")?,
        };
        Ok(result)
    }
}

pub(crate) fn ensure_loaded() -> Result<(), MihomoError> {
    let syms = symbols()?;
    unsafe {
        (syms.set_callbacks)(
            trampoline_mark as *mut c_void,
            trampoline_query_uid as *mut c_void,
            trampoline_event as *mut c_void,
            trampoline_resolve_package as *mut c_void,
        );
    }
    Ok(())
}

extern "C" fn trampoline_mark(_ctx: *mut c_void, fd: c_int) -> c_int {
    crate::core::protect_socket(fd as i32) as c_int
}

extern "C" fn trampoline_query_uid(
    _ctx: *mut c_void,
    protocol: c_int,
    source: *const c_char,
    target: *const c_char,
) -> c_int {
    if source.is_null() || target.is_null() {
        return -1;
    }
    let source = unsafe { CStr::from_ptr(source) }
        .to_string_lossy()
        .to_string();
    let target = unsafe { CStr::from_ptr(target) }
        .to_string_lossy()
        .to_string();
    crate::core::platform::query_uid(protocol as i32, &source, &target)
}

extern "C" fn trampoline_resolve_package(
    _ctx: *mut c_void,
    uid: c_int,
    buf: *mut c_char,
    buf_len: c_int,
) {
    let package = crate::core::platform::query_package_name(uid as i32);
    if buf.is_null() || buf_len <= 0 {
        return;
    }
    let len = (package.len() as c_int).min(buf_len - 1).max(0);
    unsafe {
        std::ptr::copy_nonoverlapping(package.as_ptr().cast::<c_char>(), buf, len as usize);
        *buf.add(len as usize) = 0;
    }
}

extern "C" fn trampoline_event(_ctx: *mut c_void, json: *const c_char) {
    if json.is_null() {
        return;
    }
    let json = unsafe { CStr::from_ptr(json) }
        .to_string_lossy()
        .to_string();
    on_go_event(&json);
}

fn cstring(value: &str) -> Result<CString, MihomoError> {
    CString::new(value).map_err(|e| MihomoError::Other(format!("无效字符串:{e}")))
}

pub(crate) fn core_init(home: &str) {
    let Ok(syms) = symbols() else { return };
    let Ok(home) = cstring(home) else { return };
    unsafe { (syms.core_init)(home.as_ptr()) }
}

pub(crate) fn core_start(config_path: &str) -> Result<(), MihomoError> {
    let syms = symbols()?;
    let config_path = cstring(config_path)?;
    let error = unsafe { (syms.core_start)(config_path.as_ptr()) };
    operation_result(error)
}

pub(crate) fn core_stop() {
    if let Ok(syms) = symbols() {
        unsafe { (syms.core_stop)() }
    }
}

pub(crate) fn start_tun(
    fd: i32,
    stack: &str,
    gateway: &str,
    dns: &str,
    mtu: u32,
) -> Result<(), MihomoError> {
    let syms = symbols()?;
    let stack = cstring(stack)?;
    let gateway = cstring(gateway)?;
    let dns = cstring(dns)?;
    let error = unsafe {
        (syms.start_tun)(
            fd,
            stack.as_ptr(),
            gateway.as_ptr(),
            dns.as_ptr(),
            mtu as c_int,
        )
    };
    operation_result(error)
}

pub(crate) fn stop_tun() {
    if let Ok(syms) = symbols() {
        unsafe { (syms.stop_tun)() }
    }
}

/// Take a Go-owned C string (must be freed with libc::free).
unsafe fn take_cstring(ptr: *mut c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
    unsafe { libc::free(ptr.cast()) };
    Some(value)
}

fn operation_result(error: *mut c_char) -> Result<(), MihomoError> {
    match unsafe { take_cstring(error) } {
        Some(message) => Err(MihomoError::Other(message)),
        None => Ok(()),
    }
}

pub(crate) fn query_state(method: &str) -> Result<serde_json::Value, MihomoError> {
    let syms = symbols()?;
    let method = cstring(method)?;
    let raw = unsafe { (syms.query_state)(method.as_ptr()) };
    let Some(json) = (unsafe { take_cstring(raw) }) else {
        return Err(MihomoError::Other("内核查询无响应".into()));
    };
    let value: serde_json::Value = serde_json::from_str(&json)
        .map_err(|e| MihomoError::InvalidJson(format!("{json}: {e}")))?;
    if let Some(error) = value.get("error").and_then(|v| v.as_str()) {
        return Err(MihomoError::Upstream {
            status: 400,
            body: error.to_string(),
        });
    }
    Ok(value)
}

pub(crate) fn validate_config(text: &str) -> Result<(), MihomoError> {
    let syms = symbols()?;
    let text = cstring(text)?;
    let raw = unsafe { (syms.validate_config)(text.as_ptr()) };
    if raw.is_null() {
        return Ok(());
    }
    let message = unsafe { take_cstring(raw) }.unwrap_or_default();
    Err(MihomoError::InvalidJson(message))
}

fn call_code(f: impl FnOnce(&Symbols) -> i32) -> Result<(), MihomoError> {
    let syms = symbols()?;
    if f(syms) == 0 {
        Ok(())
    } else {
        Err(MihomoError::Other("内核操作失败".into()))
    }
}

pub(crate) fn change_proxy(group: &str, name: &str) -> Result<(), MihomoError> {
    let group = cstring(group)?;
    let name = cstring(name)?;
    call_code(|s| unsafe { (s.change_proxy)(group.as_ptr(), name.as_ptr()) })
}

pub(crate) fn close_connection(id: &str) -> Result<(), MihomoError> {
    let id = cstring(id)?;
    call_code(|s| unsafe { (s.close_connection)(id.as_ptr()) })
}

pub(crate) fn close_all_connections() -> Result<(), MihomoError> {
    call_code(|s| unsafe { (s.close_all_connections)() })
}

pub(crate) fn patch_config(body: &str) -> Result<(), MihomoError> {
    let body = cstring(body)?;
    call_code(|s| unsafe { (s.patch_config)(body.as_ptr()) })
}

pub(crate) fn reload_config(path: &str) -> Result<(), MihomoError> {
    let syms = symbols()?;
    let path = cstring(path)?;
    let error = unsafe { (syms.reload_config)(path.as_ptr()) };
    operation_result(error)
}

pub(crate) fn set_default_interface(name: &str) -> Result<(), MihomoError> {
    let name = cstring(name)?;
    call_code(|s| unsafe { (s.set_default_interface)(name.as_ptr()) })
}

pub(crate) fn compute_route_ranges(excludes: &[&str]) -> Result<Vec<String>, MihomoError> {
    let body = cstring(&serde_json::to_string(excludes)?)?;
    let syms = symbols()?;
    let raw = unsafe { (syms.compute_route_ranges)(body.as_ptr()) };
    let Some(text) = (unsafe { take_cstring(raw) }) else {
        return Err(MihomoError::Other("计算绕过路由无响应".into()));
    };
    serde_json::from_str(&text).map_err(Into::into)
}

pub(crate) fn set_override_config(
    config: &crate::backend::api::core::CoreConfig,
) -> Result<(), MihomoError> {
    let controller = cstring(&config.external_controller)?;
    let secret = cstring(&config.secret)?;
    let log_level = cstring(&config.log_level)?;
    call_code(|s| unsafe {
        (s.set_override_config)(
            config.mixed_port as c_int,
            config.port as c_int,
            config.socks_port as c_int,
            config.allow_lan as c_int,
            controller.as_ptr(),
            secret.as_ptr(),
            log_level.as_ptr(),
        )
    })
}

pub(crate) fn unfix_proxy(name: &str) -> Result<(), MihomoError> {
    let name = cstring(name)?;
    call_code(|s| unsafe { (s.unfix_proxy)(name.as_ptr()) })
}

pub(crate) fn update_provider(name: &str) -> Result<(), MihomoError> {
    let name = cstring(name)?;
    call_code(|s| unsafe { (s.update_provider)(name.as_ptr()) })
}

pub(crate) fn update_rule_provider(name: &str) -> Result<(), MihomoError> {
    let name = cstring(name)?;
    call_code(|s| unsafe { (s.update_rule_provider)(name.as_ptr()) })
}

pub(crate) fn flush_fake_ip() -> Result<(), MihomoError> {
    call_code(|s| unsafe { (s.flush_fake_ip)() })
}

pub(crate) fn flush_dns() -> Result<(), MihomoError> {
    call_code(|s| unsafe { (s.flush_dns)() })
}

pub(crate) fn test_delay(name: &str, url: &str, timeout_ms: i32) -> Result<u64, MihomoError> {
    let result = test_delay_inner(name, url, timeout_ms);
    if let Err(err) = &result {
        #[cfg(target_os = "android")]
        crate::core::push_log(format!("DELAY_ERR name={name} err={err}"));
    }
    result
}

fn test_delay_inner(name: &str, url: &str, timeout_ms: i32) -> Result<u64, MihomoError> {
    let syms = symbols()?;
    let name = cstring(name)?;
    let url = cstring(url)?;
    let raw =
        unsafe { (syms.test_delay)(name.as_ptr(), url.as_ptr(), timeout_ms, std::ptr::null()) };
    let Some(json) = (unsafe { take_cstring(raw) }) else {
        return Err(MihomoError::Other("延迟测试无响应".into()));
    };
    let value: serde_json::Value =
        serde_json::from_str(&json).map_err(|e| MihomoError::InvalidJson(e.to_string()))?;
    if let Some(error) = value.get("error").and_then(|v| v.as_str()) {
        return Err(MihomoError::Other(error.to_string()));
    }
    value
        .get("delay")
        .and_then(|v| v.as_u64())
        .ok_or_else(|| MihomoError::Other("延迟测试无结果".into()))
}
