use crate::error::MihomoError;

use super::MihomoTarget;

/// `GET /version` → `{version, meta}`.
pub async fn version(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target.client()?.get_json("version").await?.to_string())
}
