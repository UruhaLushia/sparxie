use serde_json::Value;

use crate::MihomoError;
use crate::client::MihomoClient;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BackendKind {
    Mihomo,
    Stash,
    Unknown,
}

#[derive(Clone, Debug)]
pub(crate) struct BackendProbe {
    pub kind: BackendKind,
    pub version: String,
    pub is_cmfa: bool,
}

pub(crate) async fn probe_with_client(client: &MihomoClient) -> Result<BackendProbe, MihomoError> {
    match client.get_json("version").await {
        Ok(raw) => Ok(from_version(&raw).unwrap_or_else(|| from_root(&raw))),
        Err(MihomoError::Upstream { status: 404, .. }) => {
            let root = client.get_json("").await?;
            Ok(from_root(&root))
        }
        Err(err) => Err(err),
    }
}

fn from_version(raw: &Value) -> Option<BackendProbe> {
    let version = raw.get("version").and_then(Value::as_str)?.to_string();
    let is_cmfa = version.to_lowercase().contains("cmfa");
    Some(BackendProbe {
        kind: BackendKind::Mihomo,
        version,
        is_cmfa,
    })
}

fn from_root(raw: &Value) -> BackendProbe {
    if let Some(app_version) = raw.get("appVersion").and_then(Value::as_str) {
        return BackendProbe {
            kind: BackendKind::Stash,
            version: format!("Stash {app_version}"),
            is_cmfa: false,
        };
    }
    if raw.get("hello").and_then(Value::as_str) == Some("mihomo") {
        return BackendProbe {
            kind: BackendKind::Mihomo,
            version: String::new(),
            is_cmfa: false,
        };
    }
    BackendProbe {
        kind: BackendKind::Unknown,
        version: String::new(),
        is_cmfa: false,
    }
}
