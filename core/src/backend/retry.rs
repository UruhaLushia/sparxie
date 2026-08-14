use std::time::Duration;

use crate::MihomoError;

const DELAYS: [Duration; 4] = [
    Duration::from_secs(5),
    Duration::from_secs(10),
    Duration::from_secs(20),
    Duration::from_secs(30),
];

pub(crate) struct RetryBackoff {
    attempt: usize,
}

pub(crate) struct RetryErrorLog {
    label: &'static str,
    failed: bool,
}

impl RetryBackoff {
    pub(crate) fn new() -> Self {
        Self { attempt: 0 }
    }

    pub(crate) fn next_delay(&mut self) -> Duration {
        let index = self.attempt.min(DELAYS.len() - 1);
        self.attempt += 1;
        DELAYS[index]
    }

    pub(crate) fn reset(&mut self) {
        self.attempt = 0;
    }
}

impl RetryErrorLog {
    pub(crate) fn new(label: &'static str) -> Self {
        Self {
            label,
            failed: false,
        }
    }

    pub(crate) fn record(&mut self, error: &MihomoError) {
        if self.failed {
            return;
        }
        self.failed = true;
        eprintln!("[backend] {}: {error}", self.label);
    }

    pub(crate) fn recovered(&mut self) {
        self.failed = false;
    }
}
