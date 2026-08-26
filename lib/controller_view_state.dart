import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'controller.dart';
import 'error_format.dart';
import 'rust_api.dart' as rust;
import 'view_state/connections.dart';
import 'view_state/logs.dart';
import 'view_state/process_icons.dart';
import 'view_state/proxies.dart';

export 'view_state/connections.dart';
export 'view_state/logs.dart';
export 'view_state/process_icons.dart';
export 'view_state/proxies.dart';

typedef _ProxyMemberLoadKey = ({
  String group,
  rust.ProxyMemberSort sort,
  bool groupByProvider,
});

const _retryDelays = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
];

class ControllerViewState {
  ControllerViewState(
    this.store, {
    int connectionsIntervalMs = 1000,
    int closedConnectionsCapacity = 500,
    int logInfoCapacity = 500,
  }) : _connectionsIntervalMs = connectionsIntervalMs > 0
           ? connectionsIntervalMs
           : 1000,
       _closedConnectionsCapacity = closedConnectionsCapacity > 0
           ? closedConnectionsCapacity
           : 1,
       _logInfoCapacity = logInfoCapacity > 0 ? logInfoCapacity : 1 {
    store.addListener(_onStoreChange);
    _onStoreChange();
  }

  final ControllerStore store;

  Controller? _activeKey;
  rust.BackendTarget? _target;

  StreamSubscription<rust.TrafficSample>? _trafficSub;
  StreamSubscription<rust.MemorySample>? _memorySub;
  StreamSubscription<rust.ConnectionsFrame>? _connSub;
  StreamSubscription<rust.LogsFrame>? _logsSub;
  Timer? _trafficRetry;
  Timer? _memoryRetry;
  Timer? _connRetry;
  Timer? _logsRetry;
  Timer? _proxiesPoll;
  bool _proxiesRefreshing = false;
  bool _iconsWarmed = false;
  int _iconWarmGeneration = 0;
  _ViewErrorSource? _errorSource;
  final _retryAttempts = <_RetryKind, int>{};
  int _trafficEpoch = 0;
  int _memoryEpoch = 0;
  int _connectionsEpoch = 0;
  int _logsEpoch = 0;
  final _proxyMemberLoads = <_ProxyMemberLoadKey>{};
  final _queuedProxyMemberLoads =
      <_ProxyMemberLoadKey, _QueuedProxyMemberLoad>{};

  int _connectionsIntervalMs;
  int _closedConnectionsCapacity;
  int _proxiesIntervalMs = 3000;
  bool _includeHiddenProxyGroups = false;
  String _proxyCatalogFilter = '';
  rust.ProxyMemberSort _proxyMemberSort = rust.ProxyMemberSort.original;
  bool _groupProxyMembersByProvider = false;
  String _logsLevel = 'info';
  int _logInfoCapacity;

  final ValueNotifier<rust.TrafficSample> traffic = _TelemetryValueNotifier(
    rust.TrafficSample(
      up: BigInt.zero,
      down: BigInt.zero,
      upTotal: BigInt.zero,
      downTotal: BigInt.zero,
    ),
  );

  final ValueNotifier<rust.MemorySample> memory = _TelemetryValueNotifier(
    rust.MemorySample(inuse: BigInt.zero, oslimit: BigInt.zero, goroutines: 0),
  );

  late final ConnectionListNotifier connections = ConnectionListNotifier(
    windowFetcher: _fetchConnectionWindow,
    groupsFetcher: _fetchConnectionGroups,
    groupMembersFetcher: _fetchConnectionGroupMembers,
  );

  Future<rust.ConnectionWindow> _fetchConnectionWindow(
    ConnectionsTab tab,
    int offset,
    int limit,
    String query,
  ) async {
    final t = _target;
    if (t == null) return const rust.ConnectionWindow(total: 0, rows: []);
    return rust.controllerFetchConnectionWindow(
      target: t,
      intervalMs: _connectionsIntervalMs,
      kind: tab == ConnectionsTab.active
          ? rust.ConnectionsListKind.active
          : rust.ConnectionsListKind.closed,
      offset: offset,
      limit: limit,
      query: query,
    );
  }

  Future<rust.ConnectionStats?> fetchConnectionStats(String id) async {
    final t = _target;
    if (t == null) return null;
    return rust.controllerFetchConnectionStatsById(
      target: t,
      intervalMs: _connectionsIntervalMs,
      id: id,
    );
  }

  Future<rust.LogWindow> _fetchLogsWindow(
    int offset,
    int limit,
    String level,
    String query,
    bool fromEnd,
    BigInt? anchorId,
  ) async {
    final t = _target;
    if (t == null) {
      return const rust.LogWindow(total: 0, offset: 0, rows: []);
    }
    return rust.controllerFetchLogsWindow(
      target: t,
      level: level,
      query: query,
      offset: offset,
      limit: limit,
      fromEnd: fromEnd,
      anchorId: anchorId ?? BigInt.zero,
    );
  }

  Future<List<rust.ConnectionGroup>> _fetchConnectionGroups(
    ConnectionsTab tab,
    rust.ConnectionGroupSort sort,
    bool asc,
    String query,
  ) async {
    final t = _target;
    if (t == null) return const [];
    return rust.controllerFetchConnectionGroups(
      target: t,
      intervalMs: _connectionsIntervalMs,
      kind: tab == ConnectionsTab.active
          ? rust.ConnectionsListKind.active
          : rust.ConnectionsListKind.closed,
      sort: sort,
      asc: asc,
      query: query,
    );
  }

  Future<List<rust.Connection>> _fetchConnectionGroupMembers(
    ConnectionsTab tab,
    String groupKey,
    int limit,
    String query,
  ) async {
    final t = _target;
    if (t == null) return const [];
    return rust.controllerFetchConnectionGroupMembers(
      target: t,
      intervalMs: _connectionsIntervalMs,
      kind: tab == ConnectionsTab.active
          ? rust.ConnectionsListKind.active
          : rust.ConnectionsListKind.closed,
      group: groupKey,
      limit: limit,
      query: query,
    );
  }

  final ValueNotifier<ConnectionsTotals> connectionsTotals = ValueNotifier(
    ConnectionsTotals.zero,
  );

  late final LogWindowNotifier logs = LogWindowNotifier(
    windowFetcher: _fetchLogsWindow,
  );

  /// Resolved local-process icons. Only meaningful when [isLocalBackend].
  final ProcessIconCache processIcons = ProcessIconCache();

  final ProxiesNotifier proxies = ProxiesNotifier();

  /// Raw `version` field from `/version`. Empty until first poll succeeds.
  final ValueNotifier<String> versionString = ValueNotifier('');

  /// Number of routing rules on the active backend. Probed once per
  /// controller switch (the ruleset only changes on config reload).
  final ValueNotifier<int> ruleCount = ValueNotifier(0);

  /// True when the active controller is a CMFA-flavored mihomo build.
  final ValueNotifier<bool> isCmfa = ValueNotifier(false);

  final ValueNotifier<bool> isStash = ValueNotifier(false);
  final ValueNotifier<bool> supportsCoreConfig = ValueNotifier(false);
  final ValueNotifier<bool> supportsCoreActions = ValueNotifier(false);
  final ValueNotifier<bool> supportsCoreManagement = ValueNotifier(false);
  final ValueNotifier<bool> supportsCacheFlush = ValueNotifier(false);
  final ValueNotifier<bool> supportsDnsFlush = ValueNotifier(false);
  final ValueNotifier<bool> supportsMemory = ValueNotifier(false);
  final ValueNotifier<bool> supportsExternalResources = ValueNotifier(false);
  final ValueNotifier<bool> supportsRules = ValueNotifier(false);
  final ValueNotifier<bool> supportsTailscale = ValueNotifier(false);
  final ValueNotifier<bool> supportsDiagnostics = ValueNotifier(false);

  /// While true, incoming connection deltas are dropped on the floor —
  /// the visible row list and totals stay frozen at the last applied
  /// frame. Toggling back to false applies the next delta naturally.
  final ValueNotifier<bool> connectionsPaused = ValueNotifier(false);

  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> isStreaming = ValueNotifier(false);

  Controller? get activeController => _activeKey;
  rust.BackendTarget? get target => _target;
  int get connectionsIntervalMs => _connectionsIntervalMs;

  /// True when the active controller's host is this machine — process-icon
  /// resolution only makes sense for a local mihomo (the executable paths
  /// in `/connections` refer to processes on the backend's host).
  bool get isLocalBackend {
    final c = _activeKey;
    if (c == null) return false;
    final url = c.baseUrl.trim();
    // IPC transports are always on this machine.
    if (url.startsWith('unix:') ||
        url.startsWith('pipe:') ||
        url.startsWith('sparkle-service:') ||
        url.startsWith('local:')) {
      return true;
    }
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  void setConnectionsInterval(int ms) {
    if (ms <= 0 || ms == _connectionsIntervalMs) return;
    _connectionsIntervalMs = ms;
    _restartConnections();
  }

  void setClosedConnectionsCapacity(int value) {
    final next = value > 0 ? value : 1;
    if (next == _closedConnectionsCapacity) return;
    _closedConnectionsCapacity = next;
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
    bool? groupByProvider,
  }) {
    var catalogChanged = false;
    var memberOrderChanged = false;
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
      memberOrderChanged = true;
    }
    if (groupByProvider != null &&
        groupByProvider != _groupProxyMembersByProvider) {
      _groupProxyMembersByProvider = groupByProvider;
      memberOrderChanged = true;
    }
    if (!catalogChanged && !memberOrderChanged) return;
    _proxyMemberLoads.clear();
    _queuedProxyMemberLoads.clear();
    if (catalogChanged) {
      proxies.reset();
      _iconsWarmed = false;
      _iconWarmGeneration++;
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
    logs.setLevel(next);
  }

  void setLogInfoCapacity(int value) {
    final next = value > 0 ? value : 1;
    if (next == _logInfoCapacity) return;
    _logInfoCapacity = next;
    _restartLogs();
  }

  Future<void> refreshProxies() => _refreshProxies();

  Future<void> ensureProxyGroupMembers(
    String group,
    int firstIndex,
    int lastIndex, {
    bool locateCurrent = false,
  }) async {
    final t = _target;
    if (t == null) return;
    final request = proxies.memberWindowRequest(
      group,
      firstIndex,
      lastIndex,
      force: locateCurrent,
    );
    if (request == null) return;
    final groupByProvider = _groupProxyMembersByProvider;
    final loadKey = (
      group: group,
      sort: _proxyMemberSort,
      groupByProvider: groupByProvider,
    );
    if (_proxyMemberLoads.contains(loadKey)) {
      final previous = _queuedProxyMemberLoads[loadKey];
      _queuedProxyMemberLoads[loadKey] = _QueuedProxyMemberLoad(
        target: t,
        group: group,
        firstIndex: previous == null
            ? firstIndex
            : math.min(previous.firstIndex, firstIndex),
        lastIndex: previous == null
            ? lastIndex
            : math.max(previous.lastIndex, lastIndex),
        sort: _proxyMemberSort,
        groupByProvider: groupByProvider,
        locateCurrent: locateCurrent || (previous?.locateCurrent ?? false),
      );
      return;
    }
    await _loadProxyMemberWindow(
      loadKey,
      t,
      group,
      request,
      _proxyMemberSort,
      groupByProvider,
      locateCurrent,
    );
  }

  Future<void> _loadProxyMemberWindow(
    _ProxyMemberLoadKey loadKey,
    rust.BackendTarget target,
    String group,
    ProxyMemberWindowRequest request,
    rust.ProxyMemberSort sort,
    bool groupByProvider,
    bool locateCurrent,
  ) async {
    if (!_proxyMemberLoads.add(loadKey)) return;
    try {
      final window = await rust.controllerProxyGroupMembers(
        target: target,
        group: group,
        offset: request.offset,
        limit: request.limit,
        memberSort: sort,
        groupByProvider: groupByProvider,
        currentName: locateCurrent ? proxies.memberCurrentName(group) : null,
      );
      if (_target == target &&
          sort == _proxyMemberSort &&
          groupByProvider == _groupProxyMembersByProvider) {
        proxies.applyGroupMembers(
          group,
          request.membersHash,
          window.offset,
          window.entries,
          sections: window.sections,
          currentIndex: locateCurrent ? window.currentIndex : null,
        );
        _clearError(_ViewErrorSource.proxyMember);
      }
    } catch (e) {
      if (_target == target) {
        _showError(_formatError(e), _ViewErrorSource.proxyMember);
      }
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
    if (queued.groupByProvider != _groupProxyMembersByProvider) {
      return;
    }
    final nextRequest = proxies.memberWindowRequest(
      queued.group,
      queued.firstIndex,
      queued.lastIndex,
      force: queued.locateCurrent,
    );
    if (nextRequest == null) return;
    unawaited(
      _loadProxyMemberWindow(
        loadKey,
        queued.target,
        queued.group,
        nextRequest,
        queued.sort,
        queued.groupByProvider,
        queued.locateCurrent,
      ),
    );
  }

  /// Mobile OSes silently kill backgrounded sockets — Dart still sees the
  /// stream as healthy but no events arrive. Call this on resume to break
  /// out of that limbo.
  void reconnect() {
    if (_target == null) return;
    // Resuming is not a controller switch. Keep UI caches and notifier
    // identities alive so open routes remain valid while streams reconnect.
    _cancelAll();
    isStreaming.value = false;
    _startLiveUpdates(proxyDelay: const Duration(milliseconds: 120));
  }

  void _stopTargetStreams(rust.BackendTarget? target) {
    if (target == null) return;
    unawaited(
      rust.controllerStopTargetStreams(target: target).catchError((_) {}),
    );
  }

  void _onStoreChange() {
    final next = store.active;
    if (identical(next, _activeKey)) return;
    // frb won't abort the old backend's Rust stream tasks when we cancel the
    // Dart subscriptions below; tell the backend to tear them down explicitly
    // so a dead/unreachable old controller doesn't keep retrying forever.
    final previous = _target;
    _activeKey = next;
    _target = next == null ? null : rust.backendTargetForController(next);
    _stopTargetStreams(previous);
    _resubscribeAll();
  }

  void clearTelemetry() {
    traffic.value = rust.TrafficSample(
      up: BigInt.zero,
      down: BigInt.zero,
      upTotal: BigInt.zero,
      downTotal: BigInt.zero,
    );
    memory.value = rust.MemorySample(
      inuse: BigInt.zero,
      oslimit: BigInt.zero,
      goroutines: 0,
    );
  }

  void _resubscribeAll() {
    _cancelAll();
    isStreaming.value = false;
    clearTelemetry();
    connections.reset();
    connectionsTotals.value = ConnectionsTotals.zero;
    logs.reset();
    processIcons.reset();
    proxies.reset();
    _proxyMemberLoads.clear();
    _queuedProxyMemberLoads.clear();
    versionString.value = '';
    isCmfa.value = false;
    isStash.value = false;
    supportsCoreConfig.value = false;
    supportsCoreActions.value = false;
    supportsCoreManagement.value = false;
    supportsCacheFlush.value = false;
    supportsDnsFlush.value =
        (_activeKey?.type == BackendType.surge ||
            _activeKey?.type == BackendType.surgeController) &&
        _target != null;
    supportsCoreActions.value = supportsDnsFlush.value;
    supportsMemory.value = false;
    supportsExternalResources.value =
        (_activeKey?.type == BackendType.clash ||
            _activeKey?.type == BackendType.surgeController) &&
        _target != null;
    supportsRules.value =
        _target != null && _activeKey?.type != BackendType.singBox;
    supportsTailscale.value = false;
    supportsDiagnostics.value = false;
    if (_activeKey?.type != BackendType.singBox && _logsLevel == 'trace') {
      _logsLevel = 'debug';
    }
    logs.setLevel(_logsLevel);
    connectionsPaused.value = false;
    ruleCount.value = 0;
    _iconsWarmed = false;
    _iconWarmGeneration++;
    if (_target == null) {
      _showError('请先在“后端”中添加一个后端', _ViewErrorSource.controller);
      return;
    }
    _clearError();
    _startLiveUpdates();
    unawaited(_prepareTarget());
    // Version is build-time fixed; one probe per controller switch is enough.
    unawaited(_probeVersion());
  }

  void _startLiveUpdates({Duration proxyDelay = Duration.zero}) {
    _subscribeTraffic();
    _subscribeConnections();
    _subscribeLogs();
    if (proxyDelay == Duration.zero) {
      _startProxiesPoll();
    } else {
      _proxiesPoll?.cancel();
      _proxiesPoll = Timer(proxyDelay, _startProxiesPoll);
    }
    if (supportsMemory.value) _subscribeMemory();
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
    _invalidateAllStreams();
    _trafficSub = null;
    _memorySub = null;
    _connSub = null;
    _logsSub = null;
    _trafficRetry = null;
    _memoryRetry = null;
    _connRetry = null;
    _logsRetry = null;
    _proxiesPoll = null;
    _retryAttempts.clear();
    _proxyMemberLoads.clear();
    _queuedProxyMemberLoads.clear();
  }

  void _restartConnections() {
    _connectionsEpoch++;
    final previous = _connSub;
    _connRetry?.cancel();
    _connSub = null;
    _connRetry = null;
    _retryAttempts.remove(_RetryKind.connections);
    connections.reset();
    if (_target != null) {
      _subscribeConnections(previous: previous);
    } else {
      previous?.cancel();
    }
  }

  void _restartLogs() {
    _logsEpoch++;
    final previous = _logsSub;
    _logsRetry?.cancel();
    _logsSub = null;
    _logsRetry = null;
    _retryAttempts.remove(_RetryKind.logs);
    if (_target != null) {
      _subscribeLogs(previous: previous);
    } else {
      previous?.cancel();
    }
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
      final info = await rust.controllerVersionInfo(target: t);
      if (!identical(_activeKey, controller)) return;
      versionString.value = info.version;
      isCmfa.value = info.isCmfa;
      isStash.value = info.isStash;
      supportsCoreConfig.value = info.supportsCoreConfig;
      supportsCoreManagement.value = info.supportsCoreManagement;
      supportsCacheFlush.value = info.supportsCacheFlush;
      supportsDnsFlush.value =
          info.supportsCacheFlush ||
          controller?.type == BackendType.surge ||
          controller?.type == BackendType.surgeController;
      supportsCoreActions.value =
          info.supportsCoreActions || supportsDnsFlush.value;
      supportsMemory.value = info.supportsMemory;
      supportsTailscale.value = info.supportsTailscale;
      supportsDiagnostics.value = info.supportsDiagnostics;
      if (info.supportsMemory && _memorySub == null) _subscribeMemory();
    } catch (_) {
      // Non-critical; capability-gated UI stays hidden until a later reconnect.
    }
  }

  Future<void> _prepareTarget() async {
    final target = _target;
    final controller = _activeKey;
    if (target == null) return;
    try {
      final bootstrap = await rust.controllerPrepareTarget(target: target);
      if (identical(_activeKey, controller)) {
        ruleCount.value = bootstrap.ruleCount;
      }
    } catch (_) {
      // Static page data loads again on demand if connection bootstrap fails.
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
      final catalog = await rust.controllerProxyCatalog(
        target: t,
        includeHidden: includeHidden,
        resolveProviderCurrentDelay: false,
        filter: filter,
      );
      if (!identical(_activeKey, controller)) return;
      if (includeHidden != _includeHiddenProxyGroups ||
          filter != _proxyCatalogFilter) {
        refreshAgain = true;
        return;
      }
      proxies.applyCatalog(catalog);
      _clearError(_ViewErrorSource.proxyCatalog);
      if (!_iconsWarmed) {
        _iconsWarmed = true;
        final generation = ++_iconWarmGeneration;
        _warmIconCache(catalog.iconUrls, generation);
      }
    } catch (e) {
      if (identical(_activeKey, controller)) {
        _showError(_formatError(e), _ViewErrorSource.proxyCatalog);
      }
    } finally {
      _proxiesRefreshing = false;
      if (refreshAgain) unawaited(_refreshProxies());
    }
  }

  // Kick off background downloads for every group/node icon right after the
  // first proxy list lands, so the disk cache is warm before the user
  // scrolls to them. Fire-and-forget; failures are non-fatal.
  void _warmIconCache(List<String> urls, int generation) {
    const maxWorkers = 4;
    final workers = math.min(maxWorkers, urls.length);
    for (var worker = 0; worker < workers; worker++) {
      unawaited(_warmIcons(urls, worker, workers, generation));
    }
  }

  Future<void> _warmIcons(
    List<String> urls,
    int start,
    int stride,
    int generation,
  ) async {
    for (var i = start; i < urls.length; i += stride) {
      if (generation != _iconWarmGeneration) return;
      try {
        await rust.fetchIcon(url: urls[i]);
      } catch (_) {
        // A failed icon keeps its normal letter fallback.
      }
    }
  }

  void _subscribeTraffic() {
    final t = _target;
    if (t == null) return;
    final controller = _activeKey;
    final epoch = _nextStreamEpoch(_RetryKind.traffic);
    _trafficSub = rust
        .controllerTrafficStream(target: t)
        .listen(
          (sample) {
            if (!_isCurrentStream(_RetryKind.traffic, controller, epoch)) {
              return;
            }
            _markStreamHealthy(_RetryKind.traffic);
            traffic.value = sample;
            isStreaming.value = true;
          },
          onError: (Object e) =>
              _scheduleRetry(_RetryKind.traffic, controller, epoch, e),
          cancelOnError: true,
        );
  }

  void _subscribeMemory() {
    final t = _target;
    if (t == null) return;
    final controller = _activeKey;
    final epoch = _nextStreamEpoch(_RetryKind.memory);
    _memorySub = rust
        .controllerMemoryStream(target: t)
        .listen(
          (sample) {
            if (!_isCurrentStream(_RetryKind.memory, controller, epoch)) {
              return;
            }
            _markStreamHealthy(_RetryKind.memory);
            memory.value = sample;
          },
          onError: (Object e) =>
              _scheduleRetry(_RetryKind.memory, controller, epoch, e),
          cancelOnError: true,
        );
  }

  void _subscribeConnections({
    StreamSubscription<rust.ConnectionsFrame>? previous,
  }) {
    final t = _target;
    if (t == null) return;
    final controller = _activeKey;
    final epoch = _nextStreamEpoch(_RetryKind.connections);
    var receivedFrame = false;
    var previousSub = previous;
    _connSub = rust
        .controllerConnectionsStream(
          target: t,
          intervalMs: _connectionsIntervalMs,
          closedCapacity: _closedConnectionsCapacity,
        )
        .listen(
          (frame) {
            if (!_isCurrentStream(_RetryKind.connections, controller, epoch)) {
              return;
            }
            if (!receivedFrame) {
              receivedFrame = true;
              unawaited(previousSub?.cancel());
              previousSub = null;
            }
            _markStreamHealthy(_RetryKind.connections);
            if (connectionsPaused.value) {
              isStreaming.value = true;
              return;
            }
            connections.applyFrame(frame);
            final currentTraffic = traffic.value;
            connectionsTotals.value = ConnectionsTotals(
              upload: currentTraffic.upTotal,
              download: currentTraffic.downTotal,
              memory: supportsMemory.value ? frame.totals.memory : BigInt.zero,
              connectionsIn: frame.totals.connectionsIn,
              connectionsOut: frame.totals.connectionsOut,
              count: connections.activeCount,
            );
            isStreaming.value = true;
          },
          onError: (Object e) {
            unawaited(previousSub?.cancel());
            previousSub = null;
            _scheduleRetry(_RetryKind.connections, controller, epoch, e);
          },
          cancelOnError: true,
        );
  }

  void _subscribeLogs({StreamSubscription<rust.LogsFrame>? previous}) {
    final t = _target;
    if (t == null) return;
    final controller = _activeKey;
    final epoch = _nextStreamEpoch(_RetryKind.logs);
    var receivedFrame = false;
    var previousSub = previous;
    _logsSub = rust
        .controllerLogsStream(target: t, infoCapacity: _logInfoCapacity)
        .listen(
          (frame) {
            if (!_isCurrentStream(_RetryKind.logs, controller, epoch)) return;
            if (!receivedFrame) {
              receivedFrame = true;
              unawaited(previousSub?.cancel());
              previousSub = null;
            }
            _markStreamHealthy(_RetryKind.logs);
            logs.applyFrame(frame);
          },
          onError: (Object e) {
            unawaited(previousSub?.cancel());
            previousSub = null;
            _scheduleRetry(_RetryKind.logs, controller, epoch, e);
          },
          cancelOnError: true,
        );
  }

  /// Clear the Rust cache and the currently rendered window.
  Future<void> clearLogs() async {
    final t = _target;
    logs.clearLocal();
    if (t == null) return;
    await rust.controllerClearLogs(target: t);
  }

  void _scheduleRetry(
    _RetryKind kind,
    Controller? controller,
    int epoch,
    Object cause,
  ) {
    if (!_isCurrentStream(kind, controller, epoch)) return;
    _clearSubscription(kind);
    _showError(_formatError(cause), _ViewErrorSource.stream);
    final delay = _nextRetryDelay(kind);
    switch (kind) {
      case _RetryKind.traffic:
        _trafficRetry?.cancel();
        _trafficRetry = Timer(delay, () {
          _trafficRetry = null;
          if (_isCurrentStream(kind, controller, epoch)) _subscribeTraffic();
        });
      case _RetryKind.memory:
        _memoryRetry?.cancel();
        _memoryRetry = Timer(delay, () {
          _memoryRetry = null;
          if (_isCurrentStream(kind, controller, epoch) &&
              supportsMemory.value) {
            _subscribeMemory();
          }
        });
      case _RetryKind.connections:
        _connRetry?.cancel();
        _connRetry = Timer(delay, () {
          _connRetry = null;
          if (_isCurrentStream(kind, controller, epoch)) {
            _subscribeConnections();
          }
        });
      case _RetryKind.logs:
        _logsRetry?.cancel();
        _logsRetry = Timer(delay, () {
          _logsRetry = null;
          if (_isCurrentStream(kind, controller, epoch)) _subscribeLogs();
        });
    }
  }

  void _showError(String message, _ViewErrorSource source) {
    _errorSource = source;
    error.value = message;
  }

  void _clearError([_ViewErrorSource? source]) {
    if (source != null && _errorSource != source) return;
    _errorSource = null;
    if (error.value != null) error.value = null;
  }

  void _markStreamHealthy(_RetryKind kind) {
    _retryAttempts.remove(kind);
    _clearError(_ViewErrorSource.stream);
  }

  Duration _nextRetryDelay(_RetryKind kind) {
    final attempt = _retryAttempts[kind] ?? 0;
    _retryAttempts[kind] = attempt + 1;
    final index = attempt >= _retryDelays.length
        ? _retryDelays.length - 1
        : attempt;
    return _retryDelays[index];
  }

  int _nextStreamEpoch(_RetryKind kind) {
    return switch (kind) {
      _RetryKind.traffic => ++_trafficEpoch,
      _RetryKind.memory => ++_memoryEpoch,
      _RetryKind.connections => ++_connectionsEpoch,
      _RetryKind.logs => ++_logsEpoch,
    };
  }

  bool _isCurrentStream(_RetryKind kind, Controller? controller, int epoch) {
    if (!identical(_activeKey, controller)) return false;
    return switch (kind) {
      _RetryKind.traffic => _trafficEpoch == epoch,
      _RetryKind.memory => _memoryEpoch == epoch,
      _RetryKind.connections => _connectionsEpoch == epoch,
      _RetryKind.logs => _logsEpoch == epoch,
    };
  }

  void _invalidateAllStreams() {
    _trafficEpoch++;
    _memoryEpoch++;
    _connectionsEpoch++;
    _logsEpoch++;
  }

  void _clearSubscription(_RetryKind kind) {
    switch (kind) {
      case _RetryKind.traffic:
        _trafficSub = null;
      case _RetryKind.memory:
        _memorySub = null;
      case _RetryKind.connections:
        _connSub = null;
      case _RetryKind.logs:
        _logsSub = null;
    }
  }

  void dispose() {
    _iconWarmGeneration++;
    store.removeListener(_onStoreChange);
    _stopTargetStreams(_target);
    _cancelAll();
    traffic.dispose();
    memory.dispose();
    connectionsTotals.dispose();
    connections.dispose();
    logs.dispose();
    processIcons.dispose();
    versionString.dispose();
    isCmfa.dispose();
    isStash.dispose();
    supportsCoreConfig.dispose();
    supportsCoreActions.dispose();
    supportsCoreManagement.dispose();
    supportsCacheFlush.dispose();
    supportsDnsFlush.dispose();
    supportsMemory.dispose();
    supportsExternalResources.dispose();
    supportsRules.dispose();
    supportsTailscale.dispose();
    supportsDiagnostics.dispose();
    ruleCount.dispose();
    connectionsPaused.dispose();
    error.dispose();
    isStreaming.dispose();
  }

  String _formatError(Object error) =>
      formatError(error, backendName: _activeKey?.name);
}

enum _RetryKind { traffic, memory, connections, logs }

enum _ViewErrorSource { controller, proxyCatalog, proxyMember, stream }

/// Streaming samples represent time even when their values are unchanged.
/// ValueNotifier normally suppresses equal values, which would collapse flat
/// sections of the 1 Hz dashboard history into a single point.
class _TelemetryValueNotifier<T> extends ValueNotifier<T> {
  _TelemetryValueNotifier(super.value);

  @override
  set value(T newValue) {
    if (value == newValue) {
      notifyListeners();
      return;
    }
    super.value = newValue;
  }
}

class _QueuedProxyMemberLoad {
  const _QueuedProxyMemberLoad({
    required this.target,
    required this.group,
    required this.firstIndex,
    required this.lastIndex,
    required this.sort,
    required this.groupByProvider,
    required this.locateCurrent,
  });

  final rust.BackendTarget target;
  final String group;
  final int firstIndex;
  final int lastIndex;
  final rust.ProxyMemberSort sort;
  final bool groupByProvider;
  final bool locateCurrent;
}
