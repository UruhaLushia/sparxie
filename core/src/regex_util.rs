use regex::Regex;

use crate::error::MihomoError;

pub fn compile(pattern: Option<&str>) -> Result<Option<Regex>, MihomoError> {
    match pattern {
        None => Ok(None),
        Some(s) if s.is_empty() => Ok(None),
        Some(s) => Regex::new(s)
            .map(Some)
            .map_err(|e| MihomoError::InvalidRegex {
                pattern: s.to_string(),
                message: e.to_string(),
            }),
    }
}
