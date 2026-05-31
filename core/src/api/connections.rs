use futures_util::{StreamExt, stream::FuturesUnordered};
use reqwest::Method;
use serde_json::Value;

use crate::error::MihomoError;

use super::{MihomoTarget, urlencode};

/// `GET /connections` — one snapshot of currently tracked connections.
pub async fn connections(target: MihomoTarget) -> Result<String, MihomoError> {
    Ok(target.client()?.get_json("connections").await?.to_string())
}

/// `DELETE /connections/{id}` — close a single connection by UUID.
pub async fn close_connection(target: MihomoTarget, id: String) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(
            Method::DELETE,
            &format!("connections/{}", urlencode(&id)),
            None,
        )
        .await?;
    Ok(())
}

/// `DELETE /connections` — close every tracked connection.
pub async fn close_all_connections(target: MihomoTarget) -> Result<(), MihomoError> {
    target
        .client()?
        .forward(Method::DELETE, "connections", None)
        .await?;
    Ok(())
}

/// Close every connection whose proxy chain includes `chain`.
///
/// mihomo has no native "close by group" endpoint, so we snapshot
/// `/connections`, filter client-side, and fan out parallel DELETEs.
/// Returns the number of connections that were targeted (best effort —
/// individual closes may fail silently if the connection just ended).
pub async fn close_connections_by_chain(
    target: MihomoTarget,
    chain: String,
) -> Result<u32, MihomoError> {
    let client = target.client()?;
    let snapshot = client.get_json("connections").await?;
    let Some(rows) = snapshot.get("connections").and_then(Value::as_array) else {
        return Ok(0);
    };

    let ids: Vec<String> = rows
        .iter()
        .filter(|conn| conn_uses_chain(conn, &chain))
        .filter_map(|conn| conn.get("id").and_then(Value::as_str).map(str::to_owned))
        .collect();
    if ids.is_empty() {
        return Ok(0);
    }

    let mut tasks = FuturesUnordered::new();
    for id in &ids {
        let target = target.clone();
        let id = id.clone();
        tasks.push(async move {
            target
                .client()
                .ok()?
                .forward(
                    Method::DELETE,
                    &format!("connections/{}", urlencode(&id)),
                    None,
                )
                .await
                .ok()
        });
    }
    while tasks.next().await.is_some() {}

    Ok(ids.len() as u32)
}

fn conn_uses_chain(conn: &Value, chain: &str) -> bool {
    let Some(arr) = conn.get("chains").and_then(Value::as_array) else {
        return false;
    };
    arr.iter().any(|hop| hop.as_str() == Some(chain))
}

/// Close every connection in a process group. `group` is the same key the
/// grouped view uses: a process name, or a source IP when the process is
/// unknown. Snapshots `/connections`, filters client-side, fans out
/// parallel DELETEs. Returns the number targeted (best effort).
pub async fn close_connections_by_group(
    target: MihomoTarget,
    group: String,
) -> Result<u32, MihomoError> {
    let client = target.client()?;
    let snapshot = client.get_json("connections").await?;
    let Some(rows) = snapshot.get("connections").and_then(Value::as_array) else {
        return Ok(0);
    };

    let ids: Vec<String> = rows
        .iter()
        .filter(|conn| conn_in_group(conn, &group))
        .filter_map(|conn| conn.get("id").and_then(Value::as_str).map(str::to_owned))
        .collect();
    if ids.is_empty() {
        return Ok(0);
    }

    let mut tasks = FuturesUnordered::new();
    for id in &ids {
        let target = target.clone();
        let id = id.clone();
        tasks.push(async move {
            target
                .client()
                .ok()?
                .forward(
                    Method::DELETE,
                    &format!("connections/{}", urlencode(&id)),
                    None,
                )
                .await
                .ok()
        });
    }
    while tasks.next().await.is_some() {}

    Ok(ids.len() as u32)
}

fn conn_in_group(conn: &Value, group: &str) -> bool {
    let meta = conn.get("metadata");
    let field = |key: &str| {
        meta.and_then(|m| m.get(key))
            .and_then(Value::as_str)
            .unwrap_or("")
    };
    // Mirror connections_state::group_key — inner connections form their own
    // group keyed by a sentinel, else process name, else source IP.
    let key = if field("type").eq_ignore_ascii_case("inner") {
        "\u{0}inner"
    } else {
        let process = field("process");
        if process.is_empty() {
            field("sourceIP")
        } else {
            process
        }
    };
    key == group
}
