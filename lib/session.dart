import 'dart:async';
import 'package:flutter/foundation.dart';

import 'controller.dart';
import 'error_format.dart';
import 'rust_api.dart' as rust;
import 'session/connections.dart';
import 'session/logs.dart';
import 'session/process_icons.dart';
import 'session/proxies.dart';

export 'session/connections.dart';
export 'session/logs.dart';
export 'session/process_icons.dart';
export 'session/proxies.dart';

typedef _ProxyMemberLoadKey = (String, rust.ProxyMemberSort);

class MihomoSession {
  MihomoSession(this.store) {
    store.addListener(_onStoreChange);
    _onStoreChange();
  }

  final ControllerStore store;

  Controller? _activeKey;
  rust.MihomoTarget? _target;

  StreamSubscription<rust.TrafficSample>? _trafficSub;
  StreamSubscription<rust.MemorySample>? _memorySub;
  StreamSubscription<rust.ConnectionsFrame>? _connSub;
  StreamSubscription<List<rust.LogEntry>>? _logsSub;
  Timer? _trafficRetry;
  Timer? _memoryRetry;
  Timer? _connRetry;
  Timer? _logsRetry;
  Timer? _proxiesPoll;
  bool _proxiesRefreshing = false;
  bool _iconsWarmed = false;
  final _proxyMemberLoads = <_ProxyMemberLoadKey>{};
  final _queuedProxyMemberLoads =
      <_ProxyMemberLoadKey, _QueuedProxyMemberLoad>{};

  int _connectionsIntervalMs = 1000;
  int _proxiesIntervalMs = 3000;
  bool _includeHiddenProxyGroups = false;
  String _proxyCatalogFilter = '';
  rust.ProxyMemberSort _proxyMemberSort = rust.ProxyMemberSort.original;
  String _logsLevel = 'info';

  final ValueNotifier<rust.TrafficSample> traffic = ValueNotifier(
    rust.TrafficSample(
      up: BigInt.zero,
      down: BigInt.zero,
      upTotal: BigInt.zero,
      downTotal: BigInt.zero,
    ),
  );

  final ValueNotifier<rust.MemorySample> memory = ValueNotifier(
    rust.MemorySample(inuse: BigInt.zero, oslimit: BigInt.zero),
  );

  late final ConnectionListNotifier connections = ConnectionListNotifier(
    windowFetcher: _fetchConnectionWindow,
    groupsFetcher: _fetchConnectionGroups,
    groupMembersFetcher: _fetchConnectionGroupMembers,
  );

  Future<List<rust.Connection>> _fetchConnectionWindow(
    ConnectionsTab tab,
    int offset,
    int limit,
  ) async {
    final t = _target;
    if (t == null) return const [];
    return rust.fetchConnectionWindow(
      target: t,
      intervalMs: _connectionsIntervalMs,
      kind: tab == ConnectionsTab.active
          ? rust.ConnectionsListKind.active
          : rust.ConnectionsListKind.closed,
      offset: offset,
      limit: limit,
    );
  }

  Future<List<rust.ConnectionGroup>> _fetchConnectionGroups(
    rust.ConnectionGroupSort sort,
    bool asc,
  ) async {
    final t = _target;
    if (t == null) return const [];
    return rust.fetchConnectionGroups(
      target: t,
      intervalMs: _connectionsIntervalMs,
      sort: sort,
      asc: asc,
    );
  }

  Future<List<rust.Connection>> _fetchConnectionGroupMembers(
    String groupKey,
    int limit,
  ) async {
    final t = _target;
    if (t == null) return const [];
    return rust.fetchConnectionGroupMembers(
      target: t,
      intervalMs: _connectionsIntervalMs,
      group: groupKey,
      limit: limit,
    );
  }

  final ValueNotifier<ConnectionsTotals> connectionsTotals = ValueNotifier(
    ConnectionsTotals.zero,
  );

  /// Rolling 500-entry buffer of `/logs` for the active controller. Owned
  /// here so the WebSocket is alive even when the user is on another tab.
  final LogBuffer logs = LogBuffer();

  /// Resolved local-process icons. Only meaningful when [isLocalBackend].
  final ProcessIconCache processIcons = ProcessIconCache();

  final ProxiesNotifier proxies = ProxiesNotifier();

  /// Raw `version` field from `/version`. Empty until first poll succeeds.
  final ValueNotifier<String> versionString = ValueNotifier('');

  /// Number of routing rules on the active backend. Probed once per
  /// controller switch (the ruleset only changes on config reload).
  final ValueNotifier<int> ruleCount = ValueNotifier(0);

  /// True when the active controller is a CMFA-flavored mihomo build.
  /// Driven entirely by [versionString] — its substring `cmfa` is the only
  /// signal mihomo exposes today (no boolean field on `/version`).
  final ValueNotifier<bool> isCmfa = ValueNotifier(false);

  /// While true, incoming connection deltas are dropped on the floor —
  /// the visible row list and totals stay frozen at the last applied
  /// frame. Toggling back to false applies the next delta naturally.
  final ValueNotifier<bool> connectionsPaused = ValueNotifier(false);

  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> isStreaming = ValueNotifier(false);

  Controller? get activeController => _activeKey;
  rust.MihomoTarget? get target => _target;

  /// True when the active controller's host is this machine — process-icon
  /// resolution only makes sense for a local mihomo (the executable paths
  /// in `/connections` refer to processes on the backend's host).
  bool get isLocalBackend {
    final c = _activeKey;
    if (c == null) return false;
    final url = c.baseUrl.trim();
    // IPC transports are always on this machine.
    if (url.startsWith('unix:') || url.startsWith('pipe:')) return true;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  void setConnectionsInterval(int ms) {
    if (ms <= 0 || ms == _connectionsIntervalMs) return;
    _connectionsIntervalMs = ms;
    _restartConnections();
  }

  void setProxiesInterval(int ms) {
    if (ms <= 0 || ms == _proxiesIntervalMs) return;
    _proxiesIntervalMs = ms;
    _restartProxiesPoll();
  }

  void setIncludeHiddenProxyGroups(bool value) {
    setProxyCatalogOptions(includeHidden: value);
  }

  void setProxyCatalogOptions({
    bool? includeHidden,
    String? filter,
    rust.ProxyMemberSort? memberSort,
  }) {
    var catalogChanged = false;
    var sortChanged = false;
    if (includeHidden != null && includeHidden != _includeHiddenProxyGroups) {
      _includeHiddenProxyGroups = includeHidden;
      catalogChanged = true;
    }
    if (filter != null) {
      final next = filter.trim();
      if (next != _proxyCatalogFilter) {
        _proxyCatalogFilter = next;
        catalogChanged = true;
      }
    }
    if (memberSort != null && memberSort != _proxyMemberSort) {
      _proxyMemberSort = memberSort;
      sortChanged = true;
    }
    if (!catalogChanged && !sortChanged) return;
    _proxyMemberLoads.clear();
    _queuedProxyMemberLoads.clear();
    if (catalogChanged) {
      proxies.reset();
      _iconsWarmed = false;
      unawaited(_refreshProxies());
    } else {
      proxies.releaseAllGroupMembers();
    }
  }

  String get logsLevel => _logsLevel;

  void setLogsLevel(String level) {
    final next = level.isEmpty ? 'info' : level;
    if (next == _logsLevel) return;
    _logsLevel = next;
    _restartLogs();
  }

  Future<void> refreshProxies() => _refreshProxies();

  Future<void> ensureProxyGroupMembers(
    String group,
    int firstIndex,
    int lastIndex,
  ) async {
    final t = _target;
    if (t == null) return;
    final request = proxies.memberWindowRequest(group, firstIndex, lastIndex);
    if (request == null) return;
    final loadKey = (group, _proxyMemberSort);
    if (_proxyMemberLoads.contains(loadKey)) {
      _queuedProxyMemberLoads[loadKey] = _QueuedProxyMemberLoad(
        target: t,
        group: group,
        firstIndex: firstIndex,
        lastIndex: lastIndex,
        sort: _proxyMemberSort,
      );
      return;
    }
    await _loadProxyMemberWindow(loadKey, t, group, request, _proxyMemberSort);
  }

  Future<void> _loadProxyMemberWindow(
    _ProxyMemberLoadKey loadKey,
    rust.MihomoTarget target,
    String group,
    ProxyMemberWindowRequest request,
    rust.ProxyMemberSort sort,
  ) async {
    if (!_proxyMemberLoads.add(loadKey)) return;
    try {
      final entries = await rust.proxyGroupMembers(
        target: target,
        group: group,
        offset: request.offset,
        limit: request.limit,
        memberSort: sort,
      );
      if (_target == target && sort == _proxyMemberSort) {
        proxies.applyGroupMembers(
          group,
          request.membersHash,
          request.offset,
          entries,
        );
      }
    } catch (e) {
      if (_target == target) error.value = formatError(e);
      // The next visible tile build will retry.
    } finally {
      _proxyMemberLoads.remove(loadKey);
      _drainQueuedProxyMemberLoad(loadKey);
    }
  }

  void _drainQueuedProxyMemberLoad(_ProxyMemberLoadKey loadKey) {
    final queued = _queuedProxyMemberLoads.remove(loadKey);
    if (queued == null ||
        _target != queued.target ||
        queued.sort != _proxyMemberSort) {
      return;
    }
    final nextRequest = proxies.memberWindowRequest(
      queued.group,
      queued.firstIndex,
      queued.lastIndex,
    );
    if (nextRequest == null) return;
    unawaited(
      _loadProxyMemberWindow(
        loadKey,
        queued.target,
        queued.group,
        nextRequest,
        queued.sort,
      ),
    );
  }

  /// Mobile OSes silently kill backgrounded sockets — Dart still sees the
  /// stream as healthy but no events arrive. Call this on resume to break
  /// out of that limbo.
  void reconnect() {
    if (_target == null) return;
    _resubscribeAll();
  }

  void _onStoreChange() {
    final next = store.active;
    if (identical(next, _activeKey)) return;
    // frb won't abort the old backend's Rust stream tasks when we cancel the
    // Dart subscriptions below; tell the backend to tear them down explicitly
    // so a dead/unreachable old controller doesn't keep retrying forever.
    final previous = _target;
    _activeKey = next;
    _target = next == null
        ? null
        : rust.MihomoTarget(
            baseUrl: next.baseUrl,
            secret: next.secret.isEmpty ? null : next.secret,
            allowInsecure: next.allowInsecure,
          );
    if (previous != null) {
      unawaited(rust.stopTargetStreams(target: previous).catchError((_) {}));
    }
    _resubscribeAll();
  }

  void _resubscribeAll() {
    _cancelAll();
    isStreaming.value = false;
    connections.reset();
    connectionsTotals.value = ConnectionsTotals.zero;
    logs.reset();
    processIcons.reset();
    proxies.reset();
    _proxyMemberLoads.clear();
    _queuedProxyMemberLoads.clear();
    versionString.value = '';
    isCmfa.value = false;
    connectionsPaused.value = false;
    ruleCount.value = 0;
    _iconsWarmed = false;
    if (_target == null) {
      error.value = '请先在“后端”中添加一个 mihomo 实例';
      return;
    }
    error.value = null;
    _subscribeTraffic();
    _subscribeMemory();
    _subscribeConnections();
    _subscribeLogs();
    _startProxiesPoll();
    // Version is build-time fixed; one probe per controller switch is enough.
    unawaited(_probeVersion());
    unawaited(_probeRuleCount());
  }

  void _cancelAll() {
    _trafficSub?.cancel();
    _memorySub?.cancel();
    _connSub?.cancel();
    _logsSub?.cancel();
    _trafficRetry?.cancel();
    _memoryRetry?.cancel();
    _connRetry?.cancel();
    _logsRetry?.cancel();
    _proxiesPoll?.cancel();
    _trafficSub = null;
    _memorySub = null;
    _connSub = null;
    _logsSub = null;
    _trafficRetry = null;
    _memoryRetry = null;
    _connRetry = null;
    _logsRetry = null;
    _proxiesPoll = null;
    _proxyMemberLoads.clear();
    _queuedProxyMemberLoads.clear();
  }

  void _restartConnections() {
    _connSub?.cancel();
    _connRetry?.cancel();
    connections.reset();
    if (_target != null) _subscribeConnections();
  }

  void _restartLogs() {
    _logsSub?.cancel();
    _logsRetry?.cancel();
    _logsSub = null;
    _logsRetry = null;
    logs.reset();
    if (_target != null) _subscribeLogs();
  }

  void _restartProxiesPoll() {
    _proxiesPoll?.cancel();
    _proxiesPoll = null;
    if (_target != null) _startProxiesPoll();
  }

  void _startProxiesPoll() {
    _proxiesPoll?.cancel();
    _refreshProxies();
    _proxiesPoll = Timer.periodic(
      Duration(milliseconds: _proxiesIntervalMs),
      (_) => _refreshProxies(),
    );
  }

  // Version comes from compile-time ldflags, so it can't change while we're
  // connected to the same controller; one probe per (re)connect is enough.
  Future<void> _probeVersion() async {
    final t = _target;
    final controller = _activeKey;
    if (t == null) return;
    try {
      final info = await rust.versionInfo(target: t);
      if (!identical(_activeKey, controller)) return;
      versionString.value = info.version;
      isCmfa.value = info.isCmfa;
    } catch (_) {
      // Non-critical; absent version just means CMFA features default to false.
    }
  }

  // Rules only change on a config reload, so one probe per (re)connect is
  // enough. Count-only so it never disturbs the rules screen's paging cache.
  Future<void> _probeRuleCount() async {
    final t = _target;
    final controller = _activeKey;
    if (t == null) return;
    try {
      final n = await rust.rulesCount(target: t);
      if (identical(_activeKey, controller)) ruleCount.value = n;
    } catch (_) {
      // Non-critical; the badge just stays hidden at 0.
    }
  }

  Future<void> _refreshProxies() async {
    final t = _target;
    final controller = _activeKey;
    if (t == null || _proxiesRefreshing) return;
    _proxiesRefreshing = true;
    var refreshAgain = false;
    try {
      final includeHidden = _includeHiddenProxyGroups;
      final filter = _proxyCatalogFilter;
      final catalog = await rust.proxyCatalog(
        target: t,
        includeHidden: includeHidden,
        filter: filter,
      );
      if (!identical(_activeKey, controller)) return;
      if (includeHidden != _includeHiddenProxyGroups ||
          filter != _proxyCatalogFilter) {
        refreshAgain = true;
        return;
      }
      proxies.applyCatalog(catalog);
      if (!_iconsWarmed) {
        _iconsWarmed = true;
        _warmIconCache(catalog.iconUrls);
      }
    } catch (e) {
      if (identical(_activeKey, controller)) error.value = formatError(e);
    } finally {
      _proxiesRefreshing = false;
      if (refreshAgain) unawaited(_refreshProxies());
    }
  }

  // Kick off background downloads for every group/node icon right after the
  // first proxy list lands, so the disk cache is warm before the user
  // scrolls to them. Fire-and-forget; failures are non-fatal.
  void _warmIconCache(Iterable<String> urls) {
    for (final url in urls) {
      unawaited(rust.fetchIcon(url: url).then((_) {}, onError: (_) {}));
    }
  }

  void _subscribeTraffic() {
    final t = _target;
    if (t == null) return;
    _trafficSub = rust
        .trafficStream(target: t)
        .listen(
          (sample) {
            traffic.value = sample;
            isStreaming.value = true;
          },
          onError: (Object e) => _scheduleRetry(_RetryKind.traffic, e),
          cancelOnError: true,
        );
  }

  void _subscribeMemory() {
    final t = _target;
    if (t == null) return;
    _memorySub = rust
        .memoryStream(target: t)
        .listen(
          (sample) => memory.value = sample,
          onError: (Object e) => _scheduleRetry(_RetryKind.memory, e),
          cancelOnError: true,
        );
  }

  void _subscribeConnections() {
    final t = _target;
    if (t == null) return;
    _connSub = rust
        .connectionsStream(target: t, intervalMs: _connectionsIntervalMs)
        .listen(
          (frame) {
            if (connectionsPaused.value) {
              isStreaming.value = true;
              return;
            }
            connections.applyFrame(frame);
            connectionsTotals.value = ConnectionsTotals(
              upload: frame.totals.upload,
              download: frame.totals.download,
              memory: frame.totals.memory,
              count: connections.activeCount,
            );
            isStreaming.value = true;
          },
          onError: (Object e) => _scheduleRetry(_RetryKind.connections, e),
          cancelOnError: true,
        );
  }

  void _subscribeLogs() {
    final t = _target;
    if (t == null) return;
    final controller = _activeKey;
    // Rust replays its ring buffer on every subscribe, so wipe the mirror
    // first to avoid stacking duplicates.
    logs.reset();
    _logsSub = rust
        .logsStream(target: t, level: _logsLevel)
        .listen(
          (entries) {
            if (!identical(_activeKey, controller)) return;
            logs.addAll(entries);
          },
          onError: (Object e) => _scheduleRetry(_RetryKind.logs, e),
          cancelOnError: true,
        );
  }

  /// Drop both the Rust ring buffer and the Dart mirror; upstream stream
  /// keeps running.
  Future<void> clearLogs() async {
    final t = _target;
    logs.clearLocal();
    if (t == null) return;
    await rust.clearLogs(target: t, level: _logsLevel);
  }

  void _scheduleRetry(_RetryKind kind, Object cause) {
    error.value = '$cause';
    final controller = _activeKey;
    final delay = const Duration(seconds: 2);
    switch (kind) {
      case _RetryKind.traffic:
        _trafficRetry?.cancel();
        _trafficRetry = Timer(delay, () {
          if (identical(_activeKey, controller)) _subscribeTraffic();
        });
      case _RetryKind.memory:
        _memoryRetry?.cancel();
        _memoryRetry = Timer(delay, () {
          if (identical(_activeKey, controller)) _subscribeMemory();
        });
      case _RetryKind.connections:
        _connRetry?.cancel();
        _connRetry = Timer(delay, () {
          if (identical(_activeKey, controller)) _subscribeConnections();
        });
      case _RetryKind.logs:
        _logsRetry?.cancel();
        _logsRetry = Timer(delay, () {
          if (identical(_activeKey, controller)) _subscribeLogs();
        });
    }
  }

  void dispose() {
    store.removeListener(_onStoreChange);
    _cancelAll();
    traffic.dispose();
    memory.dispose();
    connectionsTotals.dispose();
    connections.dispose();
    logs.dispose();
    processIcons.dispose();
    versionString.dispose();
    isCmfa.dispose();
    ruleCount.dispose();
    connectionsPaused.dispose();
    error.dispose();
    isStreaming.dispose();
  }
}

enum _RetryKind { traffic, memory, connections, logs }

class _QueuedProxyMemberLoad {
  const _QueuedProxyMemberLoad({
    required this.target,
    required this.group,
    required this.firstIndex,
    required this.lastIndex,
    required this.sort,
  });

  final rust.MihomoTarget target;
  final String group;
  final int firstIndex;
  final int lastIndex;
  final rust.ProxyMemberSort sort;
}
