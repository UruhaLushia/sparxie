use crate::backend::api::{
    ConnectionGroupSort, ConnectionsListKind, ConnectionsSort, ProxyMemberSort,
};

pub(in crate::backend::api) fn clash_member_sort(
    sort: ProxyMemberSort,
) -> crate::clash::api::ProxyMemberSort {
    match sort {
        ProxyMemberSort::Original => crate::clash::api::ProxyMemberSort::Original,
        ProxyMemberSort::Name => crate::clash::api::ProxyMemberSort::Name,
        ProxyMemberSort::Delay => crate::clash::api::ProxyMemberSort::Delay,
    }
}

pub(in crate::backend::api) fn clash_list_kind(
    kind: ConnectionsListKind,
) -> crate::clash::state::connections::ConnectionsListKind {
    match kind {
        ConnectionsListKind::Active => {
            crate::clash::state::connections::ConnectionsListKind::Active
        }
        ConnectionsListKind::Closed => {
            crate::clash::state::connections::ConnectionsListKind::Closed
        }
    }
}

pub(in crate::backend::api) fn clash_conn_sort(
    sort: ConnectionsSort,
) -> crate::clash::state::connections::ConnectionsSort {
    match sort {
        ConnectionsSort::Time => crate::clash::state::connections::ConnectionsSort::Time,
        ConnectionsSort::Upload => crate::clash::state::connections::ConnectionsSort::Upload,
        ConnectionsSort::Download => crate::clash::state::connections::ConnectionsSort::Download,
        ConnectionsSort::UploadSpeed => {
            crate::clash::state::connections::ConnectionsSort::UploadSpeed
        }
        ConnectionsSort::DownloadSpeed => {
            crate::clash::state::connections::ConnectionsSort::DownloadSpeed
        }
        ConnectionsSort::Process => crate::clash::state::connections::ConnectionsSort::Process,
    }
}

pub(in crate::backend::api) fn clash_group_sort(
    sort: ConnectionGroupSort,
) -> crate::clash::state::connections::ConnectionGroupSort {
    match sort {
        ConnectionGroupSort::Name => crate::clash::state::connections::ConnectionGroupSort::Name,
        ConnectionGroupSort::Count => crate::clash::state::connections::ConnectionGroupSort::Count,
        ConnectionGroupSort::Upload => {
            crate::clash::state::connections::ConnectionGroupSort::Upload
        }
        ConnectionGroupSort::Download => {
            crate::clash::state::connections::ConnectionGroupSort::Download
        }
        ConnectionGroupSort::UploadSpeed => {
            crate::clash::state::connections::ConnectionGroupSort::UploadSpeed
        }
        ConnectionGroupSort::DownloadSpeed => {
            crate::clash::state::connections::ConnectionGroupSort::DownloadSpeed
        }
    }
}
