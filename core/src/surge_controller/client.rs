use serde::Deserialize;
use serde_json::Value;

use crate::MihomoError;

mod connection;
mod session;

pub use connection::SurgeControllerConnection;
pub use session::with_unary_connection;

#[derive(Clone)]
pub struct SurgeControllerTarget {
    pub address: String,
    pub password: Option<String>,
}

impl std::fmt::Debug for SurgeControllerTarget {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SurgeControllerTarget")
            .field("address", &self.address)
            .field("password", &self.password.as_ref().map(|_| "<redacted>"))
            .finish()
    }
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Welcome {
    #[serde(default)]
    pub protocol: u32,
    #[serde(default)]
    pub system: String,
    #[serde(default)]
    pub build: String,
}

impl SurgeControllerTarget {
    pub async fn connect(&self) -> Result<SurgeControllerConnection, MihomoError> {
        session::connect(self).await
    }

    pub async fn request<I, S>(&self, argv: I) -> Result<Value, MihomoError>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let argv = argv.into_iter().map(Into::into).collect::<Vec<_>>();
        with_unary_connection(self, |connection| {
            Box::pin(async move { connection.request(argv).await })
        })
        .await
    }

    pub async fn welcome(&self) -> Result<Welcome, MihomoError> {
        with_unary_connection(self, |connection| {
            Box::pin(async move { Ok(connection.welcome.clone()) })
        })
        .await
    }
}

pub fn target_key(target: &SurgeControllerTarget) -> String {
    let mut hash = blake3::Hasher::new();
    hash.update(target.password.as_deref().unwrap_or_default().as_bytes());
    format!(
        "{}|{}",
        target.address.trim().trim_end_matches('/'),
        hash.finalize().to_hex()
    )
}

pub fn release_target(target: &SurgeControllerTarget) {
    session::release_target(target);
}
