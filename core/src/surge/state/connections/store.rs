use std::collections::{HashMap, HashSet, VecDeque};

use crate::backend::api::{
    Connection, ConnectionGroup, ConnectionGroupSort, ConnectionsListKind, ConnectionsSort,
};

use super::sort::{sort_groups, sort_rows};

#[derive(Default)]
pub(super) struct State {
    pub(super) active: HashMap<String, Connection>,
    pub(super) closed: VecDeque<Connection>,
    closed_capacity: usize,
    sort: ConnectionsSort,
    asc: bool,
}

impl State {
    pub(super) fn new(closed_capacity: usize) -> Self {
        Self {
            closed_capacity: closed_capacity.max(1),
            ..Self::default()
        }
    }

    pub(super) fn set_closed_capacity(&mut self, closed_capacity: usize) {
        self.closed_capacity = closed_capacity.max(1);
        while self.closed.len() > self.closed_capacity {
            self.closed.pop_front();
        }
        if self.closed.capacity() > self.closed_capacity {
            self.closed.shrink_to(self.closed_capacity);
        }
    }

    pub(super) fn set_sort(&mut self, sort: ConnectionsSort, asc: bool) {
        self.sort = sort;
        self.asc = asc;
    }

    pub(super) fn push_closed(&mut self, row: Connection) {
        if self.closed.len() >= self.closed_capacity {
            self.closed.pop_front();
        }
        self.closed.push_back(row);
    }

    pub(super) fn clear_closed(&mut self) {
        self.closed = VecDeque::new();
    }

    pub(super) fn clear_closed_by_group(&mut self, group: &str) {
        self.closed
            .retain(|connection| !connection_in_group(connection, group));
        self.closed.shrink_to_fit();
    }

    pub(super) fn compact_active(&mut self) {
        if self.active.capacity() > self.active.len().saturating_mul(4).max(64) {
            self.active.shrink_to_fit();
        }
    }

    pub(super) fn window(
        &self,
        kind: ConnectionsListKind,
        offset: u32,
        limit: u32,
        query: &str,
    ) -> (u32, Vec<Connection>) {
        let mut rows = self.rows(kind);
        sort_rows(&mut rows, self.sort, self.asc);
        rows.retain(|row| row.matches_query(query));
        let total = rows.len().min(u32::MAX as usize) as u32;
        let window = rows
            .into_iter()
            .skip(offset as usize)
            .take(limit as usize)
            .collect();
        (total, window)
    }

    pub(super) fn connection_stats(&self, id: &str) -> Option<(u64, u64, u64, u64)> {
        let connection = self.active.get(id).or_else(|| {
            self.closed
                .iter()
                .rev()
                .find(|connection| connection.id == id)
        })?;
        Some((
            connection.upload,
            connection.download,
            connection.upload_speed,
            connection.download_speed,
        ))
    }

    pub(super) fn groups(
        &self,
        kind: ConnectionsListKind,
        sort: ConnectionGroupSort,
        asc: bool,
        query: &str,
    ) -> Vec<ConnectionGroup> {
        let rows = self.row_refs(kind);
        let matching_groups = (!query.is_empty()).then(|| {
            rows.iter()
                .filter(|row| row.matches_query(query))
                .map(|row| connection_group_key(row))
                .collect::<HashSet<_>>()
        });
        let mut groups = HashMap::<String, ConnectionGroup>::new();
        for row in rows.into_iter().filter(|row| {
            matching_groups
                .as_ref()
                .is_none_or(|groups| groups.contains(&connection_group_key(row)))
        }) {
            let key = connection_group_key(row);
            let entry = groups
                .entry(key.clone())
                .or_insert_with(|| ConnectionGroup {
                    key: key.clone(),
                    label: if key.is_empty() {
                        "未知".into()
                    } else {
                        key.clone()
                    },
                    process: row.process.clone(),
                    process_path: row.process_path.clone(),
                    source_ip: row.source_ip.clone(),
                    ..Default::default()
                });
            entry.count += 1;
            entry.upload = entry.upload.saturating_add(row.upload);
            entry.download = entry.download.saturating_add(row.download);
            entry.upload_speed = entry.upload_speed.saturating_add(row.upload_speed);
            entry.download_speed = entry.download_speed.saturating_add(row.download_speed);
        }
        let mut groups = groups.into_values().collect::<Vec<_>>();
        sort_groups(&mut groups, sort, asc);
        groups
    }

    pub(super) fn group_connections(
        &self,
        kind: ConnectionsListKind,
        group: &str,
        limit: u32,
        query: &str,
    ) -> Vec<Connection> {
        let mut rows = self
            .rows(kind)
            .into_iter()
            .filter(|row| connection_in_group(row, group))
            .filter(|row| row.matches_query(query))
            .collect::<Vec<_>>();
        sort_rows(&mut rows, self.sort, self.asc);
        rows.into_iter().take(limit as usize).collect()
    }

    fn rows(&self, kind: ConnectionsListKind) -> Vec<Connection> {
        match kind {
            ConnectionsListKind::Active => self.active.values().cloned().collect(),
            ConnectionsListKind::Closed => self.closed.iter().rev().cloned().collect(),
        }
    }

    fn row_refs(&self, kind: ConnectionsListKind) -> Vec<&Connection> {
        match kind {
            ConnectionsListKind::Active => self.active.values().collect(),
            ConnectionsListKind::Closed => self.closed.iter().rev().collect(),
        }
    }
}

fn connection_group_key(row: &Connection) -> String {
    if row.process.is_empty() {
        row.source_ip.clone()
    } else {
        row.process.clone()
    }
}

fn connection_in_group(row: &Connection, group: &str) -> bool {
    if row.process.is_empty() {
        row.source_ip == group
    } else {
        row.process == group
    }
}
