use serde_json::{Value, json};

use crate::MihomoError;
use crate::surge::client::SurgeTarget;

use super::value::{take_optional_string, take_string};

pub async fn connections(target: SurgeTarget) -> Result<String, MihomoError> {
    Ok(target
        .client()?
        .get_json("v1/requests/active")
        .await?
        .to_string())
}

pub async fn close_connection(target: SurgeTarget, id: String) -> Result<(), MihomoError> {
    target
        .client()?
        .post_json("v1/requests/kill", json!({ "id": request_id_value(&id) }))
        .await?;
    Ok(())
}

pub async fn close_all_connections(target: SurgeTarget) -> Result<(), MihomoError> {
    let raw = target.client()?.get_json("v1/requests/active").await?;
    for id in request_ids(&raw) {
        let _ = close_connection(target.clone(), id).await;
    }
    Ok(())
}

pub async fn close_connections_by_chain(
    target: SurgeTarget,
    chain: String,
) -> Result<(), MihomoError> {
    let raw = target.client()?.get_json("v1/requests/active").await?;
    for item in request_items(&raw) {
        let policy_node = take_string(item, &["policy", "policyName", "rulePolicy"]);
        let policy_group = take_string(item, &["originalPolicyName"]);
        if (policy_node == chain || policy_group == chain)
            && let Some(id) = take_optional_string(item, &["id", "requestId"])
        {
            let _ = close_connection(target.clone(), id).await;
        }
    }
    Ok(())
}

pub async fn close_connections_by_group(
    target: SurgeTarget,
    group: String,
) -> Result<(), MihomoError> {
    let raw = target.client()?.get_json("v1/requests/active").await?;
    for item in request_items(&raw) {
        let process = take_string(item, &["process", "processName", "application"]);
        let source = take_string(
            item,
            &[
                "sourceAddress",
                "sourceIP",
                "sourceIp",
                "clientIP",
                "clientAddress",
            ],
        );
        if (process == group || source == group)
            && let Some(id) = take_optional_string(item, &["id", "requestId"])
        {
            let _ = close_connection(target.clone(), id).await;
        }
    }
    Ok(())
}

fn request_ids(raw: &Value) -> Vec<String> {
    request_items(raw)
        .into_iter()
        .filter_map(|item| take_optional_string(item, &["id", "requestId"]))
        .collect()
}

fn request_items(raw: &Value) -> Vec<&Value> {
    if let Some(arr) = raw.as_array() {
        return arr.iter().collect();
    }
    for key in ["requests", "active", "data"] {
        if let Some(arr) = raw.get(key).and_then(Value::as_array) {
            return arr.iter().collect();
        }
    }
    Vec::new()
}

fn request_id_value(id: &str) -> Value {
    id.parse::<u64>()
        .map(Value::from)
        .unwrap_or_else(|_| Value::String(id.into()))
}
