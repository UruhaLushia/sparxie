/// Single import surface for the generated flutter_rust_bridge bindings.
/// Re-exports keep screen code stable when we reorganize the Rust side.
library;

export 'src/rust/api.dart' show MihomoTarget;
export 'src/rust/error.dart';
export 'src/rust/traffic.dart' show LogEntry, MemorySample, TrafficSample;
export 'src/rust/connections_state.dart'
    show
        Connection,
        ConnectionsFrame,
        ConnectionsListKind,
        ConnectionsSort,
        ConnectionsTotals;

export 'src/rust/api/cache.dart';
export 'src/rust/api/configs.dart';
export 'src/rust/api/connections.dart';
export 'src/rust/api/dns.dart';
export 'src/rust/api/groups.dart';
export 'src/rust/api/icons.dart';
export 'src/rust/api/providers.dart';
export 'src/rust/api/proxies.dart';
export 'src/rust/api/rules.dart';
export 'src/rust/api/storage.dart';
export 'src/rust/api/streams.dart';
export 'src/rust/api/upgrade.dart';
export 'src/rust/api/version.dart';
