/// Single import surface for the generated flutter_rust_bridge bindings.
/// Re-exports keep screen code stable when we reorganize the Rust side.
library;

export 'src/rust/api.dart' show MihomoTarget;
export 'src/rust/utils/error.dart';
export 'src/rust/state/logs.dart' show LogEntry;
export 'src/rust/state/traffic.dart' show MemorySample, TrafficSample;
export 'src/rust/state/connections/types.dart'
    show
        Connection,
        ConnectionGroup,
        ConnectionGroupSort,
        ConnectionsFrame,
        ConnectionsListKind,
        ConnectionsSort,
        ConnectionsTotals;

export 'src/rust/api/cache.dart';
export 'src/rust/api/configs.dart';
export 'src/rust/api/connections.dart';
export 'src/rust/api/dns.dart';
export 'src/rust/api/fonts.dart';
export 'src/rust/api/groups.dart';
export 'src/rust/api/icons.dart';
export 'src/rust/api/providers.dart';
export 'src/rust/api/proxies.dart';
export 'src/rust/api/proxies/catalog.dart';
export 'src/rust/api/proxies/delay.dart';
export 'src/rust/api/rules.dart';
export 'src/rust/api/storage.dart';
export 'src/rust/api/streams.dart';
export 'src/rust/api/upgrade.dart';
export 'src/rust/api/version.dart';
