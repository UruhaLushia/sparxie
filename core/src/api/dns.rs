use crate::error::MihomoError;

use super::{MihomoTarget, urlencode};

/// `GET /dns/query?name=&type=` — perform a DNS query through mihomo's
/// resolver. The response follows the DOH JSON shape (`Status`, `Question`,
/// `Answer`, etc.). Returns 500 if the DNS section is disabled upstream.
pub async fn dns_query(
    target: MihomoTarget,
    name: String,
    record_type: Option<String>,
) -> Result<String, MihomoError> {
    let ty = record_type.as_deref().unwrap_or("A");
    let path = format!(
        "dns/query?name={}&type={}",
        urlencode(&name),
        urlencode(ty)
    );
    Ok(target.client()?.get_json(&path).await?.to_string())
}
