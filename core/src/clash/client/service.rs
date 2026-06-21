use std::{
    env, fs,
    path::{Path, PathBuf},
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use base64::{Engine as _, engine::general_purpose};
use ring::{
    digest,
    rand::{SecureRandom, SystemRandom},
    signature::Ed25519KeyPair,
};
use serde::Deserialize;
use url::{Url, form_urlencoded};

use crate::MihomoError;

const AUTH_PREFIX: &str = "SPARKLE-AUTH-V2";

#[derive(Clone)]
pub(super) struct ServiceAuth {
    key_id: String,
    key_pair: Arc<Ed25519KeyPair>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServiceAuthStore {
    version: u8,
    storage: Option<String>,
    key_id: Option<String>,
    public_key: String,
    private_key: String,
}

impl ServiceAuth {
    pub(super) fn load(auth_path: Option<String>) -> Result<Self, MihomoError> {
        if let Some(path) = auth_path {
            return Self::load_file(Path::new(&path));
        }

        let candidates = default_auth_paths();
        if let Some(path) = candidates.iter().find(|path| path.exists()) {
            return Self::load_file(path);
        }

        Err(MihomoError::Other(format!(
            "未找到 Sparkle service-auth.json: {}",
            candidates
                .iter()
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>()
                .join(", ")
        )))
    }

    fn load_file(path: &Path) -> Result<Self, MihomoError> {
        let text = fs::read_to_string(path).map_err(|e| {
            MihomoError::Other(format!(
                "读取 Sparkle service-auth.json 失败 {}: {e}",
                path.display()
            ))
        })?;
        let store: ServiceAuthStore = serde_json::from_str(&text).map_err(|e| {
            MihomoError::Other(format!(
                "解析 Sparkle service-auth.json 失败 {}: {e}",
                path.display()
            ))
        })?;
        if store.version != 2 || store.storage.as_deref() != Some("plain") {
            return Err(MihomoError::Other(
                "Sparkle service-auth.json 格式不支持".into(),
            ));
        }

        let public_der = general_purpose::STANDARD
            .decode(store.public_key.trim())
            .map_err(|e| MihomoError::Other(format!("Sparkle 服务公钥无效:{e}")))?;
        let computed_key_id = hex::encode(digest::digest(&digest::SHA256, &public_der).as_ref());
        let key_id = store
            .key_id
            .filter(|v| !v.trim().is_empty())
            .unwrap_or_else(|| computed_key_id.clone());
        if key_id != computed_key_id {
            return Err(MihomoError::Other(
                "Sparkle 服务鉴权密钥 ID 与公钥不匹配".into(),
            ));
        }

        let private_der = pem_body(&store.private_key)?;
        let key_pair = Ed25519KeyPair::from_pkcs8_maybe_unchecked(&private_der)
            .map_err(|_| MihomoError::Other("Sparkle 服务私钥无效".into()))?;

        Ok(Self {
            key_id,
            key_pair: Arc::new(key_pair),
        })
    }

    pub(super) fn headers(
        &self,
        method: &str,
        path_with_query: &str,
        body: &[u8],
    ) -> Result<Vec<(&'static str, String)>, MihomoError> {
        let body_hash = hex::encode(digest::digest(&digest::SHA256, body).as_ref());
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| MihomoError::Other(format!("系统时间无效:{e}")))?
            .as_millis()
            .to_string();
        let nonce = nonce()?;
        let canonical = canonical_request(
            method,
            path_with_query,
            &timestamp,
            &nonce,
            &self.key_id,
            &body_hash,
        )?;
        let signature = self.key_pair.sign(canonical.as_bytes());

        Ok(vec![
            ("X-Auth-Version", "2".into()),
            ("X-Key-Id", self.key_id.clone()),
            ("X-Nonce", nonce),
            ("X-Content-SHA256", body_hash),
            ("X-Timestamp", timestamp),
            (
                "X-Signature",
                general_purpose::STANDARD.encode(signature.as_ref()),
            ),
        ])
    }

    pub(super) fn key_id(&self) -> &str {
        &self.key_id
    }
}

fn pem_body(pem: &str) -> Result<Vec<u8>, MihomoError> {
    let body = pem
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with("-----"))
        .collect::<String>();
    general_purpose::STANDARD
        .decode(body)
        .map_err(|e| MihomoError::Other(format!("Sparkle 服务私钥 PEM 无效:{e}")))
}

fn canonical_request(
    method: &str,
    path_with_query: &str,
    timestamp: &str,
    nonce: &str,
    key_id: &str,
    body_hash: &str,
) -> Result<String, MihomoError> {
    let url = Url::parse(&format!(
        "http://localhost/{}",
        path_with_query.trim_start_matches('/')
    ))
    .map_err(|e| MihomoError::InvalidUrl(format!("sparkle service uri: {e}")))?;
    let path = if url.path().is_empty() {
        "/"
    } else {
        url.path()
    };
    let query = canonical_query(url.query().unwrap_or(""));

    let method = method.to_ascii_uppercase();

    Ok([
        AUTH_PREFIX,
        timestamp,
        nonce,
        key_id,
        &method,
        path,
        &query,
        body_hash,
    ]
    .join("\n"))
}

fn canonical_query(raw: &str) -> String {
    let mut pairs = form_urlencoded::parse(raw.as_bytes())
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect::<Vec<_>>();
    pairs.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));

    let mut serializer = form_urlencoded::Serializer::new(String::new());
    for (key, value) in pairs {
        serializer.append_pair(&key, &value);
    }
    serializer.finish()
}

fn nonce() -> Result<String, MihomoError> {
    let mut bytes = [0_u8; 16];
    SystemRandom::new()
        .fill(&mut bytes)
        .map_err(|_| MihomoError::Other("生成 Sparkle 服务 nonce 失败".into()))?;
    Ok(general_purpose::URL_SAFE_NO_PAD.encode(bytes))
}

fn default_auth_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    #[cfg(target_os = "windows")]
    {
        if let Some(appdata) = env::var_os("APPDATA") {
            paths.push(
                PathBuf::from(appdata)
                    .join("Sparkle")
                    .join("service-auth.json"),
            );
        }
        if let Some(profile) = env::var_os("USERPROFILE") {
            paths.push(
                PathBuf::from(profile)
                    .join("AppData")
                    .join("Roaming")
                    .join("Sparkle")
                    .join("service-auth.json"),
            );
        }
    }

    #[cfg(target_os = "macos")]
    if let Some(home) = env::var_os("HOME") {
        paths.push(
            PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join("Sparkle")
                .join("service-auth.json"),
        );
    }

    #[cfg(all(unix, not(target_os = "macos")))]
    {
        if let Some(config_home) = env::var_os("XDG_CONFIG_HOME") {
            let config_home = PathBuf::from(config_home);
            paths.push(config_home.join("Sparkle").join("service-auth.json"));
            paths.push(config_home.join("sparkle").join("service-auth.json"));
        }
        if let Some(home) = env::var_os("HOME") {
            let config_home = PathBuf::from(home).join(".config");
            paths.push(config_home.join("Sparkle").join("service-auth.json"));
            paths.push(config_home.join("sparkle").join("service-auth.json"));
        }
    }

    paths
}
