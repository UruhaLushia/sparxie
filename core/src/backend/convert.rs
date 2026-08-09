use super::types::*;

mod sorts;

pub(in crate::backend::api) use sorts::{
    clash_conn_sort, clash_group_sort, clash_list_kind, clash_member_sort,
};

impl From<crate::clash::state::traffic::TrafficSample> for TrafficSample {
    fn from(value: crate::clash::state::traffic::TrafficSample) -> Self {
        Self {
            up: value.up,
            down: value.down,
            up_total: value.up_total,
            down_total: value.down_total,
        }
    }
}

impl From<crate::clash::state::traffic::MemorySample> for MemorySample {
    fn from(value: crate::clash::state::traffic::MemorySample) -> Self {
        Self {
            inuse: value.inuse,
            oslimit: value.oslimit,
            goroutines: 0,
        }
    }
}

impl From<crate::clash::state::connections::Connection> for Connection {
    fn from(value: crate::clash::state::connections::Connection) -> Self {
        Self {
            id: value.id,
            host: value.host,
            network: value.network,
            conn_type: value.conn_type,
            source_ip: value.source_ip,
            source_port: value.source_port,
            destination_ip: value.destination_ip,
            destination_port: value.destination_port,
            inbound_ip: value.inbound_ip,
            inbound_port: value.inbound_port,
            inbound_name: value.inbound_name,
            dns_mode: value.dns_mode,
            uid: value.uid,
            process: value.process,
            process_path: value.process_path,
            special_proxy: value.special_proxy,
            special_rules: value.special_rules,
            remote_destination: value.remote_destination,
            sniff_host: value.sniff_host,
            rule: value.rule,
            rule_payload: value.rule_payload,
            chains: value.chains,
            connection_logs: value.connection_logs,
            upload: value.upload,
            download: value.download,
            upload_speed: value.upload_speed,
            download_speed: value.download_speed,
            start: value.start,
            is_closed: value.is_closed,
        }
    }
}

impl From<crate::clash::state::connections::ConnectionsTotals> for ConnectionsTotals {
    fn from(value: crate::clash::state::connections::ConnectionsTotals) -> Self {
        Self {
            upload: value.upload,
            download: value.download,
            memory: value.memory,
            connections_in: 0,
            connections_out: 0,
        }
    }
}

impl From<crate::clash::state::connections::ConnectionGroup> for ConnectionGroup {
    fn from(value: crate::clash::state::connections::ConnectionGroup) -> Self {
        Self {
            key: value.key,
            label: value.label,
            process: value.process,
            process_path: value.process_path,
            source_ip: value.source_ip,
            count: value.count,
            upload: value.upload,
            download: value.download,
            upload_speed: value.upload_speed,
            download_speed: value.download_speed,
        }
    }
}

impl From<crate::clash::state::connections::ConnectionsFrame> for ConnectionsFrame {
    fn from(value: crate::clash::state::connections::ConnectionsFrame) -> Self {
        Self {
            active_count: value.active_count,
            closed_count: value.closed_count,
            totals: value.totals.into(),
            is_initial: value.is_initial,
        }
    }
}

impl From<crate::clash::api::ProxyCatalog> for ProxyCatalog {
    fn from(value: crate::clash::api::ProxyCatalog) -> Self {
        Self {
            groups: value.groups.into_iter().map(Into::into).collect(),
            icon_urls: value.icon_urls,
        }
    }
}

impl From<crate::clash::api::ProxyGroupEntry> for ProxyGroupEntry {
    fn from(value: crate::clash::api::ProxyGroupEntry) -> Self {
        let selectable = value.proxy_type != "LoadBalance";
        Self {
            name: value.name,
            proxy_type: value.proxy_type,
            selectable,
            icon: value.icon,
            member_count: value.member_count,
            members_hash: value.members_hash,
            now: value.now,
            now_delay: value.now_delay,
            test_url: value.test_url,
            fixed: value.fixed,
        }
    }
}

impl From<crate::clash::api::ProxyMemberEntry> for ProxyMemberEntry {
    fn from(value: crate::clash::api::ProxyMemberEntry) -> Self {
        Self {
            name: value.name,
            proxy_type: value.proxy_type,
            delay: value.delay,
        }
    }
}

impl From<crate::clash::api::ProxyMemberSection> for ProxyMemberSection {
    fn from(value: crate::clash::api::ProxyMemberSection) -> Self {
        Self {
            provider: value.provider,
            offset: value.offset,
            count: value.count,
        }
    }
}

impl From<crate::clash::api::ProxyMemberWindow> for ProxyMemberWindow {
    fn from(value: crate::clash::api::ProxyMemberWindow) -> Self {
        Self {
            entries: value.entries.into_iter().map(Into::into).collect(),
            sections: value.sections.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<crate::clash::api::ProxyDelayEntry> for ProxyDelayEntry {
    fn from(value: crate::clash::api::ProxyDelayEntry) -> Self {
        Self {
            name: value.name,
            delay: value.delay,
        }
    }
}

impl From<crate::clash::api::ProxyDelayEvent> for ProxyDelayEvent {
    fn from(value: crate::clash::api::ProxyDelayEvent) -> Self {
        Self {
            name: value.name,
            delay: value.delay,
            window_offset: value.window_offset,
            window_members_hash: value.window_members_hash,
            window_entries: value.window_entries.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<crate::clash::api::GroupDelayEntry> for GroupDelayEntry {
    fn from(value: crate::clash::api::GroupDelayEntry) -> Self {
        Self {
            name: value.name,
            delay: value.delay,
        }
    }
}

impl From<crate::clash::api::ProxyProviderEntry> for ProxyProviderEntry {
    fn from(value: crate::clash::api::ProxyProviderEntry) -> Self {
        Self {
            name: value.name,
            vehicle_type: value.vehicle_type,
            proxies: value.proxies,
            updated_at: value.updated_at,
            updatable: value.updatable,
            has_subscription_info: value.has_subscription_info,
            subscription_upload: value.subscription_upload,
            subscription_download: value.subscription_download,
            subscription_total: value.subscription_total,
            subscription_expire: value.subscription_expire,
        }
    }
}

impl From<crate::clash::api::RuleProviderEntry> for RuleProviderEntry {
    fn from(value: crate::clash::api::RuleProviderEntry) -> Self {
        Self {
            name: value.name,
            vehicle_type: value.vehicle_type,
            behavior: value.behavior,
            format: value.format,
            rule_count: value.rule_count,
            updated_at: value.updated_at,
            updatable: value.updatable,
        }
    }
}

impl From<crate::clash::api::RuleEntry> for RuleEntry {
    fn from(value: crate::clash::api::RuleEntry) -> Self {
        Self {
            index: value.index,
            rule_type: value.rule_type,
            payload: value.payload,
            proxy: value.proxy,
            extra_params: value.extra_params,
            disabled: value.disabled,
            hit_count: value.hit_count,
            hit_at: value.hit_at,
            miss_count: value.miss_count,
            miss_at: value.miss_at,
            has_extra: value.has_extra,
        }
    }
}

impl From<crate::clash::api::RulesSummary> for RulesSummary {
    fn from(value: crate::clash::api::RulesSummary) -> Self {
        Self {
            total: value.total,
            filtered: value.filtered,
        }
    }
}

impl From<crate::clash::api::VersionInfo> for VersionInfo {
    fn from(value: crate::clash::api::VersionInfo) -> Self {
        Self {
            version: value.version,
            is_cmfa: value.is_cmfa,
            is_stash: value.is_stash,
            supports_core_config: value.supports_core_config,
            supports_core_actions: value.supports_core_actions,
            supports_core_management: value.supports_core_management,
            supports_cache_flush: value.supports_cache_flush,
            supports_memory: value.supports_memory,
            supports_tailscale: false,
            supports_diagnostics: false,
        }
    }
}
