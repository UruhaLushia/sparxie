use std::collections::HashMap;

use serde_json::{Value, json};

use crate::MihomoError;
use crate::surge::client::{SurgeClient, SurgeTarget};

use super::super::value::{first_optional_i32, take_optional_string, value_to_i32};
use super::cache::{CachedPolicyMember, update_cached_delays};

pub(super) async fn test_policy_group(
    target: &SurgeTarget,
    client: &SurgeClient,
    group: &str,
) -> Result<HashMap<String, i32>, MihomoError> {
    client
        .post_json("v1/policy_groups/test", json!({ "group_name": group }))
        .await?;
    let delays = benchmark_delays(client).await?;
    update_cached_delays(target, &delays);
    Ok(delays)
}

pub(super) async fn benchmark_delays(
    client: &SurgeClient,
) -> Result<HashMap<String, i32>, MihomoError> {
    let raw = client.get_json("v1/policies/benchmark_results").await?;
    Ok(benchmark_delay_map(&raw))
}

pub(super) fn delay_for_member(member: &CachedPolicyMember, delays: &HashMap<String, i32>) -> i32 {
    delays
        .get(&member.line_hash)
        .or_else(|| delays.get(&member.entry.name))
        .copied()
        .unwrap_or(member.entry.delay)
}

fn benchmark_delay_map(raw: &Value) -> HashMap<String, i32> {
    let mut out = HashMap::new();
    if let Some(map) = raw.as_object() {
        for (key, value) in map {
            if let Some(delay) = benchmark_delay_value(value) {
                out.insert(key.clone(), delay);
            }
        }
    } else if let Some(arr) = raw.as_array() {
        for value in arr {
            let key = take_optional_string(
                value,
                &[
                    "lineHash",
                    "line_hash",
                    "hash",
                    "name",
                    "policy",
                    "policyName",
                ],
            );
            if let (Some(key), Some(delay)) = (key, benchmark_delay_value(value)) {
                out.insert(key, delay);
            }
        }
    }
    out
}

fn benchmark_delay_value(value: &Value) -> Option<i32> {
    first_optional_i32(
        value,
        &["lastTestScoreInMS", "delay", "latency", "rtt", "score"],
    )
    .or_else(|| value_to_i32(value))
}
