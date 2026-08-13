use serde_json::Value;

use crate::backend::api::TrafficSample;

use super::value::first_u64;

pub(crate) fn parse_traffic(raw: &Value) -> TrafficSample {
    let raw = raw.get("data").unwrap_or(raw);
    if let Some(interfaces) = raw.get("interface").and_then(Value::as_object) {
        let mut sample = TrafficSample::default();
        for value in interfaces.values() {
            sample.up = sample.up.saturating_add(first_u64(
                value,
                &["outCurrentSpeed", "up", "upload", "uploadSpeed"],
            ));
            sample.down = sample.down.saturating_add(first_u64(
                value,
                &["inCurrentSpeed", "down", "download", "downloadSpeed"],
            ));
            sample.up_total = sample
                .up_total
                .saturating_add(first_u64(value, &["out", "upTotal", "uploadTotal"]));
            sample.down_total = sample
                .down_total
                .saturating_add(first_u64(value, &["in", "downTotal", "downloadTotal"]));
        }
        return sample;
    }
    let v = raw.get("traffic").filter(|v| v.is_object()).unwrap_or(raw);
    TrafficSample {
        up: first_u64(v, &["up", "upload", "uploadSpeed", "outCurrentSpeed"]),
        down: first_u64(v, &["down", "download", "downloadSpeed", "inCurrentSpeed"]),
        up_total: first_u64(
            v,
            &["upTotal", "uploadTotal", "outTotalBytes", "outBytes", "out"],
        ),
        down_total: first_u64(
            v,
            &[
                "downTotal",
                "downloadTotal",
                "inTotalBytes",
                "inBytes",
                "in",
            ],
        ),
    }
}
