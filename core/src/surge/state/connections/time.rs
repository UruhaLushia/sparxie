use serde_json::Value;

use super::value::value_to_f64;

pub(super) fn unix_seconds_to_iso(value: &Value) -> Option<String> {
    let seconds = value_to_f64(Some(value))?;
    if !seconds.is_finite() || seconds < 0.0 {
        return None;
    }
    let mut whole = seconds.floor() as i64;
    let mut millis = ((seconds - whole as f64) * 1000.0).round() as u32;
    if millis >= 1000 {
        whole += 1;
        millis -= 1000;
    }
    let days = whole.div_euclid(86_400);
    let secs_of_day = whole.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    let hour = secs_of_day / 3600;
    let minute = (secs_of_day % 3600) / 60;
    let second = secs_of_day % 60;
    Some(format!(
        "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z"
    ))
}

fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = y + if month <= 2 { 1 } else { 0 };
    (year, month as u32, day as u32)
}
