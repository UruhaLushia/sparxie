import 'package:flutter/foundation.dart';

import 'config_store.dart';

/// How a proxy group's nodes are ordered in the grid.
enum ProxiesSort {
  /// Mihomo's natural order (config order).
  original,

  /// Alphabetical by name.
  name,

  /// Latest delay ascending (timeouts pushed to the end, untested last).
  delay,
}

/// Visual layout of the primary navigation chrome.
enum NavLayout { cards, standard }

/// Where the delay-test URL comes from when testing a group.
///
/// `group` first tries the group's own `testUrl`/`tester` from mihomo
/// (falling back to the global URL when missing); `global` always uses
/// the global URL.
enum DelayTestScope { group, global }

/// Sort key for the connections list.
enum ConnectionsSort {
  /// Connection start time.
  time,

  /// Cumulative upload bytes.
  upload,

  /// Cumulative download bytes.
  download,

  /// Last-tick upload speed.
  uploadSpeed,

  /// Last-tick download speed.
  downloadSpeed,

  /// Process name (string compare).
  process,
}

/// Sort key for the process-group list (grouped connections view).
enum GroupSort {
  /// Process / group name.
  name,

  /// Connection count.
  count,

  /// Aggregated upload bytes.
  upload,

  /// Aggregated download bytes.
  download,

  /// Aggregated upload speed.
  uploadSpeed,

  /// Aggregated download speed.
  downloadSpeed,
}

/// Which connections to drop when [AppPrefs.autoCloseOnSwitch] kicks in.
///
/// `all` closes every active connection on the controller; `group` only
/// closes the connections whose proxy chain involves the group whose
/// selection just changed.
enum CloseMode { all, group }

/// App-wide preferences not tied to any particular mihomo controller.
class AppPrefs extends ChangeNotifier {
  AppPrefs._(this._store);

  final JsonStore _store;
  Map<String, dynamic> get _s => _store.section('prefs');

  static const _kConnectionsRefreshMs = 'connectionsRefreshMs';
  static const _kProxiesSort = 'proxiesSort';
  static const _kProxiesColumns = 'proxiesColumns';
  static const _kNavLayout = 'navLayout';
  static const _kAutoCloseOnSwitch = 'autoCloseOnSwitch';
  static const _kDelayTestUrl = 'delayTestUrl';
  static const _kDelayTestTimeoutMs = 'delayTestTimeoutMs';
  static const _kDelayTestScope = 'delayTestScope';
  static const _kCloseMode = 'closeMode';
  static const _kConnectionsSort = 'connectionsSort';
  static const _kConnectionsSortAsc = 'connectionsSortAsc';
  static const _kShowProcessIcon = 'connectionsShowProcessIcon';
  static const _kShowAppName = 'connectionsShowAppName';
  static const _kGroupByProcess = 'connectionsGroupByProcess';
  static const _kGroupSort = 'connectionsGroupSort';
  static const _kGroupSortAsc = 'connectionsGroupSortAsc';

  static const defaultConnectionsRefreshMs = 1000;
  static const defaultProxiesSort = ProxiesSort.original;

  /// `0` means "auto" — pick a column count from the viewport width.
  static const defaultProxiesColumns = 0;

  static const defaultNavLayout = NavLayout.cards;
  static const defaultAutoCloseOnSwitch = true;
  static const defaultDelayTestUrl = 'https://www.gstatic.com/generate_204';
  static const defaultDelayTestTimeoutMs = 5000;
  static const defaultDelayTestScope = DelayTestScope.group;
  static const defaultCloseMode = CloseMode.all;
  static const defaultConnectionsSort = ConnectionsSort.time;
  // Newest connections first when sorting by time.
  static const defaultConnectionsSortAsc = false;
  static const defaultShowProcessIcon = true;
  static const defaultShowAppName = false;
  static const defaultGroupByProcess = false;
  static const defaultGroupSort = GroupSort.name;
  static const defaultGroupSortAsc = true;

  static Future<AppPrefs> load(JsonStore store) async => AppPrefs._(store);

  // Typed section accessors. Values live directly in the `prefs` section of
  // the shared config.json; getters read through with a default fallback.
  int _int(String key, int fallback) {
    final v = _s[key];
    return v is int ? v : (v is num ? v.toInt() : fallback);
  }

  bool _bool(String key, bool fallback) {
    final v = _s[key];
    return v is bool ? v : fallback;
  }

  String _str(String key, String fallback) {
    final v = _s[key];
    return v is String ? v : fallback;
  }

  void _put(String key, Object value) {
    _s[key] = value;
    _store.scheduleSave();
    notifyListeners();
  }

  /// Polling interval for the connections list, in milliseconds.
  int get connectionsRefreshMs =>
      _int(_kConnectionsRefreshMs, defaultConnectionsRefreshMs);

  Future<void> setConnectionsRefreshMs(int value) async {
    final clamped = value.clamp(250, 30000);
    if (clamped == connectionsRefreshMs) return;
    _put(_kConnectionsRefreshMs, clamped);
  }

  ProxiesSort get proxiesSort =>
      _decodeSort(_str(_kProxiesSort, defaultProxiesSort.name));

  Future<void> setProxiesSort(ProxiesSort value) async {
    if (value == proxiesSort) return;
    _put(_kProxiesSort, value.name);
  }

  /// `0` = auto, `1..4` = explicit override.
  int get proxiesColumns => _int(_kProxiesColumns, defaultProxiesColumns);

  Future<void> setProxiesColumns(int value) async {
    final clamped = value.clamp(0, 4);
    if (clamped == proxiesColumns) return;
    _put(_kProxiesColumns, clamped);
  }

  NavLayout get navLayout =>
      _decodeNavLayout(_str(_kNavLayout, defaultNavLayout.name));

  Future<void> setNavLayout(NavLayout value) async {
    if (value == navLayout) return;
    _put(_kNavLayout, value.name);
  }

  /// When true, switching a group's selected proxy also closes all active
  /// connections so the new node takes effect immediately.
  bool get autoCloseOnSwitch =>
      _bool(_kAutoCloseOnSwitch, defaultAutoCloseOnSwitch);

  Future<void> setAutoCloseOnSwitch(bool value) async {
    if (value == autoCloseOnSwitch) return;
    _put(_kAutoCloseOnSwitch, value);
  }

  /// URL hit by group/node delay tests. Empty string falls back to the default.
  String get delayTestUrl {
    final v = _str(_kDelayTestUrl, '');
    return v.isEmpty ? defaultDelayTestUrl : v;
  }

  Future<void> setDelayTestUrl(String value) async {
    final v = value.trim();
    if (v == _str(_kDelayTestUrl, '')) return;
    _put(_kDelayTestUrl, v);
  }

  int get delayTestTimeoutMs =>
      _int(_kDelayTestTimeoutMs, defaultDelayTestTimeoutMs);

  Future<void> setDelayTestTimeoutMs(int value) async {
    final clamped = value.clamp(500, 30000);
    if (clamped == delayTestTimeoutMs) return;
    _put(_kDelayTestTimeoutMs, clamped);
  }

  DelayTestScope get delayTestScope =>
      _decodeScope(_str(_kDelayTestScope, defaultDelayTestScope.name));

  Future<void> setDelayTestScope(DelayTestScope value) async {
    if (value == delayTestScope) return;
    _put(_kDelayTestScope, value.name);
  }

  CloseMode get closeMode =>
      _decodeCloseMode(_str(_kCloseMode, defaultCloseMode.name));

  Future<void> setCloseMode(CloseMode value) async {
    if (value == closeMode) return;
    _put(_kCloseMode, value.name);
  }

  ConnectionsSort get connectionsSort =>
      _decodeConnectionsSort(_str(_kConnectionsSort, defaultConnectionsSort.name));

  Future<void> setConnectionsSort(ConnectionsSort value) async {
    if (value == connectionsSort) return;
    _put(_kConnectionsSort, value.name);
  }

  bool get connectionsSortAsc =>
      _bool(_kConnectionsSortAsc, defaultConnectionsSortAsc);

  Future<void> setConnectionsSortAsc(bool value) async {
    if (value == connectionsSortAsc) return;
    _put(_kConnectionsSortAsc, value);
  }

  /// Show each connection's owning-process icon (local backend only).
  bool get connectionsShowProcessIcon =>
      _bool(_kShowProcessIcon, defaultShowProcessIcon);

  Future<void> setConnectionsShowProcessIcon(bool value) async {
    if (value == connectionsShowProcessIcon) return;
    _put(_kShowProcessIcon, value);
  }

  /// Show the resolved application name in place of the raw process name.
  bool get connectionsShowAppName => _bool(_kShowAppName, defaultShowAppName);

  Future<void> setConnectionsShowAppName(bool value) async {
    if (value == connectionsShowAppName) return;
    _put(_kShowAppName, value);
  }

  /// Group the active connections list by owning process.
  bool get connectionsGroupByProcess =>
      _bool(_kGroupByProcess, defaultGroupByProcess);

  Future<void> setConnectionsGroupByProcess(bool value) async {
    if (value == connectionsGroupByProcess) return;
    _put(_kGroupByProcess, value);
  }

  /// Sort key for the grouped connections view (groups, not connections).
  GroupSort get connectionsGroupSort =>
      _decodeGroupSort(_str(_kGroupSort, defaultGroupSort.name));

  Future<void> setConnectionsGroupSort(GroupSort value) async {
    if (value == connectionsGroupSort) return;
    _put(_kGroupSort, value.name);
  }

  bool get connectionsGroupSortAsc =>
      _bool(_kGroupSortAsc, defaultGroupSortAsc);

  Future<void> setConnectionsGroupSortAsc(bool value) async {
    if (value == connectionsGroupSortAsc) return;
    _put(_kGroupSortAsc, value);
  }

  static ProxiesSort _decodeSort(String? raw) {
    if (raw == null) return defaultProxiesSort;
    for (final v in ProxiesSort.values) {
      if (v.name == raw) return v;
    }
    return defaultProxiesSort;
  }

  static NavLayout _decodeNavLayout(String? raw) {
    if (raw == null) return defaultNavLayout;
    for (final v in NavLayout.values) {
      if (v.name == raw) return v;
    }
    return defaultNavLayout;
  }

  static DelayTestScope _decodeScope(String? raw) {
    if (raw == null) return defaultDelayTestScope;
    for (final v in DelayTestScope.values) {
      if (v.name == raw) return v;
    }
    return defaultDelayTestScope;
  }

  static CloseMode _decodeCloseMode(String? raw) {
    if (raw == null) return defaultCloseMode;
    for (final v in CloseMode.values) {
      if (v.name == raw) return v;
    }
    return defaultCloseMode;
  }

  static ConnectionsSort _decodeConnectionsSort(String? raw) {
    if (raw == null) return defaultConnectionsSort;
    for (final v in ConnectionsSort.values) {
      if (v.name == raw) return v;
    }
    return defaultConnectionsSort;
  }

  static GroupSort _decodeGroupSort(String? raw) {
    if (raw == null) return defaultGroupSort;
    for (final v in GroupSort.values) {
      if (v.name == raw) return v;
    }
    return defaultGroupSort;
  }
}
