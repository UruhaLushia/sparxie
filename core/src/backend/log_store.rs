use std::collections::{HashSet, VecDeque};

use super::api::{LogEntry, LogWindow, LogsFrame};

const TOTAL_CAPACITY_MULTIPLIER: usize = 2;

struct StoredLog {
    entry: LogEntry,
    dedupe_key: Option<String>,
}

pub(crate) struct LogStore {
    entries: VecDeque<StoredLog>,
    seen: HashSet<String>,
    info_entries: usize,
    info_capacity: usize,
    next_id: u64,
}

impl LogStore {
    pub(crate) fn new(info_capacity: usize) -> Self {
        Self {
            entries: VecDeque::new(),
            seen: HashSet::new(),
            info_entries: 0,
            info_capacity: info_capacity.max(1),
            next_id: 0,
        }
    }

    pub(crate) fn set_info_capacity(&mut self, info_capacity: usize) {
        let info_capacity = info_capacity.max(1);
        if info_capacity == self.info_capacity {
            return;
        }
        let reduced = info_capacity < self.info_capacity;
        self.info_capacity = info_capacity;
        self.trim();
        if reduced {
            self.entries.shrink_to_fit();
            self.seen.shrink_to_fit();
        }
    }

    pub(crate) fn push(&mut self, entry: LogEntry) -> LogsFrame {
        self.push_inner(entry, None)
    }

    pub(crate) fn push_unique(&mut self, key: String, entry: LogEntry) -> Option<LogsFrame> {
        if !self.seen.insert(key.clone()) {
            return None;
        }
        Some(self.push_inner(entry, Some(key)))
    }

    pub(crate) fn clear(&mut self) -> LogsFrame {
        self.entries = VecDeque::new();
        self.seen = HashSet::new();
        self.info_entries = 0;
        self.frame(false)
    }

    pub(crate) fn frame(&self, is_initial: bool) -> LogsFrame {
        LogsFrame {
            total: usize_to_u32(self.entries.len()),
            latest_id: self.entries.back().map_or(0, |stored| stored.entry.id),
            is_initial,
        }
    }

    pub(crate) fn window(
        &self,
        level: &str,
        query: &str,
        offset: usize,
        limit: usize,
        from_end: bool,
        anchor_id: u64,
    ) -> LogWindow {
        let query = query.trim().to_lowercase();
        let filter_rank = level_rank(if level.is_empty() { "info" } else { level });
        let matches = |stored: &&StoredLog| {
            level_allows_rank(filter_rank, &stored.entry.level)
                && (query.is_empty()
                    || crate::utils::text::contains_filter(&stored.entry.message, &query)
                    || crate::utils::text::contains_filter(&stored.entry.level, &query))
        };
        let mut total = 0usize;
        let mut anchor_index = None;
        for stored in self.entries.iter().filter(matches) {
            if stored.entry.id == anchor_id {
                anchor_index = Some(total);
            }
            total += 1;
        }
        let start = if from_end {
            total.saturating_sub(limit)
        } else if let Some(anchor_index) = anchor_index {
            anchor_index
                .saturating_sub(limit / 2)
                .min(total.saturating_sub(limit))
        } else {
            offset.min(total)
        };
        let rows = self
            .entries
            .iter()
            .filter(matches)
            .skip(start)
            .take(limit)
            .map(|stored| stored.entry.clone())
            .collect();
        LogWindow {
            total: usize_to_u32(total),
            offset: usize_to_u32(start),
            rows,
        }
    }

    fn push_inner(&mut self, mut entry: LogEntry, dedupe_key: Option<String>) -> LogsFrame {
        self.next_id = self.next_id.wrapping_add(1).max(1);
        entry.id = self.next_id;
        if level_allows("info", &entry.level) {
            self.info_entries += 1;
        }
        self.entries.push_back(StoredLog { entry, dedupe_key });
        self.trim();
        self.frame(false)
    }

    fn trim(&mut self) {
        // Verbose entries keep their own budget so changing the visible level
        // still has history, but a Debug/Trace-only stream cannot grow forever.
        let total_capacity = self.info_capacity.saturating_mul(TOTAL_CAPACITY_MULTIPLIER);
        while self.info_entries > self.info_capacity || self.entries.len() > total_capacity {
            let Some(stored) = self.entries.pop_front() else {
                self.info_entries = 0;
                break;
            };
            if let Some(key) = stored.dedupe_key {
                self.seen.remove(&key);
            }
            if level_allows("info", &stored.entry.level) {
                self.info_entries -= 1;
            }
        }
    }
}

fn level_allows(filter: &str, level: &str) -> bool {
    let filter_rank = level_rank(if filter.is_empty() { "info" } else { filter });
    level_allows_rank(filter_rank, level)
}

fn level_allows_rank(filter_rank: Option<u8>, level: &str) -> bool {
    filter_rank.is_some_and(|filter_rank| {
        level_rank(level).is_some_and(|level_rank| level_rank >= filter_rank)
    })
}

fn level_rank(level: &str) -> Option<u8> {
    match level.to_ascii_lowercase().as_str() {
        "trace" => Some(0),
        "debug" => Some(1),
        "info" => Some(2),
        "warning" | "warn" => Some(3),
        "error" => Some(4),
        "fatal" => Some(5),
        "panic" => Some(6),
        "silent" => None,
        _ => Some(2),
    }
}

fn usize_to_u32(value: usize) -> u32 {
    value.min(u32::MAX as usize) as u32
}
