use super::types::{Connection, ConnectionGroup, ConnectionGroupSort, ConnectionsSort};

pub(super) fn sort_groups(rows: &mut [ConnectionGroup], sort: ConnectionGroupSort, asc: bool) {
    match sort {
        ConnectionGroupSort::Name => {
            rows.sort_by(|a, b| cmp_str(&a.label.to_lowercase(), &b.label.to_lowercase(), asc))
        }
        ConnectionGroupSort::Count => {
            rows.sort_by(|a, b| cmp_u64(a.count as u64, b.count as u64, asc))
        }
        ConnectionGroupSort::Upload => rows.sort_by(|a, b| cmp_u64(a.upload, b.upload, asc)),
        ConnectionGroupSort::Download => rows.sort_by(|a, b| cmp_u64(a.download, b.download, asc)),
        ConnectionGroupSort::UploadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.upload_speed, b.upload_speed, asc))
        }
        ConnectionGroupSort::DownloadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.download_speed, b.download_speed, asc))
        }
    }
}

pub(super) fn sort_rows(rows: &mut [&Connection], sort: ConnectionsSort, asc: bool) {
    match sort {
        ConnectionsSort::Time => rows.sort_by(|a, b| cmp_str(&a.start, &b.start, asc)),
        ConnectionsSort::Upload => rows.sort_by(|a, b| cmp_u64(a.upload, b.upload, asc)),
        ConnectionsSort::Download => rows.sort_by(|a, b| cmp_u64(a.download, b.download, asc)),
        ConnectionsSort::UploadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.upload_speed, b.upload_speed, asc))
        }
        ConnectionsSort::DownloadSpeed => {
            rows.sort_by(|a, b| cmp_u64(a.download_speed, b.download_speed, asc))
        }
        ConnectionsSort::Process => rows.sort_by(|a, b| cmp_str(&a.process, &b.process, asc)),
    }
}

fn cmp_u64(a: u64, b: u64, asc: bool) -> std::cmp::Ordering {
    if asc { a.cmp(&b) } else { b.cmp(&a) }
}

fn cmp_str(a: &str, b: &str, asc: bool) -> std::cmp::Ordering {
    if asc { a.cmp(b) } else { b.cmp(a) }
}
