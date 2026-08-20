use futures_util::StreamExt;
use tokio_stream::wrappers::BroadcastStream;

use crate::MihomoError;
use crate::frb_generated::StreamSink;

use super::{
    BackendTarget, BackendType, Connection, ConnectionGroup, ConnectionGroupSort, ConnectionStats,
    ConnectionWindow, ConnectionsFrame, ConnectionsListKind, ConnectionsSort,
};
use super::{clash_conn_sort, clash_group_sort, clash_list_kind};

pub async fn controller_connections(target: BackendTarget) -> Result<String, MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::connections(target.clash()).await,
        BackendType::Surge => crate::surge::api::connections(target.surge()).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::connections(target.surge_controller()).await
        }
        BackendType::SingBox => Ok(serde_json::json!({ "connections": [] }).to_string()),
    }
}

pub async fn controller_close_connection(
    target: BackendTarget,
    id: String,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::close_connection(target.clash(), id).await,
        BackendType::Surge => crate::surge::api::close_connection(target.surge(), id).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::close_connection(target.surge_controller(), id).await
        }
        BackendType::SingBox => crate::sing_box::api::close_connection(target.sing_box(), id).await,
    }
}

pub async fn controller_close_all_connections(target: BackendTarget) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => crate::clash::api::close_all_connections(target.clash()).await,
        BackendType::Surge => crate::surge::api::close_all_connections(target.surge()).await,
        BackendType::SurgeController => {
            crate::surge_controller::api::close_all_connections(target.surge_controller()).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::close_all_connections(target.sing_box()).await
        }
    }
}

pub async fn controller_close_connections_by_chain(
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
        BackendType::SurgeController => {
            crate::surge_controller::api::close_connections_by_chain(
                target.surge_controller(),
                chain,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::api::close_connections_by_chain(target.sing_box(), chain).await
        }
    }
}

pub async fn controller_close_connections_by_group(
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
        BackendType::SurgeController => {
            crate::surge_controller::api::close_connections_by_group(
                target.surge_controller(),
                group,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::api::close_connections_by_group(target.sing_box(), group).await
        }
    }
}

pub async fn controller_connections_stream(
    target: BackendTarget,
    interval_ms: u32,
    closed_capacity: u32,
    sink: StreamSink<ConnectionsFrame>,
) -> Result<(), MihomoError> {
    let closed_capacity = closed_capacity.max(1) as usize;
    match target.backend_type {
        BackendType::Clash => {
            let rx = crate::clash::state::connections::subscribe(
                target.clash(),
                interval_ms,
                closed_capacity,
            )
            .await?;
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
            let rx = crate::surge::state::connections::subscribe(
                target.surge(),
                interval_ms,
                closed_capacity,
            )
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
        BackendType::SurgeController => {
            let rx = crate::surge_controller::state::connections::subscribe(
                target.surge_controller(),
                interval_ms,
                closed_capacity,
            )
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
        BackendType::SingBox => {
            let rx = crate::sing_box::state::connections::subscribe(
                target.sing_box(),
                interval_ms,
                closed_capacity,
            )
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

pub async fn controller_fetch_connection_window(
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
        BackendType::SurgeController => {
            let (total, rows) = crate::surge_controller::state::connections::fetch_window(
                target.surge_controller(),
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

pub async fn controller_fetch_connection_stats_by_id(
    target: BackendTarget,
    interval_ms: u32,
    id: String,
) -> Option<ConnectionStats> {
    let stats = match target.backend_type {
        BackendType::Clash => {
            crate::clash::state::connections::fetch_connection_stats_by_id(
                target.clash(),
                interval_ms,
                id,
            )
            .await
        }
        BackendType::Surge => {
            crate::surge::state::connections::fetch_connection_stats_by_id(
                target.surge(),
                interval_ms,
                id,
            )
            .await
        }
        BackendType::SurgeController => {
            crate::surge_controller::state::connections::fetch_connection_stats_by_id(
                target.surge_controller(),
                interval_ms,
                id,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::fetch_connection_stats_by_id(
                target.sing_box(),
                interval_ms,
                id,
            )
            .await
        }
    }?;
    Some(ConnectionStats {
        upload: stats.0,
        download: stats.1,
        upload_speed: stats.2,
        download_speed: stats.3,
    })
}

pub async fn controller_fetch_connection_groups(
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
        BackendType::SurgeController => {
            crate::surge_controller::state::connections::fetch_groups(
                target.surge_controller(),
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

pub async fn controller_fetch_connection_group_members(
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
        BackendType::SurgeController => {
            crate::surge_controller::state::connections::fetch_group_connections(
                target.surge_controller(),
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

pub async fn controller_set_connections_sort(
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
        BackendType::SurgeController => {
            crate::surge_controller::state::connections::set_sort(
                target.surge_controller(),
                interval_ms,
                sort,
                asc,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::set_sort(target.sing_box(), interval_ms, sort, asc)
                .await
        }
    }
}

pub async fn controller_clear_closed_connections(target: BackendTarget, interval_ms: u32) {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::state::connections::clear_closed(target.clash(), interval_ms).await
        }
        BackendType::Surge => {
            crate::surge::state::connections::clear_closed(target.surge(), interval_ms).await
        }
        BackendType::SurgeController => {
            crate::surge_controller::state::connections::clear_closed(
                target.surge_controller(),
                interval_ms,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::state::connections::clear_closed(target.sing_box(), interval_ms).await
        }
    }
}

pub async fn controller_clear_closed_connections_by_group(
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
        BackendType::SurgeController => {
            crate::surge_controller::state::connections::clear_closed_by_group(
                target.surge_controller(),
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

pub fn controller_stop_target_streams(target: BackendTarget) {
    if target.backend_type == BackendType::Clash {
        crate::clash::state::stream_manager::stop(&target.clash());
    }
    super::session::release_target(&target);
}
