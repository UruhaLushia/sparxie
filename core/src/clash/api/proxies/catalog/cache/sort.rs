use super::CachedNode;
use crate::clash::api::proxies::catalog::ProxyMemberSort;

pub(super) fn sort_members(
    member_ids: &mut [usize],
    sort: ProxyMemberSort,
    lower_names: &[String],
    nodes: &[Option<CachedNode>],
) {
    match sort {
        ProxyMemberSort::Original => {}
        ProxyMemberSort::Name => {
            member_ids.sort_by(|a, b| lower_name(lower_names, *a).cmp(lower_name(lower_names, *b)))
        }
        ProxyMemberSort::Delay => {
            member_ids.sort_by(|a, b| {
                delay_score(delay_of(nodes, *a))
                    .cmp(&delay_score(delay_of(nodes, *b)))
                    .then_with(|| lower_name(lower_names, *a).cmp(lower_name(lower_names, *b)))
            });
        }
    }
}

fn lower_name(names: &[String], id: usize) -> &str {
    names.get(id).map(String::as_str).unwrap_or_default()
}

fn delay_of(nodes: &[Option<CachedNode>], id: usize) -> i32 {
    nodes
        .get(id)
        .and_then(Option::as_ref)
        .map(|node| node.delay)
        .unwrap_or(-1)
}

fn delay_score(delay: i32) -> i32 {
    if delay < 0 {
        1 << 30
    } else if delay == 0 {
        (1 << 30) - 1
    } else {
        delay
    }
}
