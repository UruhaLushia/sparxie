import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'controller.dart';
import 'error_format.dart';
import 'rust_api.dart' as rust;
import 'session/connections.dart';
import 'session/proxies.dart';

export 'session/connections.dart';
export 'session/proxies.dart';

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
  Timer? _trafficRetry;
  Timer? _memoryRetry;
  Timer? _connRetry;
  Timer? _proxiesPoll;
  bool _proxiesRefreshing = false;

  int _connectionsIntervalMs = 1000;
  int _proxiesIntervalMs = 3000;

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

  final ValueNotifier<ConnectionsTotals> connectionsTotals =
      ValueNotifier(ConnectionsTotals.zero);

  final ProxiesNotifier proxies = ProxiesNotifier();

  /// Raw `version` field from `/version`. Empty until first poll succeeds.
  final ValueNotifier<String> versionString = ValueNotifier('');

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

  Future<void> refreshProxies() => _refreshProxies();

  void _onStoreChange() {
    final next = store.active;
    if (identical(next, _activeKey)) return;
    _activeKey = next;
    _target = next == null
        ? null
        : rust.MihomoTarget(
            baseUrl: next.baseUrl,
            secret: next.secret.isEmpty ? null : next.secret,
          );
    _resubscribeAll();
  }

  void _resubscribeAll() {
    _cancelAll();
    isStreaming.value = false;
    connections.reset();
    connectionsTotals.value = ConnectionsTotals.zero;
    proxies.reset();
    versionString.value = '';
    isCmfa.value = false;
    connectionsPaused.value = false;
    if (_target == null) {
      error.value = '请先在“后端”中添加一个 mihomo 实例';
      return;
    }
    error.value = null;
    _subscribeTraffic();
    _subscribeMemory();
    _subscribeConnections();
    _startProxiesPoll();
    // Version is build-time fixed; one probe per controller switch is enough.
    unawaited(_probeVersion());
  }

  void _cancelAll() {
    _trafficSub?.cancel();
    _memorySub?.cancel();
    _connSub?.cancel();
    _trafficRetry?.cancel();
    _memoryRetry?.cancel();
    _connRetry?.cancel();
    _proxiesPoll?.cancel();
    _trafficSub = null;
    _memorySub = null;
    _connSub = null;
    _trafficRetry = null;
    _memoryRetry = null;
    _connRetry = null;
    _proxiesPoll = null;
  }

  void _restartConnections() {
    _connSub?.cancel();
    _connRetry?.cancel();
    connections.reset();
    if (_target != null) _subscribeConnections();
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
      final raw = await rust.version(target: t);
      if (!identical(_activeKey, controller)) return;
      String version = '';
      try {
        final json = jsonDecode(raw);
        if (json is Map && json['version'] is String) {
          version = json['version'] as String;
        }
      } catch (_) {}
      versionString.value = version;
      isCmfa.value = version.toLowerCase().contains('cmfa');
    } catch (_) {
      // Non-critical; absent version just means CMFA features default to false.
    }
  }

  Future<void> _refreshProxies() async {
    final t = _target;
    final controller = _activeKey;
    if (t == null || _proxiesRefreshing) return;
    _proxiesRefreshing = true;
    try {
      final raw = await rust.proxies(target: t, groupsOnly: false);
      if (!identical(_activeKey, controller)) return;
      proxies.apply(raw);
    } catch (e) {
      if (identical(_activeKey, controller)) error.value = formatError(e);
    } finally {
      _proxiesRefreshing = false;
    }
  }

  void _subscribeTraffic() {
    final t = _target;
    if (t == null) return;
    _trafficSub = rust.trafficStream(target: t).listen(
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
    _memorySub = rust.memoryStream(target: t).listen(
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
    }
  }

  void dispose() {
    store.removeListener(_onStoreChange);
    _cancelAll();
    traffic.dispose();
    memory.dispose();
    connectionsTotals.dispose();
    connections.dispose();
    versionString.dispose();
    isCmfa.dispose();
    connectionsPaused.dispose();
    error.dispose();
    isStreaming.dispose();
  }
}

enum _RetryKind { traffic, memory, connections }
