use crate::backend::api::{Connection, ConnectionGroup, ConnectionGroupSort, ConnectionsSort};

pub(super) fn sort_rows(rows: &mut [Connection], sort: ConnectionsSort, asc: bool) {
    rows.sort_by(|a, b| {
        let ord = match sort {
            ConnectionsSort::Time => a.start.cmp(&b.start),
            ConnectionsSort::Upload => a.upload.cmp(&b.upload),
            ConnectionsSort::Download => a.download.cmp(&b.download),
            ConnectionsSort::UploadSpeed => a.upload_speed.cmp(&b.upload_speed),
            ConnectionsSort::DownloadSpeed => a.download_speed.cmp(&b.download_speed),
            ConnectionsSort::Process => a.process.cmp(&b.process),
        };
        if asc { ord } else { ord.reverse() }
    });
}

pub(super) fn sort_groups(rows: &mut [ConnectionGroup], sort: ConnectionGroupSort, asc: bool) {
    rows.sort_by(|a, b| {
        let ord = match sort {
            ConnectionGroupSort::Name => a.label.cmp(&b.label),
            ConnectionGroupSort::Count => a.count.cmp(&b.count),
            ConnectionGroupSort::Upload => a.upload.cmp(&b.upload),
            ConnectionGroupSort::Download => a.download.cmp(&b.download),
            ConnectionGroupSort::UploadSpeed => a.upload_speed.cmp(&b.upload_speed),
            ConnectionGroupSort::DownloadSpeed => a.download_speed.cmp(&b.download_speed),
        };
        if asc { ord } else { ord.reverse() }
    });
}
