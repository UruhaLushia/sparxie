use futures_util::StreamExt;
use tokio_stream::wrappers::BroadcastStream;

use crate::MihomoError;
use crate::frb_generated::StreamSink;

use super::{
    BackendTarget, BackendType, Connection, ConnectionGroup, ConnectionGroupSort, ConnectionWindow,
    ConnectionsFrame, ConnectionsListKind, ConnectionsSort,
};
use super::{clash_conn_sort, clash_group_sort, clash_list_kind};

pub async fn connections(target: BackendTarget) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::connections(target.clash()).await,
        BackendType::Surge => crate::surge::api::connections(target.surge()).await,
        BackendType::SingBox => Ok(serde_json::json!({ "connections": [] }).to_string()),
    }
}

pub async fn close_connection(target: BackendTarget, id: String) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::close_connection(target.clash(), id).await,
        BackendType::Surge => crate::surge::api::close_connection(target.surge(), id).await,
        BackendType::SingBox => crate::sing_box::api::close_connection(target.sing_box(), id).await,
    }
}

pub async fn close_all_connections(target: BackendTarget) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::close_all_connections(target.clash()).await,
        BackendType::Surge => crate::surge::api::close_all_connections(target.surge()).await,
        BackendType::SingBox => {
            crate::sing_box::api::close_all_connections(target.sing_box()).await
        }
    }
}

pub async fn close_connections_by_chain(
    target: BackendTarget,
    chain: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::close_connections_by_chain(target.clash(), chain)
            .await
            .map(|_| ()),
        BackendType::Surge => {
            crate::surge::api::close_connections_by_chain(target.surge(), chain).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::close_connections_by_chain(target.sing_box(), chain).await
        }
    }
}

pub async fn close_connections_by_group(
    target: BackendTarget,
    group: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::close_connections_by_group(target.clash(), group)
            .await
            .map(|_| ()),
        BackendType::Surge => {
            crate::surge::api::close_connections_by_group(target.surge(), group).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::close_connections_by_group(target.sing_box(), group).await
        }
    }
}

pub async fn connections_stream(
    target: BackendTarget,
    interval_ms: u32,
    sink: StreamSink<ConnectionsFrame>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            let rx =
                crate::clash::state::connections::subscribe(target.clash(), interval_ms).await?;
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(frame) = item else { continue };
                if sink.add(frame.into()).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::Surge => {
            let rx =
                crate::surge::state::connections::subscribe(target.surge(), interval_ms).await?;
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(frame) = item else { continue };
                if sink.add(frame).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::SingBox => {
            let rx = crate::sing_box::state::connections::subscribe(target.sing_box(), interval_ms)
                .await?;
            let mut stream = BroadcastStream::new(rx);
            while let Some(item) = stream.next().await {
                let Ok(frame) = item else { continue };
                if sink.add(frame).is_err() {
                    break;
                }
            }
            Ok(())
        }
    }
}

pub async fn fetch_connection_window(
    target: BackendTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    offset: u32,
    limit: u32,
    query: String,
) -> ConnectionWindow {
    match target.backend_type {
        BackendType::Clash => {
            let (total, rows) = crate::clash::state::connections::fetch_window(
                target.clash(),
                interval_ms,
                clash_list_kind(kind),
                offset,
                limit,
                query,
            )
            .await;
            ConnectionWindow {
                total,
                rows: rows.into_iter().map(Into::into).collect(),
            }
        }
        BackendType::Surge => {
            let (total, rows) = crate::surge::state::connections::fetch_window(
                target.surge(),
                interval_ms,
                kind,
                offset,
                limit,
                query,
            )
            .await;
            ConnectionWindow { total, rows }
        }
        BackendType::SingBox => {
            let (total, rows) = crate::sing_box::state::connections::fetch_window(
                target.sing_box(),
                interval_ms,
                kind,
                offset,
                limit,
                query,
            )
            .await;
            ConnectionWindow { total, rows }
        }
    }
}

pub async fn fetch_connection_groups(
    target: BackendTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    sort: ConnectionGroupSort,
    asc: bool,
    query: String,
) -> Vec<ConnectionGroup> {
    match target.backend_type {
        BackendType::Clash => crate::clash::state::connections::fetch_groups(
            target.clash(),
            interval_ms,
            clash_list_kind(kind),
            clash_group_sort(sort),
            asc,
            query,
        )
        .await
        .into_iter()
        .map(Into::into)
        .collect(),
        BackendType::Surge => {
            crate::surge::state::connections::fetch_groups(
                target.surge(),
                interval_ms,
                kind,
                sort,
                asc,
                query,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::fetch_groups(
                target.sing_box(),
                interval_ms,
                kind,
                sort,
                asc,
                query,
            )
            .await
        }
    }
}

pub async fn fetch_connection_group_members(
    target: BackendTarget,
    interval_ms: u32,
    kind: ConnectionsListKind,
    group: String,
    limit: u32,
    query: String,
) -> Vec<Connection> {
    match target.backend_type {
        BackendType::Clash => crate::clash::state::connections::fetch_group_connections(
            target.clash(),
            interval_ms,
            clash_list_kind(kind),
            group,
            limit,
            query,
        )
        .await
        .into_iter()
        .map(Into::into)
        .collect(),
        BackendType::Surge => {
            crate::surge::state::connections::fetch_group_connections(
                target.surge(),
                interval_ms,
                kind,
                group,
                limit,
                query,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::fetch_group_connections(
                target.sing_box(),
                interval_ms,
                kind,
                group,
                limit,
                query,
            )
            .await
        }
    }
}

pub async fn set_connections_sort(
    target: BackendTarget,
    interval_ms: u32,
    sort: ConnectionsSort,
    asc: bool,
) {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::state::connections::set_sort(
                target.clash(),
                interval_ms,
                clash_conn_sort(sort),
                asc,
            )
            .await
        }
        BackendType::Surge => {
            crate::surge::state::connections::set_sort(target.surge(), interval_ms, sort, asc).await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::set_sort(target.sing_box(), interval_ms, sort, asc)
                .await
        }
    }
}

pub async fn clear_closed_connections(target: BackendTarget, interval_ms: u32) {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::state::connections::clear_closed(target.clash(), interval_ms).await
        }
        BackendType::Surge => {
            crate::surge::state::connections::clear_closed(target.surge(), interval_ms).await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::clear_closed(target.sing_box(), interval_ms).await
        }
    }
}

pub async fn clear_closed_connections_by_group(
    target: BackendTarget,
    interval_ms: u32,
    group: String,
) {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::state::connections::clear_closed_by_group(
                target.clash(),
                interval_ms,
                group,
            )
            .await
        }
        BackendType::Surge => {
            crate::surge::state::connections::clear_closed_by_group(
                target.surge(),
                interval_ms,
                group,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::clear_closed_by_group(
                target.sing_box(),
                interval_ms,
                group,
            )
            .await
        }
    }
}

pub fn stop_target_streams(target: BackendTarget) {
    if target.backend_type == BackendType::Clash {
        crate::clash::state::stop::stop(&target.clash());
    }
}
