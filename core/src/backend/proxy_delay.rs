use futures_util::{StreamExt, stream};

use crate::MihomoError;
use crate::frb_generated::StreamSink;

use super::{
    BackendTarget, BackendType, GroupDelayEntry, ProxyDelayEntry, ProxyDelayEvent, ProxyMemberSort,
    clash_member_sort,
};

pub async fn group_delay(
    target: BackendTarget,
    group: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: Option<u32>,
) -> Result<Vec<GroupDelayEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::group_delay(
            target.clash(),
            group,
            test_url,
            timeout_ms,
            expected_status,
            concurrency,
        )
        .await?
        .into_iter()
        .map(Into::into)
        .collect()),
        BackendType::Surge => crate::surge::api::group_delay(target.surge(), group).await,
        BackendType::SingBox => crate::sing_box::api::group_delay(target.sing_box(), group).await,
    }
}

pub async fn proxy_delay(
    target: BackendTarget,
    name: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
) -> Result<i64, MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            crate::clash::api::proxy_delay(
                target.clash(),
                name,
                test_url,
                timeout_ms,
                expected_status,
            )
            .await
        }
        BackendType::Surge => {
            Ok(
                crate::surge::api::proxy_batch_delay(target.surge(), vec![name], test_url)
                    .await?
                    .into_iter()
                    .next()
                    .map(|entry| entry.delay as i64)
                    .unwrap_or(-1),
            )
        }
        BackendType::SingBox => Ok(crate::sing_box::api::proxy_batch_delay(
            target.sing_box(),
            vec![name],
        )
        .await?
        .into_iter()
        .next()
        .map(|entry| entry.delay as i64)
        .unwrap_or(-1)),
    }
}

pub async fn proxy_batch_delay(
    target: BackendTarget,
    names: Vec<String>,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: u32,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_batch_delay(
            target.clash(),
            names,
            test_url,
            timeout_ms,
            expected_status,
            concurrency,
        )
        .await?
        .into_iter()
        .map(Into::into)
        .collect()),
        BackendType::Surge => {
            crate::surge::api::proxy_batch_delay(target.surge(), names, test_url).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::proxy_batch_delay(target.sing_box(), names).await
        }
    }
}

pub async fn proxy_group_batch_delay(
    target: BackendTarget,
    group: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: u32,
) -> Result<Vec<ProxyDelayEntry>, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_group_batch_delay(
            target.clash(),
            group,
            test_url,
            timeout_ms,
            expected_status,
            concurrency,
        )
        .await?
        .into_iter()
        .map(Into::into)
        .collect()),
        BackendType::Surge => {
            crate::surge::api::proxy_group_batch_delay(target.surge(), group, test_url).await
        }
        BackendType::SingBox => {
            crate::sing_box::api::proxy_group_batch_delay(target.sing_box(), group).await
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub async fn proxy_group_delay_stream(
    target: BackendTarget,
    group: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    concurrency: u32,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    window_members_hash: u32,
    sink: StreamSink<ProxyDelayEvent>,
) -> Result<(), MihomoError> {
    match target.backend_type {
        BackendType::Clash => {
            let clash_target = target.clash();
            let members = crate::clash::api::proxy_group_members(
                clash_target.clone(),
                group.clone(),
                0,
                u32::MAX,
                crate::clash::api::ProxyMemberSort::Original,
            )
            .await?;
            let names = members
                .into_iter()
                .map(|member| member.name)
                .collect::<Vec<_>>();
            let providers =
                crate::clash::api::cached_node_providers(clash_target.clone(), &names).await?;
            let client = clash_target.client()?;
            let concurrency = concurrency.clamp(1, 512) as usize;
            let mut stream = stream::iter(names)
                .map(|name| {
                    let target = &clash_target;
                    let client = &client;
                    let group = group.clone();
                    let provider = providers.get(&name).cloned();
                    let test_url = test_url.clone();
                    let expected_status = expected_status.clone();
                    async move {
                        crate::clash::api::proxy_delay_window_with_client(
                            target,
                            client,
                            &group,
                            name,
                            provider.as_deref(),
                            &test_url,
                            timeout_ms,
                            expected_status.as_deref(),
                            clash_member_sort(member_sort),
                            window_offset,
                            window_limit,
                            window_members_hash,
                        )
                        .await
                    }
                })
                .buffer_unordered(concurrency);
            while let Some(event) = stream.next().await {
                if sink.add(event?.into()).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::Surge => {
            let delays =
                crate::surge::api::proxy_group_batch_delay(target.surge(), group.clone(), test_url)
                    .await?;
            for entry in delays {
                let event = crate::surge::api::proxy_delay_window(
                    target.surge(),
                    group.clone(),
                    entry.name,
                    String::new(),
                    member_sort,
                    window_offset,
                    window_limit,
                    window_members_hash,
                )
                .await?;
                if sink.add(event).is_err() {
                    break;
                }
            }
            Ok(())
        }
        BackendType::SingBox => {
            let delays =
                crate::sing_box::api::proxy_group_batch_delay(target.sing_box(), group.clone())
                    .await?;
            for entry in delays {
                let event = crate::sing_box::api::proxy_delay_window(
                    target.sing_box(),
                    group.clone(),
                    entry.name,
                    false,
                    member_sort,
                    window_offset,
                    window_limit,
                    window_members_hash,
                )
                .await?;
                if sink.add(event).is_err() {
                    break;
                }
            }
            Ok(())
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub async fn proxy_delay_window(
    target: BackendTarget,
    group: String,
    name: String,
    test_url: String,
    timeout_ms: u32,
    expected_status: Option<String>,
    member_sort: ProxyMemberSort,
    window_offset: u32,
    window_limit: u32,
    window_members_hash: u32,
) -> Result<ProxyDelayEvent, MihomoError> {
    match target.backend_type {
        BackendType::Clash => Ok(crate::clash::api::proxy_delay_window(
            target.clash(),
            group,
            name,
            test_url,
            timeout_ms,
            expected_status,
            clash_member_sort(member_sort),
            window_offset,
            window_limit,
            window_members_hash,
        )
        .await?
        .into()),
        BackendType::Surge => {
            crate::surge::api::proxy_delay_window(
                target.surge(),
                group,
                name,
                test_url,
                member_sort,
                window_offset,
                window_limit,
                window_members_hash,
            )
            .await
        }
        BackendType::SingBox => {
            crate::sing_box::api::proxy_delay_window(
                target.sing_box(),
                group,
                name,
                !test_url.trim().is_empty(),
                member_sort,
                window_offset,
                window_limit,
                window_members_hash,
            )
            .await
        }
    }
}
