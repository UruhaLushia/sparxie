import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'platform_capabilities.dart';

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
enum NavLayout { cards, standard, floating }

/// Item style of the compact bottom bar (floating and standard layouts).
enum NavBarStyle {
  /// Selected item expands into an icon+label capsule; others icon-only.
  capsule,

  /// All items icon+label; a pill indicator slides behind the selection.
  pill,

  /// All items icon+label; selection is tint-only (iOS-like).
  tint,

  /// Material 3: pill behind the selected icon, label always below.
  m3,
}

enum CompactControlKind { navigationBar, button, search, segmented, toggle }

enum AppThemeMode { system, light, dark }

enum DesktopTitleBarMode { system, custom, hidden }

enum AppBackgroundSource { theme, color, image }

enum AppBackgroundFit { cover, focalPoint }

enum AppSurfaceEffect { solid, blur, acrylic }

/// How the proxies screen renders groups: the classic pinned-header list or
/// Surge-style gradient cards that expand into an overlay.
enum ProxiesLayout { list, cards }

/// Where the delay-test URL comes from when testing a group.
///
/// `group` first tries the group's own `testUrl`/`tester` from the backend
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

@immutable
class ImportedFont {
  const ImportedFont({required this.family, required this.path});

  final String family;
  final String path;

  Map<String, String> toJson() => {'family': family, 'path': path};

  static ImportedFont? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final family = raw['family'];
    final path = raw['path'];
    if (family is! String || path is! String) return null;
    final cleanFamily = family.trim();
    final cleanPath = path.trim();
    if (cleanFamily.isEmpty || cleanPath.isEmpty) return null;
    return ImportedFont(family: cleanFamily, path: cleanPath);
  }
}

/// App-wide preferences not tied to any particular mihomo controller.
class AppPrefs extends ChangeNotifier {
  AppPrefs._(this._store);

  static const systemFontFamily = '__system_font__';

  final JsonStore _store;
  Map<String, dynamic> get _s => _store.section('prefs');

  static const _kConnectionsRefreshMs = 'connectionsRefreshMs';
  static const _kProxiesSort = 'proxiesSort';
  static const _kProxiesColumns = 'proxiesColumns';
  static const _kProxiesShowGroupIcons = 'proxiesShowGroupIcons';
  static const _kProxiesShowHiddenGroups = 'proxiesShowHiddenGroups';
  static const _kProxiesLayout = 'proxiesLayout';
  static const _kProxiesCardColored = 'proxiesCardColored';
  static const _kNavLayout = 'navLayout';
  static const _kNavBarStyle = 'navBarStyle';
  static const _kAutoCloseOnSwitch = 'autoCloseOnSwitch';
  static const _kDelayTestUrl = 'delayTestUrl';
  static const _kDelayTestTimeoutMs = 'delayTestTimeoutMs';
  static const _kDelayTestScope = 'delayTestScope';
  static const _kDelayTestUseGroupApi = 'delayTestUseGroupApi';
  static const _kDelayTestConcurrency = 'delayTestConcurrency';
  static const _kCloseMode = 'closeMode';
  static const _kConnectionsSort = 'connectionsSort';
  static const _kConnectionsSortAsc = 'connectionsSortAsc';
  static const _kShowProcessIcon = 'connectionsShowProcessIcon';
  static const _kShowAppName = 'connectionsShowAppName';
  static const _kGroupByProcess = 'connectionsGroupByProcess';
  static const _kGroupSort = 'connectionsGroupSort';
  static const _kGroupSortAsc = 'connectionsGroupSortAsc';
  static const _kUiFontFamily = 'uiFontFamily';
  static const _kUiFontFamilies = 'uiFontFamilies';
  static const _kImportedFonts = 'importedFonts';
  static const _kAllowInsecureOnlineResources = 'allowInsecureOnlineResources';
  static const _kGlobalThemeColor = 'globalThemeColor';
  static const _kAutomaticColor = 'automaticColor';
  static const _kPureBlackMode = 'pureBlackMode';
  static const _kAppThemeMode = 'appThemeMode';
  static const _kDesktopTitleBarMode = 'desktopTitleBarMode';
  static const _kBackgroundSource = 'backgroundSource';
  static const _kBackgroundColor = 'backgroundColor';
  static const _kBackgroundImagePath = 'backgroundImagePath';
  static const _kBackgroundFit = 'backgroundFit';
  static const _kBackgroundFocalX = 'backgroundFocalX';
  static const _kBackgroundFocalY = 'backgroundFocalY';
  static const _kBackgroundZoom = 'backgroundZoom';
  static const _kSurfaceOpacity = 'surfaceOpacity';
  static const _kSurfaceEffect = 'surfaceEffect';
  static const _kSurfaceBlur = 'surfaceBlur';

  static const defaultConnectionsRefreshMs = 1000;
  static const defaultProxiesSort = ProxiesSort.original;

  /// `0` means "auto" — pick a column count from the viewport width.
  static const defaultProxiesColumns = 0;
  static const defaultProxiesShowGroupIcons = true;
  static const defaultProxiesShowHiddenGroups = false;
  static const defaultProxiesLayout = ProxiesLayout.list;
  static const defaultProxiesCardColored = false;

  static const defaultNavLayout = NavLayout.cards;
  static const defaultNavBarStyle = NavBarStyle.capsule;
  static const defaultAutoCloseOnSwitch = true;
  static const defaultDelayTestUrl = 'https://www.gstatic.com/generate_204';
  static const defaultDelayTestTimeoutMs = 5000;
  static const defaultDelayTestScope = DelayTestScope.group;
  static const defaultDelayTestUseGroupApi = false;
  static const defaultDelayTestConcurrency = 50;
  static const defaultCloseMode = CloseMode.all;
  static const defaultConnectionsSort = ConnectionsSort.time;
  // Newest connections first when sorting by time.
  static const defaultConnectionsSortAsc = false;
  static const defaultShowProcessIcon = true;
  static const defaultShowAppName = false;
  static const defaultGroupByProcess = false;
  static const defaultGroupSort = GroupSort.name;
  static const defaultGroupSortAsc = true;
  static const defaultAllowInsecureOnlineResources = false;
  static const defaultGlobalThemeColor = 0xff66ccff;
  static const defaultAutomaticColor = false;
  static const defaultPureBlackMode = false;
  static const defaultAppThemeMode = AppThemeMode.system;
  static const defaultDesktopTitleBarMode = DesktopTitleBarMode.system;
  static const defaultBackgroundSource = AppBackgroundSource.theme;
  static const defaultBackgroundColor = 0xff18232c;
  static const defaultBackgroundFit = AppBackgroundFit.cover;
  static const defaultBackgroundFocalX = 0.0;
  static const defaultBackgroundFocalY = 0.0;
  static const defaultBackgroundZoom = 1.0;
  static const maxBackgroundZoom = 5.0;
  static const defaultSurfaceOpacity = 0.84;
  static const defaultSurfaceEffect = AppSurfaceEffect.acrylic;
  static const defaultSurfaceBlur = 18.0;
  static const defaultCompactThemeColor = 0xff66ccff;
  static const defaultCompactBorderRadius = 12.0;
  static const defaultCompactControlHeight = 40.0;
  static const defaultCompactWidthScale = 1.0;
  static const defaultNavigationInnerWidthScale = 1.0;
  static const defaultNavigationFloatingHeightOffset = 0.0;

  double _defaultCompactRadius(CompactControlKind kind) =>
      kind == CompactControlKind.navigationBar
      ? 28
      : defaultCompactBorderRadius;

  double _defaultCompactHeight(CompactControlKind kind) =>
      kind == CompactControlKind.navigationBar
      ? navLayout == NavLayout.floating
            ? 56
            : 64
      : defaultCompactControlHeight;

  double get _defaultNavigationInnerBorderRadius => switch (navBarStyle) {
    NavBarStyle.capsule => 21,
    NavBarStyle.pill => 25,
    NavBarStyle.tint => 14,
    NavBarStyle.m3 => 14,
  };

  double get _defaultNavigationInnerHeight => switch (navBarStyle) {
    NavBarStyle.capsule => 42,
    NavBarStyle.pill => 50,
    NavBarStyle.tint => 26,
    NavBarStyle.m3 => 26,
  };

  static double _minimumCompactHeight(CompactControlKind kind) =>
      kind == CompactControlKind.navigationBar ? 52 : 32;

  static double _maximumCompactHeight(CompactControlKind kind) =>
      kind == CompactControlKind.navigationBar ? 76 : 52;

  static Future<AppPrefs> load(JsonStore store) async => AppPrefs._(store);

  // Typed section accessors. Values live directly in the `prefs` section of
  // the shared config.json; getters read through with a default fallback.
  int _int(String key, int fallback) {
    final v = _s[key];
    return v is int ? v : (v is num ? v.toInt() : fallback);
  }

  double _double(String key, double fallback) {
    final v = _s[key];
    return v is num ? v.toDouble() : fallback;
  }

  bool _bool(String key, bool fallback) {
    final v = _s[key];
    return v is bool ? v : fallback;
  }

  String _str(String key, String fallback) {
    final v = _s[key];
    return v is String ? v : fallback;
  }

  List<String> _strList(String key) {
    final v = _s[key];
    return v is List ? _sanitizeStringList(v) : const [];
  }

  void _put(String key, Object value) {
    _s[key] = value;
    _store.scheduleSave();
    notifyListeners();
  }

  void _putAll(Map<String, Object> values) {
    var changed = false;
    for (final MapEntry(:key, :value) in values.entries) {
      if (_s[key] == value) continue;
      _s[key] = value;
      changed = true;
    }
    if (!changed) return;
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

  bool get proxiesShowGroupIcons =>
      _bool(_kProxiesShowGroupIcons, defaultProxiesShowGroupIcons);

  Future<void> setProxiesShowGroupIcons(bool value) async {
    if (value == proxiesShowGroupIcons) return;
    _put(_kProxiesShowGroupIcons, value);
  }

  bool get proxiesShowHiddenGroups =>
      _bool(_kProxiesShowHiddenGroups, defaultProxiesShowHiddenGroups);

  Future<void> setProxiesShowHiddenGroups(bool value) async {
    if (value == proxiesShowHiddenGroups) return;
    _put(_kProxiesShowHiddenGroups, value);
  }

  ProxiesLayout get proxiesLayout =>
      _decodeProxiesLayout(_str(_kProxiesLayout, defaultProxiesLayout.name));

  Future<void> setProxiesLayout(ProxiesLayout value) async {
    if (value == proxiesLayout) return;
    _put(_kProxiesLayout, value.name);
  }

  bool get proxiesCardColored =>
      _bool(_kProxiesCardColored, defaultProxiesCardColored);

  Future<void> setProxiesCardColored(bool value) async {
    if (value == proxiesCardColored) return;
    _put(_kProxiesCardColored, value);
  }

  NavLayout get navLayout =>
      _decodeNavLayout(_str(_kNavLayout, defaultNavLayout.name));

  Future<void> setNavLayout(NavLayout value) async {
    if (value == navLayout) return;
    _put(_kNavLayout, value.name);
  }

  NavBarStyle get navBarStyle =>
      _decodeNavBarStyle(_str(_kNavBarStyle, defaultNavBarStyle.name));

  Future<void> setNavBarStyle(NavBarStyle value) async {
    if (value == navBarStyle) return;
    _put(_kNavBarStyle, value.name);
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

  bool get delayTestUseGroupApi =>
      _bool(_kDelayTestUseGroupApi, defaultDelayTestUseGroupApi);

  Future<void> setDelayTestUseGroupApi(bool value) async {
    if (value == delayTestUseGroupApi) return;
    _put(_kDelayTestUseGroupApi, value);
  }

  int get delayTestConcurrency =>
      _int(_kDelayTestConcurrency, defaultDelayTestConcurrency);

  Future<void> setDelayTestConcurrency(int value) async {
    final clamped = value.clamp(1, 512);
    if (clamped == delayTestConcurrency) return;
    _put(_kDelayTestConcurrency, clamped);
  }

  CloseMode get closeMode =>
      _decodeCloseMode(_str(_kCloseMode, defaultCloseMode.name));

  Future<void> setCloseMode(CloseMode value) async {
    if (value == closeMode) return;
    _put(_kCloseMode, value.name);
  }

  ConnectionsSort get connectionsSort => _decodeConnectionsSort(
    _str(_kConnectionsSort, defaultConnectionsSort.name),
  );

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
      supportsProcessIdentity &&
      _bool(_kShowProcessIcon, defaultShowProcessIcon);

  Future<void> setConnectionsShowProcessIcon(bool value) async {
    if (value == connectionsShowProcessIcon) return;
    _put(_kShowProcessIcon, value);
  }

  /// Show the resolved application name in place of the raw process name.
  bool get connectionsShowAppName =>
      supportsProcessIdentity && _bool(_kShowAppName, defaultShowAppName);

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

  /// Ordered UI font family set. Empty = platform default.
  List<String> get uiFontFamilies {
    final families = _strList(_kUiFontFamilies);
    if (families.isNotEmpty || _s.containsKey(_kUiFontFamilies)) {
      return families;
    }
    final legacy = _str(_kUiFontFamily, '').trim();
    return legacy.isEmpty ? const [] : [legacy];
  }

  Future<void> setUiFontFamilies(List<String> value) async {
    final next = _sanitizeStringList(value);
    if (_sameStrings(next, uiFontFamilies)) return;
    _s[_kUiFontFamilies] = next;
    _s[_kUiFontFamily] = next.isEmpty ? '' : next.first;
    _store.scheduleSave();
    notifyListeners();
  }

  List<ImportedFont> get importedFonts {
    final raw = _s[_kImportedFonts];
    if (raw is! List) return const [];
    return _sanitizeImportedFonts(raw.map(ImportedFont.fromJson));
  }

  Future<void> setImportedFonts(List<ImportedFont> value) async {
    final next = _sanitizeImportedFonts(value);
    if (_sameImportedFonts(next, importedFonts)) return;
    _put(_kImportedFonts, [for (final font in next) font.toJson()]);
  }

  Future<void> addImportedFont(ImportedFont font) async {
    final next = [...importedFonts, font];
    await setImportedFonts(next);
  }

  bool get allowInsecureOnlineResources => _bool(
    _kAllowInsecureOnlineResources,
    defaultAllowInsecureOnlineResources,
  );

  Future<void> setAllowInsecureOnlineResources(bool value) async {
    if (value == allowInsecureOnlineResources) return;
    _put(_kAllowInsecureOnlineResources, value);
  }

  int get globalThemeColor => _int(_kGlobalThemeColor, defaultGlobalThemeColor);

  Future<void> setGlobalThemeColor(int value) async {
    if (value == globalThemeColor) return;
    _put(_kGlobalThemeColor, value);
  }

  bool get automaticColor => _bool(_kAutomaticColor, defaultAutomaticColor);

  Future<void> setAutomaticColor(bool value) async {
    if (value == automaticColor) return;
    _put(_kAutomaticColor, value);
  }

  bool get pureBlackMode => _bool(_kPureBlackMode, defaultPureBlackMode);

  Future<void> setPureBlackMode(bool value) async {
    if (value == pureBlackMode) return;
    _put(_kPureBlackMode, value);
  }

  AppThemeMode get appThemeMode =>
      _decodeAppThemeMode(_str(_kAppThemeMode, defaultAppThemeMode.name));

  Future<void> setAppThemeMode(AppThemeMode value) async {
    if (value == appThemeMode) return;
    _put(_kAppThemeMode, value.name);
  }

  DesktopTitleBarMode get desktopTitleBarMode => _decodeDesktopTitleBarMode(
    _str(_kDesktopTitleBarMode, defaultDesktopTitleBarMode.name),
  );

  Future<void> setDesktopTitleBarMode(DesktopTitleBarMode value) async {
    if (value == desktopTitleBarMode) return;
    _put(_kDesktopTitleBarMode, value.name);
  }

  AppBackgroundSource get backgroundSource => _decodeBackgroundSource(
    _str(_kBackgroundSource, defaultBackgroundSource.name),
  );

  Future<void> setBackgroundSource(AppBackgroundSource value) async {
    if (value == backgroundSource) return;
    _put(_kBackgroundSource, value.name);
  }

  int get backgroundColor => _int(_kBackgroundColor, defaultBackgroundColor);

  Future<void> setBackgroundColor(int value) async {
    if (value == backgroundColor) return;
    _put(_kBackgroundColor, value);
  }

  String get backgroundImagePath => _str(_kBackgroundImagePath, '').trim();

  Future<void> useBackgroundImage(String path) async {
    final next = path.trim();
    if (next.isEmpty) return;
    _putAll({
      _kBackgroundImagePath: next,
      _kBackgroundFocalX: defaultBackgroundFocalX,
      _kBackgroundFocalY: defaultBackgroundFocalY,
      _kBackgroundZoom: defaultBackgroundZoom,
      _kBackgroundSource: AppBackgroundSource.image.name,
    });
  }

  Future<void> clearBackgroundImage() async {
    _putAll({
      _kBackgroundSource: AppBackgroundSource.theme.name,
      _kBackgroundImagePath: '',
    });
  }

  Future<void> resetBackgroundStyle() async {
    _putAll({
      _kBackgroundSource: defaultBackgroundSource.name,
      _kBackgroundColor: defaultBackgroundColor,
      _kBackgroundImagePath: '',
      _kBackgroundFit: defaultBackgroundFit.name,
      _kBackgroundFocalX: defaultBackgroundFocalX,
      _kBackgroundFocalY: defaultBackgroundFocalY,
      _kBackgroundZoom: defaultBackgroundZoom,
      _kSurfaceOpacity: defaultSurfaceOpacity,
      _kSurfaceEffect: defaultSurfaceEffect.name,
      _kSurfaceBlur: defaultSurfaceBlur,
    });
  }

  AppBackgroundFit get backgroundFit =>
      _decodeBackgroundFit(_str(_kBackgroundFit, defaultBackgroundFit.name));

  Future<void> setBackgroundFit(AppBackgroundFit value) async {
    if (value == backgroundFit) return;
    _put(_kBackgroundFit, value.name);
  }

  double get backgroundFocalX =>
      _normalizedFocal(_double(_kBackgroundFocalX, defaultBackgroundFocalX));

  double get backgroundFocalY =>
      _normalizedFocal(_double(_kBackgroundFocalY, defaultBackgroundFocalY));

  double get backgroundZoom => _normalizedBackgroundZoom(
    _double(_kBackgroundZoom, defaultBackgroundZoom),
  );

  Future<void> setBackgroundViewport(double x, double y, double zoom) async {
    final nextX = _normalizedFocal(x);
    final nextY = _normalizedFocal(y);
    final nextZoom = _normalizedBackgroundZoom(zoom);
    if (nextX == backgroundFocalX &&
        nextY == backgroundFocalY &&
        nextZoom == backgroundZoom) {
      return;
    }
    _putAll({
      _kBackgroundFocalX: nextX,
      _kBackgroundFocalY: nextY,
      _kBackgroundZoom: nextZoom,
    });
  }

  double get surfaceOpacity =>
      _double(_kSurfaceOpacity, defaultSurfaceOpacity).clamp(0.05, 1.0);

  Future<void> setSurfaceOpacity(double value) async {
    final next = value.clamp(0.05, 1.0).toDouble();
    if (next == surfaceOpacity) return;
    _put(_kSurfaceOpacity, next);
  }

  AppSurfaceEffect get surfaceEffect =>
      _decodeSurfaceEffect(_str(_kSurfaceEffect, defaultSurfaceEffect.name));

  Future<void> setSurfaceEffect(AppSurfaceEffect value) async {
    if (value == surfaceEffect) return;
    _put(_kSurfaceEffect, value.name);
  }

  double get surfaceBlur =>
      _double(_kSurfaceBlur, defaultSurfaceBlur).clamp(0.0, 40.0);

  Future<void> setSurfaceBlur(double value) async {
    final next = value.clamp(0.0, 40.0).toDouble();
    if (next == surfaceBlur) return;
    _put(_kSurfaceBlur, next);
  }

  String _compactKey(CompactControlKind kind, String property) =>
      'compact.${kind.name}.$property';

  String _navigationInnerKey(String property, [NavBarStyle? style]) =>
      'compact.navigationBar.inner.${(style ?? navBarStyle).name}.$property';

  String _compactStyleKey(
    CompactControlKind kind,
    String property, [
    NavBarStyle? style,
  ]) => kind == CompactControlKind.navigationBar
      ? 'compact.navigationBar.outer.${(style ?? navBarStyle).name}.$property'
      : _compactKey(kind, property);

  int compactThemeColor(CompactControlKind kind) => _int(
    _compactStyleKey(kind, 'color'),
    _int(_compactKey(kind, 'color'), defaultCompactThemeColor),
  );

  bool compactColorFollowsGlobal(CompactControlKind kind) {
    final key = _compactStyleKey(kind, 'followGlobalColor');
    final legacyKey = _compactKey(kind, 'followGlobalColor');
    final hasCustomColor =
        _s.containsKey(_compactStyleKey(kind, 'color')) ||
        _s.containsKey(_compactKey(kind, 'color'));
    return _bool(key, _bool(legacyKey, !hasCustomColor));
  }

  int effectiveCompactThemeColor(CompactControlKind kind) =>
      compactColorFollowsGlobal(kind)
      ? globalThemeColor
      : compactThemeColor(kind);

  Future<void> setCompactColorFollowsGlobal(
    CompactControlKind kind,
    bool value,
  ) async {
    final key = _compactStyleKey(kind, 'followGlobalColor');
    if (_s[key] == value) return;
    _put(key, value);
  }

  Future<void> setCompactThemeColor(CompactControlKind kind, int value) async {
    final key = _compactStyleKey(kind, 'color');
    if (_s[key] == value) return;
    _put(key, value);
  }

  double compactBorderRadius(CompactControlKind kind) => _double(
    _compactStyleKey(kind, 'borderRadius'),
    _double(_compactKey(kind, 'borderRadius'), _defaultCompactRadius(kind)),
  ).clamp(0, 36);

  Future<void> setCompactBorderRadius(
    CompactControlKind kind,
    double value,
  ) async {
    final next = value.clamp(0, 36).toDouble();
    final key = _compactStyleKey(kind, 'borderRadius');
    if (_s[key] == next) return;
    _put(key, next);
  }

  double compactControlHeight(CompactControlKind kind) => _double(
    _compactStyleKey(kind, 'height'),
    _double(_compactKey(kind, 'height'), _defaultCompactHeight(kind)),
  ).clamp(_minimumCompactHeight(kind), _maximumCompactHeight(kind));

  Future<void> setCompactControlHeight(
    CompactControlKind kind,
    double value,
  ) async {
    final next = value
        .clamp(_minimumCompactHeight(kind), _maximumCompactHeight(kind))
        .toDouble();
    final key = _compactStyleKey(kind, 'height');
    if (_s[key] == next) return;
    _put(key, next);
  }

  double compactWidthScale(CompactControlKind kind) => _double(
    _compactStyleKey(kind, 'widthScale'),
    _double(_compactKey(kind, 'widthScale'), defaultCompactWidthScale),
  ).clamp(0.75, 1.5);

  Future<void> setCompactWidthScale(
    CompactControlKind kind,
    double value,
  ) async {
    final next = value.clamp(0.75, 1.5).toDouble();
    final key = _compactStyleKey(kind, 'widthScale');
    if (_s[key] == next) return;
    _put(key, next);
  }

  bool get navigationSurfaceFollowsGlobal => _bool(
    _compactStyleKey(CompactControlKind.navigationBar, 'followGlobalSurface'),
    true,
  );

  AppSurfaceEffect get navigationSurfaceEffect => _decodeSurfaceEffect(
    _str(
      _compactStyleKey(CompactControlKind.navigationBar, 'surfaceEffect'),
      defaultSurfaceEffect.name,
    ),
  );

  double get navigationSurfaceOpacity => _double(
    _compactStyleKey(CompactControlKind.navigationBar, 'surfaceOpacity'),
    defaultSurfaceOpacity,
  ).clamp(0.05, 1.0);

  double get navigationSurfaceBlur => _double(
    _compactStyleKey(CompactControlKind.navigationBar, 'surfaceBlur'),
    defaultSurfaceBlur,
  ).clamp(0.0, 40.0);

  AppSurfaceEffect get effectiveNavigationSurfaceEffect =>
      navigationSurfaceFollowsGlobal ? surfaceEffect : navigationSurfaceEffect;

  double get effectiveNavigationSurfaceOpacity => navigationSurfaceFollowsGlobal
      ? surfaceOpacity
      : navigationSurfaceOpacity;

  double get effectiveNavigationSurfaceBlur =>
      navigationSurfaceFollowsGlobal ? surfaceBlur : navigationSurfaceBlur;

  Future<void> setNavigationSurfaceFollowsGlobal(bool value) async {
    final followKey = _compactStyleKey(
      CompactControlKind.navigationBar,
      'followGlobalSurface',
    );
    if (_bool(followKey, true) == value) return;
    if (!value) {
      _s.putIfAbsent(
        _compactStyleKey(CompactControlKind.navigationBar, 'surfaceEffect'),
        () => surfaceEffect.name,
      );
      _s.putIfAbsent(
        _compactStyleKey(CompactControlKind.navigationBar, 'surfaceOpacity'),
        () => surfaceOpacity,
      );
      _s.putIfAbsent(
        _compactStyleKey(CompactControlKind.navigationBar, 'surfaceBlur'),
        () => surfaceBlur,
      );
    }
    _s[followKey] = value;
    _store.scheduleSave();
    notifyListeners();
  }

  Future<void> setNavigationSurfaceEffect(AppSurfaceEffect value) async {
    final key = _compactStyleKey(
      CompactControlKind.navigationBar,
      'surfaceEffect',
    );
    if (_s[key] == value.name) return;
    _put(key, value.name);
  }

  Future<void> setNavigationSurfaceOpacity(double value) async {
    final next = value.clamp(0.05, 1.0).toDouble();
    final key = _compactStyleKey(
      CompactControlKind.navigationBar,
      'surfaceOpacity',
    );
    if (_s[key] == next) return;
    _put(key, next);
  }

  Future<void> setNavigationSurfaceBlur(double value) async {
    final next = value.clamp(0.0, 40.0).toDouble();
    final key = _compactStyleKey(
      CompactControlKind.navigationBar,
      'surfaceBlur',
    );
    if (_s[key] == next) return;
    _put(key, next);
  }

  int get navigationInnerThemeColor => _int(
    _navigationInnerKey('color'),
    _int(
      _compactKey(CompactControlKind.navigationBar, 'innerColor'),
      effectiveCompactThemeColor(CompactControlKind.navigationBar),
    ),
  );

  bool get hasNavigationInnerThemeColor =>
      _s.containsKey(_navigationInnerKey('color')) ||
      _s.containsKey(
        _compactKey(CompactControlKind.navigationBar, 'innerColor'),
      );

  Future<void> setNavigationInnerThemeColor(int value) async {
    final key = _navigationInnerKey('color');
    if (_s[key] == value) return;
    _put(key, value);
  }

  double get navigationInnerBorderRadius => _double(
    _navigationInnerKey('borderRadius'),
    _double(
      _compactKey(CompactControlKind.navigationBar, 'innerBorderRadius'),
      _defaultNavigationInnerBorderRadius,
    ),
  ).clamp(0, 36);

  Future<void> setNavigationInnerBorderRadius(double value) async {
    final next = value.clamp(0, 36).toDouble();
    final key = _navigationInnerKey('borderRadius');
    if (_s[key] == next) return;
    _put(key, next);
  }

  double get navigationInnerHeight => _double(
    _navigationInnerKey('height'),
    _double(
      _compactKey(CompactControlKind.navigationBar, 'innerHeight'),
      _defaultNavigationInnerHeight,
    ),
  ).clamp(24, 68);

  Future<void> setNavigationInnerHeight(double value) async {
    final next = value.clamp(24, 68).toDouble();
    final key = _navigationInnerKey('height');
    if (_s[key] == next) return;
    _put(key, next);
  }

  double get navigationInnerWidthScale => _double(
    _navigationInnerKey('widthScale'),
    _double(
      _compactKey(CompactControlKind.navigationBar, 'innerWidthScale'),
      defaultNavigationInnerWidthScale,
    ),
  ).clamp(0.75, 1.5);

  Future<void> setNavigationInnerWidthScale(double value) async {
    final next = value.clamp(0.75, 1.5).toDouble();
    final key = _navigationInnerKey('widthScale');
    if (_s[key] == next) return;
    _put(key, next);
  }

  double get navigationFloatingHeightOffset => _double(
    _compactStyleKey(CompactControlKind.navigationBar, 'heightOffset'),
    defaultNavigationFloatingHeightOffset,
  ).clamp(-20, 20);

  Future<void> setNavigationFloatingHeightOffset(double value) async {
    final next = value.clamp(-20, 20).toDouble();
    final key = _compactStyleKey(
      CompactControlKind.navigationBar,
      'heightOffset',
    );
    if (_s[key] == next) return;
    _put(key, next);
  }

  Future<void> resetCompactStyle(CompactControlKind kind) async {
    for (final property in const [
      'color',
      'borderRadius',
      'height',
      'widthScale',
      'innerColor',
      'innerBorderRadius',
      'innerHeight',
      'innerWidthScale',
      'followGlobalColor',
    ]) {
      _s.remove(_compactKey(kind, property));
    }
    if (kind == CompactControlKind.navigationBar) {
      for (final property in const [
        'color',
        'borderRadius',
        'height',
        'widthScale',
        'heightOffset',
        'followGlobalColor',
        'followGlobalSurface',
        'surfaceEffect',
        'surfaceOpacity',
        'surfaceBlur',
      ]) {
        _s.remove(_navigationInnerKey(property));
        _s.remove(_compactStyleKey(kind, property));
      }
    }
    _store.scheduleSave();
    notifyListeners();
  }

  static ProxiesSort _decodeSort(String? raw) {
    if (raw == null) return defaultProxiesSort;
    for (final v in ProxiesSort.values) {
      if (v.name == raw) return v;
    }
    return defaultProxiesSort;
  }

  static AppThemeMode _decodeAppThemeMode(String? raw) {
    for (final value in AppThemeMode.values) {
      if (value.name == raw) return value;
    }
    return defaultAppThemeMode;
  }

  static DesktopTitleBarMode _decodeDesktopTitleBarMode(String? raw) {
    for (final value in DesktopTitleBarMode.values) {
      if (value.name == raw) return value;
    }
    return defaultDesktopTitleBarMode;
  }

  static AppBackgroundSource _decodeBackgroundSource(String? raw) {
    for (final value in AppBackgroundSource.values) {
      if (value.name == raw) return value;
    }
    return defaultBackgroundSource;
  }

  static AppSurfaceEffect _decodeSurfaceEffect(String? raw) {
    for (final value in AppSurfaceEffect.values) {
      if (value.name == raw) return value;
    }
    return defaultSurfaceEffect;
  }

  static AppBackgroundFit _decodeBackgroundFit(String? raw) {
    // The old contain mode is migrated to focal-point cover. Its default
    // center coordinates preserve a sensible first result for existing users.
    if (raw == 'contain') return AppBackgroundFit.focalPoint;
    for (final value in AppBackgroundFit.values) {
      if (value.name == raw) return value;
    }
    return defaultBackgroundFit;
  }

  static double _normalizedFocal(double value) =>
      value.isFinite ? value.clamp(-1.0, 1.0).toDouble() : 0.0;

  static double _normalizedBackgroundZoom(double value) => value.isFinite
      ? value.clamp(defaultBackgroundZoom, maxBackgroundZoom).toDouble()
      : defaultBackgroundZoom;

  static ProxiesLayout _decodeProxiesLayout(String? raw) {
    if (raw == null) return defaultProxiesLayout;
    for (final v in ProxiesLayout.values) {
      if (v.name == raw) return v;
    }
    return defaultProxiesLayout;
  }

  static NavBarStyle _decodeNavBarStyle(String? raw) {
    if (raw == null) return defaultNavBarStyle;
    for (final v in NavBarStyle.values) {
      if (v.name == raw) return v;
    }
    return defaultNavBarStyle;
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

  static List<String> _sanitizeStringList(Iterable<Object?> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in raw) {
      if (value is! String) continue;
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      out.add(trimmed);
    }
    return out;
  }

  static List<ImportedFont> _sanitizeImportedFonts(
    Iterable<ImportedFont?> raw,
  ) {
    final seen = <String>{};
    final out = <ImportedFont>[];
    for (final font in raw) {
      if (font == null || !seen.add(font.family)) continue;
      out.add(font);
    }
    return out;
  }

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameImportedFonts(List<ImportedFont> a, List<ImportedFont> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].family != b[i].family || a[i].path != b[i].path) return false;
    }
    return true;
  }
}
