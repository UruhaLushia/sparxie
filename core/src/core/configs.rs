//! Rust-owned kernel profile store.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::MihomoError;
use crate::backend::api::core::{CoreConfigProfile, CoreProfileKind};

use super::android::core_files_dir;

const BUILTIN_DIRECT_ID: &str = "builtin-direct";
const BUILTIN_DIRECT_NAME: &str = "内置直连";

const BUILTIN_DIRECT_YAML: &str = r#"
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
    - 8.8.8.8
proxies: []
rules:
  - MATCH,DIRECT
"#;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct ProfileIndex {
    profiles: Vec<CoreConfigProfile>,
    active: String,
}

fn profiles_dir() -> Result<PathBuf, MihomoError> {
    let dir = core_files_dir()?;
    let dir = dir.join("configs");
    std::fs::create_dir_all(&dir)
        .map_err(|e| MihomoError::Other(format!("创建配置目录失败:{e}")))?;
    Ok(dir)
}

fn index_path(dir: &Path) -> PathBuf {
    dir.join("index.json")
}

fn load_index(dir: &Path) -> Result<ProfileIndex, MihomoError> {
    let path = index_path(dir);
    if !path.exists() {
        return Ok(ProfileIndex::default());
    }
    let text = std::fs::read_to_string(path)
        .map_err(|error| MihomoError::Other(format!("读取配置索引失败:{error}")))?;
    serde_json::from_str(&text)
        .map_err(|error| MihomoError::InvalidJson(format!("配置索引无效:{error}")))
}

fn save_index(dir: &Path, index: &ProfileIndex) -> Result<(), MihomoError> {
    let json =
        serde_json::to_string_pretty(index).map_err(|e| MihomoError::InvalidJson(e.to_string()))?;
    write_atomic(&index_path(dir), json.as_bytes())
        .map_err(|e| MihomoError::Other(format!("保存配置索引失败:{e}")))
}

fn ensure_builtin(dir: &Path, index: &mut ProfileIndex) -> Result<(), MihomoError> {
    let path = dir.join(format!("{BUILTIN_DIRECT_ID}.yaml"));
    if !path.exists() {
        write_atomic(&path, BUILTIN_DIRECT_YAML.as_bytes())
            .map_err(|e| MihomoError::Other(format!("写入内置配置失败:{e}")))?;
    }
    if !index.profiles.iter().any(|p| p.id == BUILTIN_DIRECT_ID) {
        index.profiles.push(CoreConfigProfile {
            id: BUILTIN_DIRECT_ID.to_string(),
            name: BUILTIN_DIRECT_NAME.to_string(),
            kind: CoreProfileKind::Builtin,
            source_url: String::new(),
            user_agent: String::new(),
            etag: String::new(),
            active: false,
        });
    }
    if index.active.is_empty() {
        index.active = BUILTIN_DIRECT_ID.to_string();
    }
    Ok(())
}

pub(crate) fn list() -> Result<Vec<CoreConfigProfile>, MihomoError> {
    let dir = profiles_dir()?;
    let mut index = load_index(&dir)?;
    ensure_builtin(&dir, &mut index)?;
    let active = index.active.clone();
    for profile in &mut index.profiles {
        profile.active = profile.id == active;
    }
    save_index(&dir, &index)?;
    index
        .profiles
        .retain(|profile| profile.kind == CoreProfileKind::Imported);
    index.profiles.sort_by(|left, right| {
        right
            .active
            .cmp(&left.active)
            .then_with(|| left.name.cmp(&right.name))
    });
    Ok(index.profiles)
}

pub(crate) fn active_path() -> Result<PathBuf, MihomoError> {
    let dir = profiles_dir()?;
    let index = load_index(&dir)?;
    let id = if index.active.is_empty() {
        BUILTIN_DIRECT_ID.to_string()
    } else {
        index.active.clone()
    };
    Ok(dir.join(format!("{id}.yaml")))
}

pub(crate) fn active_profile() -> Result<(CoreConfigProfile, String), MihomoError> {
    let dir = profiles_dir()?;
    let mut index = load_index(&dir)?;
    ensure_builtin(&dir, &mut index)?;
    let id = if index.active.is_empty() {
        BUILTIN_DIRECT_ID.to_string()
    } else {
        index.active.clone()
    };
    let profile = index
        .profiles
        .iter()
        .find(|p| p.id == id)
        .cloned()
        .ok_or_else(|| MihomoError::Other("激活的配置不存在".into()))?;
    let path = dir.join(format!("{id}.yaml"));
    let content = std::fs::read_to_string(&path)
        .map_err(|e| MihomoError::Other(format!("读取配置失败:{e}")))?;
    Ok((profile, content))
}

pub(crate) fn set_active(id: &str) -> Result<(), MihomoError> {
    let dir = profiles_dir()?;
    let mut index = load_index(&dir)?;
    ensure_builtin(&dir, &mut index)?;
    if !index.profiles.iter().any(|p| p.id == id) {
        return Err(MihomoError::Other("配置不存在".into()));
    }
    index.active = id.to_string();
    save_index(&dir, &index)
}

pub(crate) async fn import(
    url: &str,
    text: &str,
    name_hint: &str,
    user_agent: &str,
) -> Result<CoreConfigProfile, MihomoError> {
    let mut fetched_etag = None;
    let mut remote_filename = None;
    let content = if !url.trim().is_empty() {
        let fetched = fetch_config(url, Some(user_agent), None).await?;
        fetched_etag = fetched.etag.clone();
        remote_filename = fetched.filename.clone();
        fetched.content
    } else {
        text.to_string()
    };
    if content.trim().is_empty() {
        return Err(MihomoError::Other("配置内容为空".into()));
    }
    crate::core::go_bridge::validate_config(&content)?;

    let dir = profiles_dir()?;
    let mut index = load_index(&dir)?;
    ensure_builtin(&dir, &mut index)?;

    let id_source = if name_hint.trim().is_empty() {
        remote_filename.as_deref().unwrap_or_default()
    } else {
        name_hint
    };
    let base_id = slug(id_source);
    let mut id = base_id.clone();
    let mut n = 1;
    while index.profiles.iter().any(|p| p.id == id) {
        n += 1;
        id = format!("{base_id}-{n}");
    }
    if id.is_empty() {
        id = format!(
            "profile-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0)
        );
    }

    let profile_path = dir.join(format!("{id}.yaml"));
    write_atomic(&profile_path, content.as_bytes())
        .map_err(|e| MihomoError::Other(format!("保存配置失败:{e}")))?;
    let name = {
        let hint = name_hint.trim();
        if !hint.is_empty() {
            hint.to_string()
        } else if let Some(f) = remote_filename {
            f
        } else {
            "导入配置".to_string()
        }
    };
    let activate = !index
        .profiles
        .iter()
        .any(|profile| profile.kind == CoreProfileKind::Imported);
    let profile = CoreConfigProfile {
        id: id.clone(),
        name,
        kind: CoreProfileKind::Imported,
        source_url: url.trim().to_string(),
        user_agent: user_agent.trim().to_string(),
        etag: fetched_etag.unwrap_or_default(),
        active: activate,
    };
    index.profiles.push(profile.clone());
    if activate {
        index.active = id;
    }
    if let Err(error) = save_index(&dir, &index) {
        let _ = std::fs::remove_file(profile_path);
        return Err(error);
    }
    Ok(profile)
}

pub(crate) fn delete(id: &str) -> Result<bool, MihomoError> {
    let dir = profiles_dir()?;
    let mut index = load_index(&dir)?;
    ensure_builtin(&dir, &mut index)?;
    let Some(profile) = index.profiles.iter().find(|p| p.id == id).cloned() else {
        return Ok(false);
    };
    if profile.kind == CoreProfileKind::Builtin {
        return Err(MihomoError::Other("内置配置不可删除".into()));
    }
    index.profiles.retain(|p| p.id != id);
    let active_changed = index.active == id;
    if active_changed {
        index.active = index
            .profiles
            .iter()
            .find(|p| p.kind != CoreProfileKind::Builtin)
            .map(|p| p.id.clone())
            .unwrap_or_else(|| BUILTIN_DIRECT_ID.to_string());
    }
    save_index(&dir, &index)?;
    let _ = std::fs::remove_file(dir.join(format!("{id}.yaml")));
    Ok(active_changed)
}

pub(crate) fn edit(id: &str, name: &str, url: &str, user_agent: &str) -> Result<(), MihomoError> {
    let dir = profiles_dir()?;
    let mut index = load_index(&dir)?;
    let Some(profile) = index.profiles.iter_mut().find(|p| p.id == id) else {
        return Err(MihomoError::Other("配置不存在".into()));
    };
    if profile.kind == CoreProfileKind::Builtin {
        return Err(MihomoError::Other("内置配置不可编辑".into()));
    }
    let name = name.trim();
    if name.is_empty() {
        return Err(MihomoError::Other("名称不能为空".into()));
    }
    profile.name = name.to_string();
    profile.source_url = url.trim().to_string();
    profile.user_agent = user_agent.trim().to_string();
    save_index(&dir, &index)
}

pub(crate) async fn update(id: &str) -> Result<(), MihomoError> {
    let dir = profiles_dir()?;
    let index = load_index(&dir)?;
    let Some(profile) = index.profiles.iter().find(|p| p.id == id) else {
        return Err(MihomoError::Other("配置不存在".into()));
    };
    if profile.kind == CoreProfileKind::Builtin || profile.source_url.trim().is_empty() {
        return Err(MihomoError::Other("该配置没有订阅地址".into()));
    }
    let fetched = fetch_config(
        &profile.source_url,
        Some(&profile.user_agent),
        Some(&profile.etag),
    )
    .await?;
    if fetched.not_modified {
        return Ok(());
    }
    if fetched.content.trim().is_empty() {
        return Err(MihomoError::Other("配置内容为空".into()));
    }
    crate::core::go_bridge::validate_config(&fetched.content)?;
    write_atomic(&dir.join(format!("{id}.yaml")), fetched.content.as_bytes())
        .map_err(|e| MihomoError::Other(format!("保存配置失败:{e}")))?;
    let mut index = load_index(&dir)?;
    if let Some(p) = index.profiles.iter_mut().find(|p| p.id == id) {
        if let Some(tag) = &fetched.etag {
            p.etag = tag.clone();
        }
    }
    save_index(&dir, &index)
}

fn download_ua(custom: Option<&str>) -> Option<String> {
    let custom = custom.map(str::trim).filter(|s| !s.is_empty());
    if let Some(ua) = custom {
        return Some(ua.to_string());
    }
    #[cfg(target_os = "android")]
    {
        use crate::core::go_bridge;
        if let Ok(value) = go_bridge::query_state("version") {
            if let Some(version) = value.get("version").and_then(|v| v.as_str()) {
                return Some(format!("clash.meta/{version}"));
            }
        }
    }
    None
}

struct FetchedConfig {
    content: String,
    filename: Option<String>,
    etag: Option<String>,
    not_modified: bool,
}

async fn fetch_config(
    url: &str,
    user_agent: Option<&str>,
    etag: Option<&str>,
) -> Result<FetchedConfig, MihomoError> {
    let client = reqwest::Client::builder()
        .build()
        .map_err(|e| MihomoError::Network(e.to_string()))?;
    let mut request = client.get(url);
    if let Some(ua) = download_ua(user_agent) {
        request = request.header(reqwest::header::USER_AGENT, ua);
    }
    if let Some(tag) = etag.filter(|t| !t.trim().is_empty()) {
        request = request.header(reqwest::header::IF_NONE_MATCH, tag.trim());
    }
    let response = request
        .send()
        .await
        .map_err(|e| MihomoError::Network(e.to_string()))?;
    let status = response.status();
    if status == reqwest::StatusCode::NOT_MODIFIED {
        return Ok(FetchedConfig {
            content: String::new(),
            filename: None,
            etag: None,
            not_modified: true,
        });
    }
    let filename = response
        .headers()
        .get(reqwest::header::CONTENT_DISPOSITION)
        .and_then(|v| v.to_str().ok())
        .and_then(parse_content_disposition);
    let etag = response
        .headers()
        .get(reqwest::header::ETAG)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim().to_string());
    let text = response
        .text()
        .await
        .map_err(|e| MihomoError::Network(e.to_string()))?;
    if !status.is_success() {
        return Err(MihomoError::Upstream {
            status: status.as_u16(),
            body: text,
        });
    }
    Ok(FetchedConfig {
        content: text,
        filename,
        etag,
        not_modified: false,
    })
}

/// Prefers RFC 5987 `filename*` over plain `filename`.
fn parse_content_disposition(value: &str) -> Option<String> {
    for part in value.split(';').skip(1) {
        let part = part.trim();
        if let Some(rest) = part.strip_prefix("filename*=") {
            let encoded = rest.trim().trim_matches('"');
            let name = encoded.split("''").nth(1).unwrap_or(encoded);
            if let Ok(decoded) = percent_decode(name) {
                if !decoded.trim().is_empty() {
                    return Some(decoded.trim().to_string());
                }
            }
        }
    }
    for part in value.split(';').skip(1) {
        let part = part.trim();
        if let Some(rest) = part.strip_prefix("filename=") {
            let name = rest.trim().trim_matches('"');
            if !name.is_empty() {
                return Some(name.to_string());
            }
        }
    }
    None
}

fn percent_decode(input: &str) -> Result<String, std::string::FromUtf8Error> {
    let bytes: Vec<u8> = input.as_bytes().to_vec();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hi = (bytes[i + 1] as char).to_digit(16);
            let lo = (bytes[i + 2] as char).to_digit(16);
            if let (Some(h), Some(l)) = (hi, lo) {
                out.push((h * 16 + l) as u8);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out)
}

fn slug(value: &str) -> String {
    let mut result = String::new();
    for ch in value.trim().chars() {
        if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
            result.push(ch.to_ascii_lowercase());
        } else if !result.ends_with('-') {
            result.push('-');
        }
    }
    result.trim_matches('-').to_string()
}

pub(crate) fn materialize_active() -> Result<String, MihomoError> {
    let (_, content) = active_profile()?;
    let runtime_dir = core_files_dir()?.join("runtime");
    std::fs::create_dir_all(&runtime_dir)
        .map_err(|e| MihomoError::Other(format!("创建内核目录失败:{e}")))?;
    let path = runtime_dir.join("active.yaml");
    write_atomic(&path, content.as_bytes())
        .map_err(|e| MihomoError::Other(format!("写入运行配置失败:{e}")))?;
    Ok(path.to_string_lossy().to_string())
}

fn write_atomic(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    let temporary = path.with_extension(format!(
        "tmp-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|value| value.as_nanos())
            .unwrap_or_default()
    ));
    std::fs::write(&temporary, contents)?;
    match std::fs::rename(&temporary, path) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _ = std::fs::remove_file(temporary);
            Err(error)
        }
    }
}
