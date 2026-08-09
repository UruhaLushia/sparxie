//! Clash external-controller API implementation.

use crate::MihomoError;
use crate::clash::client::MihomoClient;

pub(crate) mod backend;
pub mod cache;
pub mod configs;
pub mod connections;
pub mod dns;
pub mod fonts;
pub mod groups;
pub mod icons;
pub mod providers;
pub mod proxies;
pub mod rules;
pub mod storage;
pub mod upgrade;
pub mod version;

pub use cache::*;
pub use configs::*;
pub use connections::*;
pub use dns::*;
pub use fonts::*;
pub use groups::*;
pub use icons::*;
pub use providers::*;
pub use proxies::*;
pub use rules::*;
pub use storage::*;
pub use upgrade::*;
pub use version::*;

/// One Clash external-controller endpoint.
#[derive(Debug, Clone)]
pub struct MihomoTarget {
    pub base_url: String,
    pub secret: Option<String>,
    /// Skip TLS cert validation for https/wss (self-signed backends).
    pub allow_insecure: bool,
}

impl MihomoTarget {
    pub(crate) fn client(&self) -> Result<MihomoClient, MihomoError> {
        MihomoClient::new(&self.base_url, self.secret.clone(), self.allow_insecure)
    }

    pub(crate) fn identity_key(&self) -> String {
        format!(
            "{}|{}|{}",
            self.base_url.trim_end_matches('/'),
            self.secret.as_deref().unwrap_or(""),
            self.allow_insecure,
        )
    }
}

pub(crate) fn urlencode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.' | '~') {
            out.push(ch);
        } else {
            for byte in ch.to_string().as_bytes() {
                out.push_str(&format!("%{byte:02X}"));
            }
        }
    }
    out
}
