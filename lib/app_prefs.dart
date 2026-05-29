import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Which connections to drop when [AppPrefs.autoCloseOnSwitch] kicks in.
///
/// `all` closes every active connection on the controller; `group` only
/// closes the connections whose proxy chain involves the group whose
/// selection just changed.
enum CloseMode { all, group }

/// App-wide preferences not tied to any particular mihomo controller.
class AppPrefs extends ChangeNotifier {
  AppPrefs._(
    this._prefs,
    this._connectionsRefreshMs,
    this._proxiesSort,
    this._proxiesColumns,
    this._navLayout,
    this._autoCloseOnSwitch,
    this._delayTestUrl,
    this._delayTestTimeoutMs,
    this._delayTestScope,
    this._closeMode,
    this._connectionsSort,
    this._connectionsSortAsc,
    this._showProcessIcon,
    this._showAppName,
  );

  static const _kConnectionsRefreshMs = 'prefs.connectionsRefreshMs';
  static const _kProxiesSort = 'prefs.proxiesSort';
  static const _kProxiesColumns = 'prefs.proxiesColumns';
  static const _kNavLayout = 'prefs.navLayout';
  static const _kAutoCloseOnSwitch = 'prefs.autoCloseOnSwitch';
  static const _kDelayTestUrl = 'prefs.delayTestUrl';
  static const _kDelayTestTimeoutMs = 'prefs.delayTestTimeoutMs';
  static const _kDelayTestScope = 'prefs.delayTestScope';
  static const _kCloseMode = 'prefs.closeMode';
  static const _kConnectionsSort = 'prefs.connectionsSort';
  static const _kConnectionsSortAsc = 'prefs.connectionsSortAsc';
  static const _kShowProcessIcon = 'prefs.connectionsShowProcessIcon';
  static const _kShowAppName = 'prefs.connectionsShowAppName';

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

  final SharedPreferences _prefs;
  int _connectionsRefreshMs;
  ProxiesSort _proxiesSort;
  int _proxiesColumns;
  NavLayout _navLayout;
  bool _autoCloseOnSwitch;
  String _delayTestUrl;
  int _delayTestTimeoutMs;
  DelayTestScope _delayTestScope;
  CloseMode _closeMode;
  ConnectionsSort _connectionsSort;
  bool _connectionsSortAsc;
  bool _showProcessIcon;
  bool _showAppName;

  static Future<AppPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPrefs._(
      prefs,
      prefs.getInt(_kConnectionsRefreshMs) ?? defaultConnectionsRefreshMs,
      _decodeSort(prefs.getString(_kProxiesSort)),
      prefs.getInt(_kProxiesColumns) ?? defaultProxiesColumns,
      _decodeNavLayout(prefs.getString(_kNavLayout)),
      prefs.getBool(_kAutoCloseOnSwitch) ?? defaultAutoCloseOnSwitch,
      prefs.getString(_kDelayTestUrl) ?? defaultDelayTestUrl,
      prefs.getInt(_kDelayTestTimeoutMs) ?? defaultDelayTestTimeoutMs,
      _decodeScope(prefs.getString(_kDelayTestScope)),
      _decodeCloseMode(prefs.getString(_kCloseMode)),
      _decodeConnectionsSort(prefs.getString(_kConnectionsSort)),
      prefs.getBool(_kConnectionsSortAsc) ?? defaultConnectionsSortAsc,
      prefs.getBool(_kShowProcessIcon) ?? defaultShowProcessIcon,
      prefs.getBool(_kShowAppName) ?? defaultShowAppName,
    );
  }

  /// Polling interval for the connections list, in milliseconds.
  int get connectionsRefreshMs => _connectionsRefreshMs;

  Future<void> setConnectionsRefreshMs(int value) async {
    final clamped = value.clamp(250, 30000);
    if (clamped == _connectionsRefreshMs) return;
    _connectionsRefreshMs = clamped;
    await _prefs.setInt(_kConnectionsRefreshMs, clamped);
    notifyListeners();
  }

  ProxiesSort get proxiesSort => _proxiesSort;

  Future<void> setProxiesSort(ProxiesSort value) async {
    if (value == _proxiesSort) return;
    _proxiesSort = value;
    await _prefs.setString(_kProxiesSort, value.name);
    notifyListeners();
  }

  /// `0` = auto, `1..4` = explicit override.
  int get proxiesColumns => _proxiesColumns;

  Future<void> setProxiesColumns(int value) async {
    final clamped = value.clamp(0, 4);
    if (clamped == _proxiesColumns) return;
    _proxiesColumns = clamped;
    await _prefs.setInt(_kProxiesColumns, clamped);
    notifyListeners();
  }

  NavLayout get navLayout => _navLayout;

  Future<void> setNavLayout(NavLayout value) async {
    if (value == _navLayout) return;
    _navLayout = value;
    await _prefs.setString(_kNavLayout, value.name);
    notifyListeners();
  }

  /// When true, switching a group's selected proxy also closes all active
  /// connections so the new node takes effect immediately.
  bool get autoCloseOnSwitch => _autoCloseOnSwitch;

  Future<void> setAutoCloseOnSwitch(bool value) async {
    if (value == _autoCloseOnSwitch) return;
    _autoCloseOnSwitch = value;
    await _prefs.setBool(_kAutoCloseOnSwitch, value);
    notifyListeners();
  }

  /// URL hit by group/node delay tests. Empty string falls back to the default.
  String get delayTestUrl =>
      _delayTestUrl.isEmpty ? defaultDelayTestUrl : _delayTestUrl;

  Future<void> setDelayTestUrl(String value) async {
    final v = value.trim();
    if (v == _delayTestUrl) return;
    _delayTestUrl = v;
    await _prefs.setString(_kDelayTestUrl, v);
    notifyListeners();
  }

  int get delayTestTimeoutMs => _delayTestTimeoutMs;

  Future<void> setDelayTestTimeoutMs(int value) async {
    final clamped = value.clamp(500, 30000);
    if (clamped == _delayTestTimeoutMs) return;
    _delayTestTimeoutMs = clamped;
    await _prefs.setInt(_kDelayTestTimeoutMs, clamped);
    notifyListeners();
  }

  DelayTestScope get delayTestScope => _delayTestScope;

  Future<void> setDelayTestScope(DelayTestScope value) async {
    if (value == _delayTestScope) return;
    _delayTestScope = value;
    await _prefs.setString(_kDelayTestScope, value.name);
    notifyListeners();
  }

  CloseMode get closeMode => _closeMode;

  Future<void> setCloseMode(CloseMode value) async {
    if (value == _closeMode) return;
    _closeMode = value;
    await _prefs.setString(_kCloseMode, value.name);
    notifyListeners();
  }

  ConnectionsSort get connectionsSort => _connectionsSort;

  Future<void> setConnectionsSort(ConnectionsSort value) async {
    if (value == _connectionsSort) return;
    _connectionsSort = value;
    await _prefs.setString(_kConnectionsSort, value.name);
    notifyListeners();
  }

  bool get connectionsSortAsc => _connectionsSortAsc;

  Future<void> setConnectionsSortAsc(bool value) async {
    if (value == _connectionsSortAsc) return;
    _connectionsSortAsc = value;
    await _prefs.setBool(_kConnectionsSortAsc, value);
    notifyListeners();
  }

  /// Show each connection's owning-process icon (local backend only).
  bool get connectionsShowProcessIcon => _showProcessIcon;

  Future<void> setConnectionsShowProcessIcon(bool value) async {
    if (value == _showProcessIcon) return;
    _showProcessIcon = value;
    await _prefs.setBool(_kShowProcessIcon, value);
    notifyListeners();
  }

  /// Show the resolved application name in place of the raw process name.
  bool get connectionsShowAppName => _showAppName;

  Future<void> setConnectionsShowAppName(bool value) async {
    if (value == _showAppName) return;
    _showAppName = value;
    await _prefs.setBool(_kShowAppName, value);
    notifyListeners();
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
}
