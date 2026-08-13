use serde_json::Value;
use url::Url;

use crate::surge_controller::api::value_string;

pub(super) fn resource_matches_group(resource: &Value, group: &str, detail: &str) -> bool {
    let group = group.to_lowercase();
    let detail = detail.to_lowercase();
    ["key", "path", "fromModule"]
        .iter()
        .filter_map(|key| value_string(resource.get(*key)))
        .filter(|value| !value.is_empty())
        .any(|value| {
            let value = value.to_lowercase();
            value == group || detail.contains(&value) || normalized_resource_key(&value) == group
        })
}

fn normalized_resource_key(key: &str) -> String {
    key.rsplit("::")
        .next()
        .unwrap_or(key)
        .trim_matches(|character: char| !character.is_alphanumeric())
        .to_string()
}

pub(super) fn resources<'a>(raw: &'a Value, kinds: &[&str]) -> Vec<&'a Value> {
    raw.get("defines")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|item| {
            let kind = resource_type(item);
            kinds
                .iter()
                .any(|candidate| kind.eq_ignore_ascii_case(candidate))
        })
        .collect()
}

pub(super) fn resource_key(item: &Value) -> String {
    value_string(item.get("key"))
        .or_else(|| value_string(item.get("name")))
        .unwrap_or_default()
}

pub(super) fn resource_display_name(item: &Value, matched_group: Option<&str>) -> String {
    if let Some(group) = matched_group.filter(|name| !name.is_empty()) {
        return group.to_string();
    }
    if let Some(name) = value_string(item.get("name")).filter(|name| !name.is_empty()) {
        return name;
    }
    if let Some(module) = value_string(item.get("fromModule")).filter(|name| !name.is_empty()) {
        return module;
    }
    if let Some(path) = value_string(item.get("path"))
        && let Some(name) = display_name_from_url(&path)
    {
        return name;
    }
    let key = resource_key(item);
    let suffix = key.chars().take(8).collect::<String>();
    let resource_type = resource_type(item);
    let kind = resource_type_label(&resource_type);
    if suffix.is_empty() {
        kind.to_string()
    } else {
        format!("{kind} {suffix}")
    }
}

fn display_name_from_url(value: &str) -> Option<String> {
    let url = Url::parse(value).ok();
    let path = url
        .as_ref()
        .map(Url::path)
        .unwrap_or_else(|| value.split(['?', '#']).next().unwrap_or(value));
    let file = path
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or_default();
    let name = strip_resource_extension(file).trim();
    if !name.is_empty() {
        return Some(name.to_string());
    }
    url.and_then(|url| url.host_str().map(str::to_string))
}

fn strip_resource_extension(value: &str) -> &str {
    const EXTENSIONS: &[&str] = &[
        ".list",
        ".conf",
        ".sgmodule",
        ".js",
        ".yaml",
        ".yml",
        ".txt",
        ".json",
    ];
    EXTENSIONS
        .iter()
        .find_map(|extension| value.strip_suffix(extension))
        .unwrap_or(value)
}

fn resource_type_label(kind: &str) -> &str {
    match kind.to_ascii_lowercase().as_str() {
        "policy-group" => "策略组",
        "ruleset" => "规则集",
        "domainset" => "域名集",
        "script" => "脚本",
        _ => "资源",
    }
}

pub(super) fn resource_type(item: &Value) -> String {
    value_string(item.get("type")).unwrap_or_default()
}

pub(super) fn resource_time(item: &Value) -> String {
    let Some(value) = item.get("updatedAt") else {
        return String::new();
    };
    let seconds = value
        .as_i64()
        .or_else(|| value.as_f64().map(|value| value.floor() as i64))
        .or_else(|| value.as_str().and_then(|value| value.parse().ok()));
    seconds
        .filter(|seconds| *seconds > 0)
        .map(|seconds| {
            if seconds > 10_000_000_000 {
                seconds / 1000
            } else {
                seconds
            }
        })
        .and_then(unix_seconds_to_iso)
        .or_else(|| value_string(Some(value)))
        .unwrap_or_default()
}

pub(super) fn resource_updatable(item: &Value) -> bool {
    !item.get("local").and_then(Value::as_bool).unwrap_or(false)
}

fn unix_seconds_to_iso(seconds: i64) -> Option<String> {
    let days = seconds.div_euclid(86_400);
    let day_seconds = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    Some(format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        day_seconds / 3600,
        day_seconds % 3600 / 60,
        day_seconds % 60,
    ))
}

fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let day_of_era = z - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let mut year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    year += i64::from(month <= 2);
    (year, month, day)
}
