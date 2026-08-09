import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

part 'connections/models.dart';

typedef WindowFetcher =
    Future<rust.ConnectionWindow> Function(
      ConnectionsTab tab,
      int offset,
      int limit,
      String query,
    );

typedef GroupsFetcher =
    Future<List<rust.ConnectionGroup>> Function(
      ConnectionsTab tab,
      rust.ConnectionGroupSort sort,
      bool asc,
      String query,
    );

typedef GroupMembersFetcher =
    Future<List<rust.Connection>> Function(
      ConnectionsTab tab,
      String groupKey,
      int limit,
      String query,
    );

/// Virtual paging: Rust holds the full sorted list, Dart only ever holds the
/// visible rows plus a small overscan around the viewport.
///
/// The screen calls [ensureWindow] with its visible index range; the notifier
/// pulls that range plus overscan from Rust. Per-row volatile counters are
/// patched in place so individual tiles repaint without rebuilding the list.
class ConnectionListNotifier extends ChangeNotifier {
  ConnectionListNotifier({
    this.windowFetcher,
    this.groupsFetcher,
    this.groupMembersFetcher,
  });

  WindowFetcher? windowFetcher;
  GroupsFetcher? groupsFetcher;
  GroupMembersFetcher? groupMembersFetcher;

  /// Cap on member rows held per expanded group. An expanded group shows its
  /// top-N by the current sort key; the header still reflects the true total.
  static const int _groupMemberCap = 100;

  /// Keep only five rows above and below the actual viewport in Dart memory.
  static const int _windowOverscan = 5;
  static const int _windowRefetchMargin = _windowOverscan;

  static const Duration _refetchDebounce = Duration(milliseconds: 50);
  static const Duration _rowRetireDelay = Duration(milliseconds: 250);

  // Active window state.
  int _activeOffset = 0;
  int _activeLimit = 0;
  // ordered ids in the active window
  final List<String> _activeWindowIds = <String>[];
  // id → row, keyed within the window so we can patch volatile counters
  // without rebuilding ConnectionRow objects.
  final LinkedHashMap<String, ConnectionRow> _activeRows =
      LinkedHashMap<String, ConnectionRow>();

  int _closedOffset = 0;
  int _closedLimit = 0;
  final List<String> _closedWindowIds = <String>[];
  final LinkedHashMap<String, ConnectionRow> _closedRows =
      LinkedHashMap<String, ConnectionRow>();

  int _activeCount = 0;
  int _closedCount = 0;
  String _query = '';
  int _filteredCount = 0;
  bool _filterLoading = false;
  int _filterRevision = 0;

  ConnectionsTab _visibleTab = ConnectionsTab.active;
  Timer? _refetchTimer;
  bool _refetching = false;
  bool _refetchAgain = false;
  bool _pendingRefetchForce = false;
  int _activityGeneration = 0;

  // Grouped (by-process) mode state.
  bool _grouped = false;
  rust.ConnectionGroupSort _groupSort = rust.ConnectionGroupSort.name;
  bool _groupSortAsc = true;
  final List<ConnectionGroupSummary> _groups = <ConnectionGroupSummary>[];
  late final List<ConnectionGroupSummary> groups = UnmodifiableListView(
    _groups,
  );
  final Map<String, ConnectionGroupSummary> _groupsByKey =
      <String, ConnectionGroupSummary>{};
  final Set<String> _expandedGroups = <String>{};
  // Per-expanded-group ordered member ids + row cache.
  final Map<String, List<String>> _groupMemberIds = <String, List<String>>{};
  final Map<String, LinkedHashMap<String, ConnectionRow>> _groupMemberRows =
      <String, LinkedHashMap<String, ConnectionRow>>{};
  Timer? _groupsTimer;
  int _groupsRevision = 0;
  bool _refreshingGroups = false;
  bool _refreshGroupsAgain = false;
  bool _pendingGroupsForce = false;
  final Set<String> _fetchingGroupMembers = <String>{};
  final Set<String> _queuedGroupMembers = <String>{};

  @override
  void removeListener(VoidCallback listener) {
    final hadListeners = hasListeners;
    super.removeListener(listener);
    if (!hadListeners || hasListeners) return;
    _activityGeneration++;
    _refetchTimer?.cancel();
    _refetchTimer = null;
    _groupsTimer?.cancel();
    _groupsTimer = null;
    _pendingRefetchForce = false;
    _pendingGroupsForce = false;
    _refetchAgain = false;
    _refreshGroupsAgain = false;
    _queuedGroupMembers.clear();
  }

  bool get grouped => _grouped;

  set grouped(bool value) {
    if (value == _grouped) return;
    _grouped = value;
    if (value) {
      _scheduleGroupsRefresh(force: true);
    } else {
      _disposeGroups();
      if (hasFilter) _prepareInitialWindow();
    }
    notifyListeners();
  }

  void setVisibleTab(ConnectionsTab tab) {
    if (tab == _visibleTab) return;
    _visibleTab = tab;
    if (hasFilter) {
      _filterRevision++;
      _filteredCount = 0;
      _filterLoading = true;
      _clearWindow(tab);
    }
    if (_grouped) {
      _disposeGroups();
      _scheduleGroupsRefresh(force: true);
    } else {
      _prepareInitialWindow();
    }
    notifyListeners();
  }

  /// Set the group ordering. A change forces an immediate re-sort.
  void setGroupSort(rust.ConnectionGroupSort sort, bool asc) {
    if (sort == _groupSort && asc == _groupSortAsc) return;
    _groupSort = sort;
    _groupSortAsc = asc;
    _groupsRevision++;
    if (_grouped) _scheduleGroupsRefresh(force: true);
  }

  bool isExpanded(String groupKey) => _expandedGroups.contains(groupKey);

  void toggleGroup(String groupKey) {
    if (!_expandedGroups.remove(groupKey)) {
      _expandedGroups.add(groupKey);
      _refetchGroupMembers(groupKey);
    }
    notifyListeners();
  }

  /// Ordered member ids of an expanded group (empty until first fetch).
  List<String> groupMemberIds(String groupKey) =>
      _groupMemberIds[groupKey] ?? const <String>[];

  ConnectionRow? groupMemberAt(String groupKey, int index) {
    final ids = _groupMemberIds[groupKey];
    if (ids == null || index < 0 || index >= ids.length) return null;
    return _groupMemberRows[groupKey]?[ids[index]];
  }

  int get activeCount => _activeCount;
  int get closedCount => _closedCount;
  bool get hasFilter => _query.isNotEmpty;
  bool get filterLoading => _filterLoading;
  ConnectionsTab get visibleTab => _visibleTab;
  int visibleCount(ConnectionsTab tab) => hasFilter && tab == _visibleTab
      ? _filteredCount
      : tab == ConnectionsTab.active
      ? _activeCount
      : _closedCount;
  int get windowOverscan => _windowOverscan;

  int activeWindowOffset() => _activeOffset;
  int closedWindowOffset() => _closedOffset;

  void setFilter(String value) {
    final query = value.trim().toLowerCase();
    if (query == _query) return;
    _query = query;
    _filterRevision++;
    _filteredCount = 0;
    _filterLoading = query.isNotEmpty;
    _clearWindow(_visibleTab);
    if (_grouped) _disposeGroups();
    if (_grouped) {
      _scheduleGroupsRefresh(force: true);
    } else {
      _prepareInitialWindow();
    }
    notifyListeners();
  }

  void _prepareInitialWindow() {
    if (_visibleTab == ConnectionsTab.active) {
      _activeOffset = 0;
      _activeLimit = 30;
    } else {
      _closedOffset = 0;
      _closedLimit = 30;
    }
    _scheduleRefetch(force: true);
  }

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
    // A stream restart on foreground resume still targets the same backend.
    // Keep the painted window until the forced refresh below replaces it, so
    // resume does not tear down and rebuild the visible list twice. Controller
    // changes and preference-driven restarts already call reset explicitly.
    final shapeChanged =
        _activeCount != frame.activeCount ||
        _closedCount != frame.closedCount ||
        frame.isInitial;
    _activeCount = frame.activeCount;
    _closedCount = frame.closedCount;
    if (_activeCount == 0) _clearWindow(ConnectionsTab.active);
    if (_closedCount == 0) _clearWindow(ConnectionsTab.closed);
    if (hasListeners) {
      // Re-pull only the current view; inactive tabs will fetch on switch.
      if (_grouped) {
        _scheduleGroupsRefresh(force: frame.isInitial);
      } else {
        _scheduleRefetch();
      }
      if (shapeChanged) notifyListeners();
    }
  }

  /// Ensure the cached rows cover `[firstIndex, lastIndex]`, plus overscan.
  void ensureWindow(ConnectionsTab tab, int firstIndex, int lastIndex) {
    _visibleTab = tab;
    if (hasFilter && _filterLoading) return;
    final total = visibleCount(tab);
    if (total == 0) {
      _clearWindow(tab);
      return;
    }
    final safeFirst = firstIndex.clamp(0, total - 1).toInt();
    final safeLast = lastIndex.clamp(safeFirst, total - 1).toInt();
    final desiredOffset = (safeFirst - _windowOverscan).clamp(0, total).toInt();
    final end = (safeLast + 1 + _windowOverscan).clamp(0, total).toInt();
    final desiredLimit = end - desiredOffset;
    final offset = tab == ConnectionsTab.active ? _activeOffset : _closedOffset;
    final limit = tab == ConnectionsTab.active ? _activeLimit : _closedLimit;
    final ids = tab == ConnectionsTab.active
        ? _activeWindowIds
        : _closedWindowIds;
    final cachedEnd = offset + limit;
    final covered =
        ids.isNotEmpty &&
        safeFirst >= offset + _windowRefetchMargin &&
        safeLast < cachedEnd - _windowRefetchMargin;
    if (covered ||
        (desiredOffset == offset && desiredLimit == limit && ids.isNotEmpty)) {
      return;
    }
    if (tab == ConnectionsTab.active) {
      _activeOffset = desiredOffset;
      _activeLimit = desiredLimit;
    } else {
      _closedOffset = desiredOffset;
      _closedLimit = desiredLimit;
    }
    _scheduleRefetch(force: true);
  }

  /// Refresh the retained visible view after its page becomes active again.
  void refreshVisible() {
    if (_grouped) {
      _scheduleGroupsRefresh(force: true);
    } else {
      _scheduleRefetch(force: true);
    }
  }

  void _scheduleRefetch({bool force = false}) {
    _pendingRefetchForce |= force;
    if (_refetching) {
      _refetchAgain = true;
      return;
    }
    if (force) {
      _refetchTimer?.cancel();
      _refetchTimer = null;
      final force = _pendingRefetchForce;
      _pendingRefetchForce = false;
      unawaited(_runRefetch(force: force));
      return;
    }
    _refetchTimer?.cancel();
    _refetchTimer = Timer(_refetchDebounce, () {
      _refetchTimer = null;
      final force = _pendingRefetchForce;
      _pendingRefetchForce = false;
      unawaited(_runRefetch(force: force));
    });
  }

  void _scheduleGroupsRefresh({bool force = false}) {
    _pendingGroupsForce |= force;
    if (_refreshingGroups) {
      _refreshGroupsAgain = true;
      return;
    }
    if (force) {
      _groupsTimer?.cancel();
      _groupsTimer = null;
      final force = _pendingGroupsForce;
      _pendingGroupsForce = false;
      unawaited(_runGroupsRefresh(force: force));
      return;
    }
    _groupsTimer?.cancel();
    _groupsTimer = Timer(_refetchDebounce, () {
      _groupsTimer = null;
      final force = _pendingGroupsForce;
      _pendingGroupsForce = false;
      unawaited(_runGroupsRefresh(force: force));
    });
  }

  Future<void> _runRefetch({required bool force}) async {
    if (_refetching) {
      _pendingRefetchForce |= force;
      _refetchAgain = true;
      return;
    }
    _refetching = true;
    final activityGeneration = _activityGeneration;
    try {
      await _refetch(force: force);
    } finally {
      _refetching = false;
      if (activityGeneration != _activityGeneration) {
        final refreshAgain = _refetchAgain;
        final pendingForce = _pendingRefetchForce;
        _refetchAgain = false;
        _pendingRefetchForce = false;
        if (refreshAgain) {
          if (pendingForce) {
            unawaited(_runRefetch(force: true));
          } else {
            _scheduleRefetch();
          }
        }
      } else if (_refetchAgain) {
        _refetchAgain = false;
        final force = _pendingRefetchForce;
        _pendingRefetchForce = false;
        if (force) {
          unawaited(_runRefetch(force: force));
        } else {
          _scheduleRefetch();
        }
      }
    }
  }

  Future<void> _runGroupsRefresh({required bool force}) async {
    if (_refreshingGroups) {
      _pendingGroupsForce |= force;
      _refreshGroupsAgain = true;
      return;
    }
    _refreshingGroups = true;
    final activityGeneration = _activityGeneration;
    try {
      await _refreshGroups(force: force);
    } finally {
      _refreshingGroups = false;
      if (activityGeneration != _activityGeneration) {
        final refreshAgain = _refreshGroupsAgain;
        final pendingForce = _pendingGroupsForce;
        _refreshGroupsAgain = false;
        _pendingGroupsForce = false;
        if (refreshAgain) {
          _scheduleGroupsRefresh(force: pendingForce);
        }
      } else if (_refreshGroupsAgain) {
        _refreshGroupsAgain = false;
        final force = _pendingGroupsForce;
        _pendingGroupsForce = false;
        _scheduleGroupsRefresh(force: force);
      }
    }
  }

  Future<void> _refreshGroups({required bool force}) async {
    final fetcher = groupsFetcher;
    if (fetcher == null || !_grouped) return;
    final tab = _visibleTab;
    final revision = _groupsRevision;
    final filterRevision = _filterRevision;
    final activityGeneration = _activityGeneration;
    final query = _query;
    final List<rust.ConnectionGroup> fresh;
    try {
      fresh = await fetcher(tab, _groupSort, _groupSortAsc, query);
    } catch (_) {
      return;
    }
    if (!_grouped ||
        activityGeneration != _activityGeneration ||
        tab != _visibleTab ||
        revision != _groupsRevision ||
        filterRevision != _filterRevision) {
      return;
    }
    final wasLoading = _filterLoading;
    if (query.isNotEmpty) _filterLoading = false;
    _applyGroups(fresh, force: force);
    for (final key in _expandedGroups.toList()) {
      _refetchGroupMembers(key);
    }
    if (wasLoading && !_filterLoading) notifyListeners();
  }

  void _applyGroups(List<rust.ConnectionGroup> fresh, {required bool force}) {
    final newKeys = fresh.map((g) => g.key).toList(growable: false);
    final oldKeys = _groups.map((g) => g.key).toList(growable: false);
    final orderChanged = force || !_listEq(oldKeys, newKeys);

    final seen = newKeys.toSet();
    for (final g in fresh) {
      final existing = _groupsByKey[g.key];
      if (existing != null) {
        if (existing.count.value != g.count) existing.count.value = g.count;
        final b = RowBytes(g.upload, g.download);
        if (existing.bytes.value != b) existing.bytes.value = b;
        final s = RowSpeeds(g.uploadSpeed, g.downloadSpeed);
        if (existing.speeds.value != s) existing.speeds.value = s;
      } else {
        _groupsByKey[g.key] = ConnectionGroupSummary.fromGroup(g);
      }
    }
    final removed = _groupsByKey.keys.where((k) => !seen.contains(k)).toList();
    for (final k in removed) {
      _groupsByKey.remove(k)?.dispose();
      _expandedGroups.remove(k);
      _disposeGroupMembers(k);
    }

    if (orderChanged) {
      _groups
        ..clear()
        ..addAll(newKeys.map((k) => _groupsByKey[k]!));
      notifyListeners();
    }
  }

  Future<void> _refetchGroupMembers(String groupKey) async {
    if (!_fetchingGroupMembers.add(groupKey)) {
      _queuedGroupMembers.add(groupKey);
      return;
    }
    try {
      await _loadGroupMembers(groupKey);
    } finally {
      _fetchingGroupMembers.remove(groupKey);
      if (_queuedGroupMembers.remove(groupKey) &&
          _expandedGroups.contains(groupKey)) {
        unawaited(_refetchGroupMembers(groupKey));
      }
    }
  }

  Future<void> _loadGroupMembers(String groupKey) async {
    final fetcher = groupMembersFetcher;
    if (fetcher == null || !_expandedGroups.contains(groupKey)) return;
    final tab = _visibleTab;
    final revision = _groupsRevision;
    final filterRevision = _filterRevision;
    final activityGeneration = _activityGeneration;
    final query = _query;
    final List<rust.Connection> rows;
    try {
      rows = await fetcher(tab, groupKey, _groupMemberCap, query);
    } catch (_) {
      return;
    }
    if (activityGeneration != _activityGeneration ||
        tab != _visibleTab ||
        revision != _groupsRevision ||
        filterRevision != _filterRevision ||
        !_expandedGroups.contains(groupKey)) {
      return;
    }

    final rowMap = _groupMemberRows.putIfAbsent(
      groupKey,
      () => LinkedHashMap<String, ConnectionRow>(),
    );
    final newIds = <String>[];
    final prev = _groupMemberIds[groupKey] ?? const <String>[];

    for (final c in rows) {
      newIds.add(c.id);
      final existing = rowMap[c.id];
      if (existing != null) {
        existing.updateFromConnection(c);
      } else {
        rowMap[c.id] = ConnectionRow.fromConnection(c);
      }
    }
    final orderChanged = !_listEq(prev, newIds);
    _retainRows(rowMap, newIds);
    _groupMemberIds[groupKey] = newIds;
    if (orderChanged) notifyListeners();
  }

  void _disposeGroupMembers(String groupKey) {
    final rows = _groupMemberRows.remove(groupKey);
    if (rows != null) {
      _retireRows(rows.values);
    }
    _groupMemberIds.remove(groupKey);
  }

  void _disposeGroups() {
    _groupsTimer?.cancel();
    _groupsRevision++;
    for (final g in _groups) {
      g.dispose();
    }
    _groups.clear();
    _groupsByKey.clear();
    _expandedGroups.clear();
    for (final key in _groupMemberRows.keys.toList()) {
      _disposeGroupMembers(key);
    }
  }

  Future<void> _refetch({required bool force}) async {
    final fetcher = windowFetcher;
    if (fetcher == null) return;
    await _refetchTab(_visibleTab, fetcher, force: force);
  }

  Future<void> _refetchTab(
    ConnectionsTab tab,
    WindowFetcher fetcher, {
    required bool force,
  }) async {
    final total = visibleCount(tab);
    if (total == 0 && !hasFilter) {
      _clearWindow(tab);
      return;
    }
    final offset = tab == ConnectionsTab.active ? _activeOffset : _closedOffset;
    final limit = tab == ConnectionsTab.active ? _activeLimit : _closedLimit;
    if (limit <= 0) return;
    final filterRevision = _filterRevision;
    final query = _query;
    final activityGeneration = _activityGeneration;
    try {
      final window = await fetcher(tab, offset, limit, query);
      if (activityGeneration != _activityGeneration) return;
      _applyWindow(tab, offset, limit, filterRevision, query, window);
    } catch (_) {
      // Silent — next frame retriggers.
    }
  }

  void _applyWindow(
    ConnectionsTab tab,
    int expectedOffset,
    int expectedLimit,
    int filterRevision,
    String query,
    rust.ConnectionWindow window,
  ) {
    // Stale response from a window that's since shifted? Drop it.
    final currentOffset = tab == ConnectionsTab.active
        ? _activeOffset
        : _closedOffset;
    final currentLimit = tab == ConnectionsTab.active
        ? _activeLimit
        : _closedLimit;
    if (expectedOffset != currentOffset ||
        expectedLimit != currentLimit ||
        filterRevision != _filterRevision ||
        query != _query) {
      return;
    }

    if (window.total > 0 && expectedOffset >= window.total) {
      final nextOffset = (window.total - expectedLimit)
          .clamp(0, window.total)
          .toInt();
      if (tab == ConnectionsTab.active) {
        _activeOffset = nextOffset;
      } else {
        _closedOffset = nextOffset;
      }
      if (query.isNotEmpty) _filteredCount = window.total;
      _scheduleRefetch(force: true);
      notifyListeners();
      return;
    }

    final ids = tab == ConnectionsTab.active
        ? _activeWindowIds
        : _closedWindowIds;
    final rowMap = tab == ConnectionsTab.active ? _activeRows : _closedRows;

    final newIds = <String>[];

    // Patch existing rows in place (volatile counters), and insert
    // brand-new ones.
    for (final c in window.rows) {
      newIds.add(c.id);
      final existing = rowMap[c.id];
      if (existing != null) {
        existing.updateFromConnection(c);
      } else {
        rowMap[c.id] = ConnectionRow.fromConnection(c);
      }
    }
    // Drop rows that left the window.
    _retainRows(rowMap, newIds);

    final orderChanged = !_listEq(ids, newIds);
    final countChanged = query.isNotEmpty && _filteredCount != window.total;
    final wasLoading = _filterLoading;
    if (query.isNotEmpty) {
      _filteredCount = window.total;
      _filterLoading = false;
    }
    if (orderChanged) {
      ids
        ..clear()
        ..addAll(newIds);
    }
    if (orderChanged || countChanged || (wasLoading && !_filterLoading)) {
      notifyListeners();
    }
  }

  /// Hide a row before the upstream confirms the close. The next stream
  /// frame plus refetch will rebuild authoritative state.
  void optimisticRemove(String id) {
    var changed = false;
    final active = _activeRows.remove(id);
    if (active != null) {
      _retireRow(active);
      _activeWindowIds.remove(id);
      if (_activeCount > 0) _activeCount--;
      if (hasFilter &&
          _visibleTab == ConnectionsTab.active &&
          _filteredCount > 0) {
        _filteredCount--;
      }
      changed = true;
    }
    final closed = _closedRows.remove(id);
    if (closed != null) {
      _retireRow(closed);
      _closedWindowIds.remove(id);
      if (_closedCount > 0) _closedCount--;
      if (hasFilter &&
          _visibleTab == ConnectionsTab.closed &&
          _filteredCount > 0) {
        _filteredCount--;
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Optimistically drop the entire closed buffer. Pair with a Rust call
  /// to `clearClosedConnections` so the next frame agrees.
  void clearClosedOptimistic() {
    if (_closedCount == 0 && _closedRows.isEmpty) return;
    _filterRevision++;
    _clearWindow(ConnectionsTab.closed);
    _closedCount = 0;
    if (_visibleTab == ConnectionsTab.closed) {
      _filteredCount = 0;
      _filterLoading = false;
    }
    if (_grouped && _visibleTab == ConnectionsTab.closed) {
      _disposeGroups();
    }
    notifyListeners();
  }

  void clearClosedGroupOptimistic(String groupKey) {
    final group = _groupsByKey.remove(groupKey);
    if (group == null) return;
    _filterRevision++;
    _groupsRevision++;
    final count = group.count.value;
    _groups.remove(group);
    group.dispose();
    _expandedGroups.remove(groupKey);
    _disposeGroupMembers(groupKey);
    _closedCount = (_closedCount - count).clamp(0, _closedCount);
    _clearWindow(ConnectionsTab.closed);
    notifyListeners();
  }

  void reset() {
    _retireRows(_activeRows.values);
    _activeWindowIds.clear();
    _activeRows.clear();
    _activeOffset = 0;
    _retireRows(_closedRows.values);
    _closedWindowIds.clear();
    _closedRows.clear();
    _closedOffset = 0;
    _activeCount = 0;
    _closedCount = 0;
    _filteredCount = 0;
    _filterLoading = hasFilter;
    _filterRevision++;
    _refetchTimer?.cancel();
    _groupsTimer?.cancel();
    _pendingRefetchForce = false;
    _pendingGroupsForce = false;
    _refetchAgain = false;
    _refreshGroupsAgain = false;
    _queuedGroupMembers.clear();
    _disposeGroups();
    if (_grouped) _scheduleGroupsRefresh(force: true);
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

  void _retainRows(
    LinkedHashMap<String, ConnectionRow> rowMap,
    List<String> keepIds,
  ) {
    final retired = <ConnectionRow>[];
    rowMap.removeWhere((id, row) {
      final remove = !keepIds.contains(id);
      if (remove) retired.add(row);
      return remove;
    });
    _retireRows(retired);
  }

  void _clearWindow(ConnectionsTab tab) {
    final ids = tab == ConnectionsTab.active
        ? _activeWindowIds
        : _closedWindowIds;
    final rows = tab == ConnectionsTab.active ? _activeRows : _closedRows;
    if (ids.isNotEmpty || rows.isNotEmpty) {
      _retireRows(rows.values);
      ids.clear();
      rows.clear();
    }
    if (tab == ConnectionsTab.active) {
      _activeOffset = 0;
      _activeLimit = 0;
    } else {
      _closedOffset = 0;
      _closedLimit = 0;
    }
  }

  void _retireRows(Iterable<ConnectionRow> rows) {
    for (final row in rows.toList(growable: false)) {
      _retireRow(row);
    }
  }

  void _retireRow(ConnectionRow row) {
    Timer(_rowRetireDelay, row.dispose);
  }

  @override
  void dispose() {
    _activityGeneration++;
    _refetchTimer?.cancel();
    _groupsTimer?.cancel();
    for (final row in _activeRows.values) {
      row.dispose();
    }
    for (final row in _closedRows.values) {
      row.dispose();
    }
    _activeRows.clear();
    _closedRows.clear();
    _disposeGroups();
    super.dispose();
  }
}
