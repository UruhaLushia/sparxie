use std::collections::HashMap;

use serde_json::Value;

use crate::MihomoError;
use crate::backend::api::{ProxyMemberEntry, ProxyMemberSort};
use crate::surge::client::SurgeClient;

use super::super::value::{string_array, take_optional_string, take_string};
use super::cache::CachedPolicyMember;

pub(super) struct GroupItem<'a> {
    pub(super) name: String,
    pub(super) value: &'a Value,
}

#[derive(Default)]
pub(super) struct GroupMeta {
    pub(super) group_type: String,
    pub(super) hidden: bool,
    pub(super) selectable: bool,
    pub(super) icon: String,
}

pub(super) async fn policy_group_order(
    client: &SurgeClient,
) -> Result<HashMap<String, usize>, MihomoError> {
    let raw = client.get_json("v1/policies").await?;
    Ok(
        string_array(&raw, &["policy-groups", "policyGroups", "groups"])
            .into_iter()
            .enumerate()
            .map(|(index, name)| (name, index))
            .collect(),
    )
}

pub(super) fn policy_group_items(raw: &Value) -> Vec<GroupItem<'_>> {
    if let Some(arr) = raw.as_array() {
        return arr
            .iter()
            .map(|value| GroupItem {
                name: take_string(value, &["name", "group", "groupName"]),
                value,
            })
            .collect();
    }
    for key in ["policy_groups", "policyGroups", "groups"] {
        if let Some(arr) = raw.get(key).and_then(Value::as_array) {
            return arr
                .iter()
                .map(|value| GroupItem {
                    name: take_string(value, &["name", "group", "groupName"]),
                    value,
                })
                .collect();
        }
    }
    raw.as_object()
        .map(|map| {
            map.iter()
                .filter(|(_, value)| value.is_object() || value.is_array())
                .map(|(name, value)| GroupItem {
                    name: take_optional_string(value, &["name", "group", "groupName"])
                        .unwrap_or_else(|| name.clone()),
                    value,
                })
                .collect()
        })
        .unwrap_or_default()
}

pub(super) fn policy_members(
    value: &Value,
    delays: &HashMap<String, i32>,
) -> Vec<CachedPolicyMember> {
    if let Some(arr) = value.as_array() {
        return arr
            .iter()
            .filter(|item| item.get("enabled").and_then(Value::as_bool).unwrap_or(true))
            .filter_map(|item| member_from_value(item, delays))
            .collect();
    }
    for key in [
        "policies",
        "policy_names",
        "policyNames",
        "available",
        "options",
    ] {
        if let Some(arr) = value.get(key).and_then(Value::as_array) {
            return arr
                .iter()
                .filter_map(|item| member_from_value(item, delays))
                .collect();
        }
    }
    Vec::new()
}

fn member_from_value(value: &Value, delays: &HashMap<String, i32>) -> Option<CachedPolicyMember> {
    let name = value
        .as_str()
        .map(str::to_owned)
        .or_else(|| take_optional_string(value, &["name", "policy", "policyName"]))?;
    if name.is_empty() {
        return None;
    }
    let line_hash = take_optional_string(value, &["lineHash", "line_hash", "hash", "policyHash"])
        .unwrap_or_default();
    let delay = delays
        .get(&line_hash)
        .or_else(|| delays.get(&name))
        .copied()
        .unwrap_or(-1);
    Some(CachedPolicyMember {
        entry: ProxyMemberEntry {
            name,
            proxy_type: take_optional_string(value, &["typeDescription", "type", "policyType"])
                .unwrap_or_else(|| "Policy".into()),
            delay,
        },
        line_hash,
    })
}

pub(super) async fn group_meta(client: &SurgeClient, name: &str) -> Result<GroupMeta, MihomoError> {
    let raw = client
        .get_json(&format!(
            "v1/policies/detail?policy_name={}",
            urlencode(name)
        ))
        .await?;
    let line = raw
        .as_object()
        .and_then(|map| map.values().next())
        .and_then(Value::as_str)
        .unwrap_or_default();
    Ok(parse_group_detail(line))
}

fn parse_group_detail(line: &str) -> GroupMeta {
    let mut meta = GroupMeta::default();
    let Some((_, rest)) = line.split_once('=') else {
        return meta;
    };
    for (index, part) in rest.split(',').map(str::trim).enumerate() {
        if index == 0 {
            meta.group_type = part.to_string();
            meta.selectable = part.eq_ignore_ascii_case("select");
            continue;
        }
        let Some((key, value)) = part.split_once('=') else {
            continue;
        };
        match key.trim() {
            "hidden" => {
                meta.hidden = value.trim() == "1" || value.trim().eq_ignore_ascii_case("true")
            }
            "icon-url" => meta.icon = value.trim().to_string(),
            _ => {}
        }
    }
    meta
}

pub(super) async fn selected_policy(
    client: &SurgeClient,
    group: &str,
) -> Result<String, MihomoError> {
    let raw = client
        .get_json(&format!(
            "v1/policy_groups/select?group_name={}",
            urlencode(group)
        ))
        .await?;
    Ok(raw
        .get("policy")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string())
}

pub(super) fn display_group_type(raw_type: &str, selectable: bool) -> String {
    if raw_type.is_empty() {
        if selectable {
            "Selector".into()
        } else {
            "PolicyGroup".into()
        }
    } else {
        raw_type.to_string()
    }
}

pub(super) fn member_hash(names: &[String]) -> u32 {
    let mut hash: u32 = 2166136261;
    for name in names {
        for byte in name.as_bytes() {
            hash ^= *byte as u32;
            hash = hash.wrapping_mul(16777619);
        }
        hash ^= 0xff;
        hash = hash.wrapping_mul(16777619);
    }
    hash
}

pub(super) fn sort_members(entries: &mut [ProxyMemberEntry], sort: ProxyMemberSort) {
    match sort {
        ProxyMemberSort::Original => {}
        ProxyMemberSort::Name => entries.sort_by(|a, b| a.name.cmp(&b.name)),
        ProxyMemberSort::Delay => entries.sort_by(|a, b| {
            let ad = if a.delay < 0 { i32::MAX } else { a.delay };
            let bd = if b.delay < 0 { i32::MAX } else { b.delay };
            ad.cmp(&bd).then_with(|| a.name.cmp(&b.name))
        }),
    }
}

fn urlencode(s: &str) -> String {
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
