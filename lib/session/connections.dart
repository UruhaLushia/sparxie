import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

class ConnectionsTotals {
  ConnectionsTotals({
    required this.upload,
    required this.download,
    required this.memory,
    required this.count,
  });
  final BigInt upload;
  final BigInt download;
  final BigInt memory;
  final int count;

  static final ConnectionsTotals zero = ConnectionsTotals(
    upload: BigInt.zero,
    download: BigInt.zero,
    memory: BigInt.zero,
    count: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is ConnectionsTotals &&
      upload == other.upload &&
      download == other.download &&
      memory == other.memory &&
      count == other.count;

  @override
  int get hashCode => Object.hash(upload, download, memory, count);
}

/// Bytes pair for one connection.
class RowBytes {
  const RowBytes(this.upload, this.download);
  final BigInt upload;
  final BigInt download;

  static final RowBytes zero = RowBytes(BigInt.zero, BigInt.zero);

  @override
  bool operator ==(Object other) =>
      other is RowBytes &&
      upload == other.upload &&
      download == other.download;

  @override
  int get hashCode => Object.hash(upload, download);
}

/// Per-second up/down rate pair.
class RowSpeeds {
  const RowSpeeds(this.upload, this.download);
  final BigInt upload;
  final BigInt download;

  static final RowSpeeds zero = RowSpeeds(BigInt.zero, BigInt.zero);

  @override
  bool operator ==(Object other) =>
      other is RowSpeeds &&
      upload == other.upload &&
      download == other.download;

  @override
  int get hashCode => Object.hash(upload, download);
}

/// Stable header info for one connection. Bytes/speeds flow through
/// per-row notifiers so tile chrome doesn't repaint when only counters move.
class ConnectionRow {
  ConnectionRow({
    required this.id,
    required this.host,
    required this.network,
    required this.connType,
    required this.process,
    required this.processPath,
    required this.rule,
    required this.rulePayload,
    required this.chains,
    required this.start,
    required this.sourceIp,
    required this.sourcePort,
    required this.destinationIp,
    required this.destinationPort,
    required this.inboundIp,
    required this.inboundPort,
    required this.inboundName,
    required this.dnsMode,
    required this.uid,
    required this.specialProxy,
    required this.specialRules,
    required this.remoteDestination,
    required this.sniffHost,
    required this.isClosed,
    required RowBytes initialBytes,
    required RowSpeeds initialSpeeds,
  })  : bytes = ValueNotifier<RowBytes>(initialBytes),
        speeds = ValueNotifier<RowSpeeds>(initialSpeeds);

  final String id;
  final String host;
  final String network;
  final String connType;
  final String process;
  final String processPath;
  final String rule;
  final String rulePayload;
  final List<String> chains;
  final DateTime? start;
  final String sourceIp;
  final int sourcePort;
  final String destinationIp;
  final int destinationPort;
  final String inboundIp;
  final int inboundPort;
  final String inboundName;
  final String dnsMode;
  final int uid;
  final String specialProxy;
  final String specialRules;
  final String remoteDestination;
  final String sniffHost;
  final bool isClosed;

  /// Volatile counters; ConnectionTile listens to these directly so
  /// the rest of the row chrome doesn't repaint each tick.
  final ValueNotifier<RowBytes> bytes;
  final ValueNotifier<RowSpeeds> speeds;

  String get activeProxy => chains.isEmpty ? '' : chains.first;
  String get chainsLabel => chains.reversed.join(' → ');

  String get protocolLabel {
    if (connType.isEmpty && network.isEmpty) return '';
    if (connType.isEmpty) return network.toUpperCase();
    if (network.isEmpty) return connType;
    return '$connType(${network.toUpperCase()})';
  }

  bool matches(String needle) {
    final n = needle.toLowerCase();
    if (host.toLowerCase().contains(n)) return true;
    if (chainsLabel.toLowerCase().contains(n)) return true;
    if (rule.toLowerCase().contains(n)) return true;
    if (network.toLowerCase().contains(n)) return true;
    if (process.toLowerCase().contains(n)) return true;
    if (processPath.toLowerCase().contains(n)) return true;
    return false;
  }

  factory ConnectionRow.fromConnection(rust.Connection c) {
    final fallbackHost = c.host.isNotEmpty
        ? c.host
        : '${c.destinationIp}:${c.destinationPort}';
    return ConnectionRow(
      id: c.id,
      host: fallbackHost,
      network: c.network,
      connType: c.connType,
      process: c.process,
      processPath: c.processPath,
      rule: c.rule,
      rulePayload: c.rulePayload,
      chains: List<String>.unmodifiable(c.chains),
      start: DateTime.tryParse(c.start),
      sourceIp: c.sourceIp,
      sourcePort: c.sourcePort,
      destinationIp: c.destinationIp,
      destinationPort: c.destinationPort,
      inboundIp: c.inboundIp,
      inboundPort: c.inboundPort,
      inboundName: c.inboundName,
      dnsMode: c.dnsMode,
      uid: c.uid,
      specialProxy: c.specialProxy,
      specialRules: c.specialRules,
      remoteDestination: c.remoteDestination,
      sniffHost: c.sniffHost,
      isClosed: c.isClosed,
      initialBytes: RowBytes(c.upload, c.download),
      initialSpeeds: RowSpeeds(c.uploadSpeed, c.downloadSpeed),
    );
  }
}

enum ConnectionsTab { active, closed }

typedef WindowFetcher = Future<List<rust.Connection>> Function(
  ConnectionsTab tab,
  int offset,
  int limit,
);

/// Virtual paging: Rust holds the full sorted list, Dart only ever holds a
/// sliding window of `_windowSize` rows around the visible viewport.
///
/// The screen calls [ensureWindow] with the index it's currently scrolling
/// near; the notifier centers a new window on it (clamped to bounds) and
/// pulls fresh row data from Rust. Per-row volatile counters are patched
/// in place so individual tiles repaint without rebuilding the list.
class ConnectionListNotifier extends ChangeNotifier {
  ConnectionListNotifier({this.windowFetcher});

  WindowFetcher? windowFetcher;

  /// Visible viewport accommodates ~12 rows; we keep ~120 around it so
  /// short scrolls don't trigger fetches.
  static const int _windowSize = 120;

  /// Re-center when the user has scrolled to within this many rows of
  /// either edge of the current window.
  static const int _edgeMargin = 30;

  static const Duration _refetchDebounce = Duration(milliseconds: 50);

  // Active window state.
  int _activeOffset = 0;
  // ordered ids in the active window
  final List<String> _activeWindowIds = <String>[];
  // id → row, keyed within the window so we can patch volatile counters
  // without rebuilding ConnectionRow objects.
  final LinkedHashMap<String, ConnectionRow> _activeRows =
      LinkedHashMap<String, ConnectionRow>();

  int _closedOffset = 0;
  final List<String> _closedWindowIds = <String>[];
  final LinkedHashMap<String, ConnectionRow> _closedRows =
      LinkedHashMap<String, ConnectionRow>();

  int _activeCount = 0;
  int _closedCount = 0;

  Timer? _refetchTimer;

  int get activeCount => _activeCount;
  int get closedCount => _closedCount;
  int get windowSize => _windowSize;

  int activeWindowOffset() => _activeOffset;
  int closedWindowOffset() => _closedOffset;

  /// Returns the row at `index` within the full list, if it falls inside
  /// the current cached window. Outside the window → null (the screen
  /// renders an empty slot).
  ConnectionRow? rowAt(ConnectionsTab tab, int index) {
    final offset = tab == ConnectionsTab.active ? _activeOffset : _closedOffset;
    final ids = tab == ConnectionsTab.active
        ? _activeWindowIds
        : _closedWindowIds;
    final rows = tab == ConnectionsTab.active ? _activeRows : _closedRows;
    final local = index - offset;
    if (local < 0 || local >= ids.length) return null;
    return rows[ids[local]];
  }

  /// Apply a stream frame (counts only — no row data here).
  void applyFrame(rust.ConnectionsFrame frame) {
    if (frame.isInitial) {
      _activeWindowIds.clear();
      _activeRows.clear();
      _activeOffset = 0;
      _closedWindowIds.clear();
      _closedRows.clear();
      _closedOffset = 0;
    }
    final shapeChanged = _activeCount != frame.activeCount ||
        _closedCount != frame.closedCount ||
        frame.isInitial;
    _activeCount = frame.activeCount;
    _closedCount = frame.closedCount;
    // Re-pull the current window so volatile counters and any row that
    // entered/exited within the current viewport stay fresh.
    _scheduleRefetch();
    if (shapeChanged) notifyListeners();
  }

  /// Ensure the window covers index `centerIndex`. If the index is too
  /// close to the window edges (or outside it), shift the window so the
  /// index is centered, clamped to the list bounds, and fetch.
  void ensureWindow(ConnectionsTab tab, int centerIndex) {
    final total =
        tab == ConnectionsTab.active ? _activeCount : _closedCount;
    if (total == 0) return;
    final offset =
        tab == ConnectionsTab.active ? _activeOffset : _closedOffset;
    final localCenter = centerIndex - offset;
    final near = localCenter < _edgeMargin ||
        localCenter > _windowSize - _edgeMargin;
    if (!near) return;
    final desiredOffset =
        (centerIndex - _windowSize ~/ 2).clamp(0, (total - _windowSize).clamp(0, total));
    if (desiredOffset == offset) return;
    if (tab == ConnectionsTab.active) {
      _activeOffset = desiredOffset;
    } else {
      _closedOffset = desiredOffset;
    }
    _scheduleRefetch(force: true);
  }

  void _scheduleRefetch({bool force = false}) {
    _refetchTimer?.cancel();
    _refetchTimer = Timer(_refetchDebounce, () => _refetch(force: force));
  }

  Future<void> _refetch({required bool force}) async {
    final fetcher = windowFetcher;
    if (fetcher == null) return;
    await Future.wait([
      _refetchTab(ConnectionsTab.active, fetcher, force: force),
      _refetchTab(ConnectionsTab.closed, fetcher, force: force),
    ]);
  }

  Future<void> _refetchTab(
    ConnectionsTab tab,
    WindowFetcher fetcher, {
    required bool force,
  }) async {
    final total =
        tab == ConnectionsTab.active ? _activeCount : _closedCount;
    if (total == 0) return;
    final offset =
        tab == ConnectionsTab.active ? _activeOffset : _closedOffset;
    final ids = tab == ConnectionsTab.active
        ? _activeWindowIds
        : _closedWindowIds;
    if (!force && ids.isEmpty) {
      // First-time load is treated as forced.
    }
    try {
      final rows = await fetcher(tab, offset, _windowSize);
      _applyWindow(tab, offset, rows);
    } catch (_) {
      // Silent — next frame retriggers.
    }
  }

  void _applyWindow(
    ConnectionsTab tab,
    int expectedOffset,
    List<rust.Connection> rows,
  ) {
    // Stale response from a window that's since shifted? Drop it.
    final currentOffset =
        tab == ConnectionsTab.active ? _activeOffset : _closedOffset;
    if (expectedOffset != currentOffset) return;

    final ids = tab == ConnectionsTab.active
        ? _activeWindowIds
        : _closedWindowIds;
    final rowMap = tab == ConnectionsTab.active ? _activeRows : _closedRows;

    final newIds = rows.map((c) => c.id).toList(growable: false);
    final newIdSet = newIds.toSet();
    final orderChanged = !_listEq(ids, newIds);

    // Patch existing rows in place (volatile counters), and insert
    // brand-new ones.
    for (final c in rows) {
      final existing = rowMap[c.id];
      if (existing != null) {
        final bytes = RowBytes(c.upload, c.download);
        if (existing.bytes.value != bytes) existing.bytes.value = bytes;
        final speeds = RowSpeeds(c.uploadSpeed, c.downloadSpeed);
        if (existing.speeds.value != speeds) existing.speeds.value = speeds;
      } else {
        rowMap[c.id] = ConnectionRow.fromConnection(c);
      }
    }
    // Drop rows that left the window.
    rowMap.removeWhere((id, _) => !newIdSet.contains(id));

    if (orderChanged) {
      ids
        ..clear()
        ..addAll(newIds);
      notifyListeners();
    }
  }

  /// Hide a row before the upstream confirms the close. The next stream
  /// frame plus refetch will rebuild authoritative state.
  void optimisticRemove(String id) {
    var changed = false;
    if (_activeRows.remove(id) != null) {
      _activeWindowIds.remove(id);
      if (_activeCount > 0) _activeCount--;
      changed = true;
    }
    if (_closedRows.remove(id) != null) {
      _closedWindowIds.remove(id);
      if (_closedCount > 0) _closedCount--;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void reset() {
    _activeWindowIds.clear();
    _activeRows.clear();
    _activeOffset = 0;
    _closedWindowIds.clear();
    _closedRows.clear();
    _closedOffset = 0;
    _activeCount = 0;
    _closedCount = 0;
    _refetchTimer?.cancel();
    notifyListeners();
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _refetchTimer?.cancel();
    for (final row in _activeRows.values) {
      row.bytes.dispose();
      row.speeds.dispose();
    }
    for (final row in _closedRows.values) {
      row.bytes.dispose();
      row.speeds.dispose();
    }
    _activeRows.clear();
    _closedRows.clear();
    super.dispose();
  }
}
