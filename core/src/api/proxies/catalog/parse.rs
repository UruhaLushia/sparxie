use std::collections::{HashMap, HashSet};

use serde_json::Value;

use super::super::value::{value_to_i32, value_to_string};

pub(super) fn member_count(value: Option<&Value>) -> usize {
    value
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or_default()
}

pub(super) fn intern_member_list(
    value: Option<&Value>,
    name_ids: &mut HashMap<String, usize>,
    needed_nodes: &mut HashSet<usize>,
) -> (Vec<usize>, u32) {
    let Some(items) = value.and_then(Value::as_array) else {
        return (Vec::new(), FNV_OFFSET);
    };
    let mut members = Vec::with_capacity(items.len());
    let mut hash = FNV_OFFSET;
    for item in items {
        let id = if let Some(name) = item.as_str() {
            hash_member_name(&mut hash, name);
            intern_str_name(name, name_ids)
        } else {
            let name = value_to_string(item);
            hash_member_name(&mut hash, &name);
            intern_owned_name(name, name_ids)
        };
        needed_nodes.insert(id);
        members.push(id);
    }
    (members, hash)
}

pub(super) fn proxy_group_matches(name: &str, members: Option<&Value>, filter: &str) -> bool {
    if filter.is_empty() || name.to_lowercase().contains(filter) {
        return true;
    }
    members
        .and_then(Value::as_array)
        .map(|items| items.iter().any(|member| value_matches(member, filter)))
        .unwrap_or(false)
}

pub(super) fn push_icon(icon_urls: &mut Vec<String>, seen: &mut HashSet<String>, icon: &str) {
    if !icon.is_empty() && seen.insert(icon.to_string()) {
        icon_urls.push(icon.to_string());
    }
}

pub(super) fn history_delay(value: Option<&Value>) -> i32 {
    let Some(items) = value.and_then(Value::as_array) else {
        return -1;
    };
    let Some(last) = items.last() else {
        return -1;
    };
    last.get("delay").map(value_to_i32).unwrap_or_default()
}

fn intern_str_name(name: &str, name_ids: &mut HashMap<String, usize>) -> usize {
    if let Some(id) = name_ids.get(name) {
        return *id;
    }
    let id = name_ids.len();
    name_ids.insert(name.to_string(), id);
    id
}

fn intern_owned_name(name: String, name_ids: &mut HashMap<String, usize>) -> usize {
    if let Some(id) = name_ids.get(name.as_str()) {
        return *id;
    }
    let id = name_ids.len();
    name_ids.insert(name, id);
    id
}

const FNV_OFFSET: u32 = 2_166_136_261;
const FNV_PRIME: u32 = 16_777_619;

fn hash_member_name(hash: &mut u32, name: &str) {
    for byte in name.bytes().chain(std::iter::once(0)) {
        *hash ^= u32::from(byte);
        *hash = hash.wrapping_mul(FNV_PRIME);
    }
}

fn value_matches(value: &Value, filter: &str) -> bool {
    value
        .as_str()
        .map(|s| s.to_lowercase().contains(filter))
        .unwrap_or_else(|| value_to_string(value).to_lowercase().contains(filter))
}
