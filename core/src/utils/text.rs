/// `filter` must already be lowercased when it contains non-ASCII text.
pub(crate) fn contains_filter(value: &str, filter: &str) -> bool {
    if filter.is_empty() {
        return true;
    }
    if value.is_ascii() && filter.is_ascii() {
        return value
            .as_bytes()
            .windows(filter.len())
            .any(|window| window.eq_ignore_ascii_case(filter.as_bytes()));
    }
    value.to_lowercase().contains(filter)
}
