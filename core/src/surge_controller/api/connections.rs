use serde_json::Value;

use crate::MihomoError;
use crate::surge_controller::client::SurgeControllerTarget;

use super::{command_ok, value_string};

pub async fn connections(target: SurgeControllerTarget) -> Result<String, MihomoError> {
    Ok(target.request(["dump", "active"]).await?.to_string())
}

pub async fn close_connection(
    target: SurgeControllerTarget,
    id: String,
) -> Result<(), MihomoError> {
    command_ok(&target, ["kill".into(), id]).await
}

pub async fn close_all_connections(target: SurgeControllerTarget) -> Result<(), MihomoError> {
    let raw = target.request(["dump", "active"]).await?;
    kill_connections(&target, request_ids(&raw)).await
}

pub async fn close_connections_by_chain(
    target: SurgeControllerTarget,
    chain: String,
) -> Result<(), MihomoError> {
    close_matching_connections(target, move |item| {
        ["policy", "policyName", "originalPolicyName", "rulePolicy"]
            .iter()
            .any(|key| value_string(item.get(*key)).as_deref() == Some(&chain))
    })
    .await
}

pub async fn close_connections_by_group(
    target: SurgeControllerTarget,
    group: String,
) -> Result<(), MihomoError> {
    close_matching_connections(target, move |item| {
        [
            "process",
            "processName",
            "application",
            "sourceAddress",
            "sourceIP",
            "sourceIp",
        ]
        .iter()
        .any(|key| value_string(item.get(*key)).as_deref() == Some(&group))
    })
    .await
}

async fn close_matching_connections(
    target: SurgeControllerTarget,
    matches: impl Fn(&Value) -> bool,
) -> Result<(), MihomoError> {
    let raw = target.request(["dump", "active"]).await?;
    let ids = request_items(&raw)
        .into_iter()
        .filter(|item| matches(item))
        .filter_map(request_id)
        .collect();
    kill_connections(&target, ids).await
}

async fn kill_connections(
    target: &SurgeControllerTarget,
    ids: Vec<String>,
) -> Result<(), MihomoError> {
    for id in ids {
        command_ok(target, ["kill".into(), id]).await?;
    }
    Ok(())
}

fn request_ids(raw: &Value) -> Vec<String> {
    request_items(raw)
        .into_iter()
        .filter_map(request_id)
        .collect()
}

fn request_id(item: &Value) -> Option<String> {
    value_string(item.get("id")).or_else(|| value_string(item.get("requestId")))
}

fn request_items(raw: &Value) -> Vec<&Value> {
    if let Some(items) = raw.as_array() {
        return items.iter().collect();
    }
    ["requests", "active", "data"]
        .iter()
        .find_map(|key| raw.get(*key).and_then(Value::as_array))
        .map(|items| items.iter().collect())
        .unwrap_or_default()
}
