import 'package:flutter/foundation.dart';

import 'background_image_store.dart';
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

/// Item style shared by the compact bottom bar and wide sidebar.
enum NavBarStyle {
  /// Selected item expands into an icon+label capsule; others icon-only.
  capsule,

  /// All items icon+label; a pill indicator slides behind the selection.
  pill,

  /// All items icon+label; selection is tint-only (iOS-like).
  tint,

  /// Material 3: indicator behind the selected icon.
  m3,
}

enum CompactControlKind {
  navigationBar,
  button,
  textField,
  segmented,
  toggle,
  slider,
}

enum AppThemeMode { system, light, dark }

enum UpdateChannel { stable, beta }

enum AutomaticColorSource { system, wallpaper }

enum DesktopTitleBarMode { system, custom, hidden }

enum AppBackgroundSource { theme, image }

enum AppBackgroundFit { cover, focalPoint }

enum BackgroundRotationOrder { sequential, random }

enum BackgroundRotationTrigger { appLaunch, appResume }

enum AppSurfaceEffect { solid, blur, acrylic }

/// How the proxies screen renders groups: the classic pinned-header list or
/// Surge-style gradient cards that expand into an overlay.
enum ProxiesLayout { list, cards }

enum ProxyProviderStyle { plain, liquid }

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

/// Title content used by the flat (ungrouped) connections list.
enum ConnectionTitleStyle { sourceToTarget, targetOnly }

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
  static const _kClosedConnectionsCapacity = 'closedConnectionsCapacity';
  static const _kLogInfoCapacity = 'logInfoCapacity';
  static const _kProxiesSort = 'proxiesSort';
  static const _kProxiesColumns = 'proxiesColumns';
  static const _kProxiesShowGroupIcons = 'proxiesShowGroupIcons';
  static const _kProxiesShowHiddenGroups = 'proxiesShowHiddenGroups';
  static const _kProxiesLayout = 'proxiesLayout';
  static const _kProxyProviderStyle = 'proxyProviderStyle';
  static const _kProxiesCardColored = 'proxiesCardColored';
  static const _kProxiesCardShowDelay = 'proxiesCardShowDelay';
  static const _kProxiesCardAutoLocate = 'proxiesCardAutoLocate';
  static const _kProxiesGroupByProvider = 'proxiesGroupByProvider';
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
  static const _kConnectionTitleStyle = 'connectionTitleStyle';
  static const _kGroupSort = 'connectionsGroupSort';
  static const _kGroupSortAsc = 'connectionsGroupSortAsc';
  static const _kUiFontFamily = 'uiFontFamily';
  static const _kUiFontFamilies = 'uiFontFamilies';
  static const _kImportedFonts = 'importedFonts';
  static const _kAllowInsecureOnlineResources = 'allowInsecureOnlineResources';
  static const _kUpdateChannel = 'updateChannel';
  static const _kGitHubToken = 'githubToken';
  static const _kGlobalThemeColor = 'globalThemeColor';
  static const _kAutomaticColor = 'automaticColor';
  static const _kAutomaticColorSource = 'automaticColorSource';
  static const _kPureBlackMode = 'pureBlackMode';
  static const _kShowDividers = 'showDividers';
  static const _kAppThemeMode = 'appThemeMode';
  static const _kDesktopTitleBarMode = 'desktopTitleBarMode';
  static const _kBackgroundSource = 'backgroundSource';
  static const _kBackgroundImagePath = 'backgroundImagePath';
  static const _kBackgroundImagePaths = 'backgroundImagePaths';
  static const _kBackgroundImageIndex = 'backgroundImageIndex';
  static const _kBackgroundRotationEnabled = 'backgroundRotationEnabled';
  static const _kBackgroundRotationOrder = 'backgroundRotationOrder';
  static const _kBackgroundRotationTrigger = 'backgroundRotationTrigger';
  static const _kBackgroundFit = 'backgroundFit';
  static const _kBackgroundFocalX = 'backgroundFocalX';
  static const _kBackgroundFocalY = 'backgroundFocalY';
  static const _kBackgroundZoom = 'backgroundZoom';
  static const _kSurfaceOpacity = 'surfaceOpacity';
  static const _kSurfaceEffect = 'surfaceEffect';
  static const _kSurfaceBlur = 'surfaceBlur';

  static const defaultConnectionsRefreshMs = 1000;
  static const defaultClosedConnectionsCapacity = 500;
  static const defaultLogInfoCapacity = 500;
  static const minCacheCapacity = 50;
  static const maxCacheCapacity = 5000;
  static const defaultProxiesSort = ProxiesSort.original;

  /// `0` means "auto" — pick a column count from the viewport width.
  static const defaultProxiesColumns = 0;
  static const defaultProxiesShowGroupIcons = true;
  static const defaultProxiesShowHiddenGroups = false;
  static const defaultProxiesLayout = ProxiesLayout.list;
  static const defaultProxyProviderStyle = ProxyProviderStyle.liquid;
  static const defaultProxiesCardColored = false;
  static const defaultProxiesCardShowDelay = false;
  static const defaultProxiesCardAutoLocate = false;
  static const defaultProxiesGroupByProvider = false;

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
  static const defaultConnectionTitleStyle =
      ConnectionTitleStyle.sourceToTarget;
  static const defaultGroupSort = GroupSort.name;
  static const defaultGroupSortAsc = true;
  static const defaultAllowInsecureOnlineResources = false;
  static const defaultUpdateChannel = UpdateChannel.stable;
  static const defaultGlobalThemeColor = 0xff66ccff;
  static const defaultAutomaticColor = false;
  static const defaultAutomaticColorSource = AutomaticColorSource.system;
  static const defaultPureBlackMode = false;
  static const defaultShowDividers = true;
  static const defaultAppThemeMode = AppThemeMode.system;
  static const defaultDesktopTitleBarMode = DesktopTitleBarMode.system;
  static const defaultBackgroundSource = AppBackgroundSource.theme;
  static const defaultBackgroundFit = AppBackgroundFit.cover;
  static const defaultBackgroundRotationEnabled = false;
  static const defaultBackgroundRotationOrder =
      BackgroundRotationOrder.sequential;
  static const defaultBackgroundRotationTrigger =
      BackgroundRotationTrigger.appLaunch;
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

  static (double, double) compactHeightRange(CompactControlKind kind) =>
      switch (kind) {
        CompactControlKind.navigationBar => (52, 76),
        CompactControlKind.slider => (28, 44),
        _ => (32, 52),
      };

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

  int get closedConnectionsCapacity => _int(
    _kClosedConnectionsCapacity,
    defaultClosedConnectionsCapacity,
  ).clamp(minCacheCapacity, maxCacheCapacity);

  Future<void> setClosedConnectionsCapacity(int value) async {
    final clamped = value.clamp(minCacheCapacity, maxCacheCapacity);
    if (clamped == closedConnectionsCapacity) return;
    _put(_kClosedConnectionsCapacity, clamped);
  }

  int get logInfoCapacity => _int(
    _kLogInfoCapacity,
    defaultLogInfoCapacity,
  ).clamp(minCacheCapacity, maxCacheCapacity);

  Future<void> setLogInfoCapacity(int value) async {
    final clamped = value.clamp(minCacheCapacity, maxCacheCapacity);
    if (clamped == logInfoCapacity) return;
    _put(_kLogInfoCapacity, clamped);
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

  ProxyProviderStyle get proxyProviderStyle => _decodeProxyProviderStyle(
    _str(_kProxyProviderStyle, defaultProxyProviderStyle.name),
  );

  Future<void> setProxyProviderStyle(ProxyProviderStyle value) async {
    if (value == proxyProviderStyle) return;
    _put(_kProxyProviderStyle, value.name);
  }

  bool get proxiesCardColored =>
      _bool(_kProxiesCardColored, defaultProxiesCardColored);

  Future<void> setProxiesCardColored(bool value) async {
    if (value == proxiesCardColored) return;
    _put(_kProxiesCardColored, value);
  }

  bool get proxiesCardShowDelay =>
      _bool(_kProxiesCardShowDelay, defaultProxiesCardShowDelay);

  Future<void> setProxiesCardShowDelay(bool value) async {
    if (value == proxiesCardShowDelay) return;
    _put(_kProxiesCardShowDelay, value);
  }

  bool get proxiesCardAutoLocate =>
      _bool(_kProxiesCardAutoLocate, defaultProxiesCardAutoLocate);

  Future<void> setProxiesCardAutoLocate(bool value) async {
    if (value == proxiesCardAutoLocate) return;
    _put(_kProxiesCardAutoLocate, value);
  }

  bool get proxiesGroupByProvider =>
      _bool(_kProxiesGroupByProvider, defaultProxiesGroupByProvider);

  Future<void> setProxiesGroupByProvider(bool value) async {
    if (value == proxiesGroupByProvider) return;
    _put(_kProxiesGroupByProvider, value);
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

  /// Title content for rows when source grouping is disabled.
  ConnectionTitleStyle get connectionTitleStyle => _decodeConnectionTitleStyle(
    _str(_kConnectionTitleStyle, defaultConnectionTitleStyle.name),
  );

  Future<void> setConnectionTitleStyle(ConnectionTitleStyle value) async {
    if (value == connectionTitleStyle) return;
    _put(_kConnectionTitleStyle, value.name);
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

  UpdateChannel get updateChannel =>
      _decodeUpdateChannel(_str(_kUpdateChannel, defaultUpdateChannel.name));

  Future<void> setUpdateChannel(UpdateChannel value) async {
    if (value == updateChannel) return;
    _put(_kUpdateChannel, value.name);
  }

  String get githubToken => _str(_kGitHubToken, '').trim();

  Future<void> setGitHubToken(String value) async {
    final token = value.trim();
    if (token == githubToken) return;
    _put(_kGitHubToken, token);
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

  AutomaticColorSource get automaticColorSource => _decodeAutomaticColorSource(
    _str(_kAutomaticColorSource, defaultAutomaticColorSource.name),
  );

  Future<void> setAutomaticColorSource(AutomaticColorSource value) async {
    if (value == automaticColorSource) return;
    _put(_kAutomaticColorSource, value.name);
  }

  bool get pureBlackMode => _bool(_kPureBlackMode, defaultPureBlackMode);

  Future<void> setPureBlackMode(bool value) async {
    if (value == pureBlackMode) return;
    _put(_kPureBlackMode, value);
  }

  bool get showDividers => _bool(_kShowDividers, defaultShowDividers);

  Future<void> setShowDividers(bool value) async {
    if (value == showDividers) return;
    _put(_kShowDividers, value);
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

  List<String> get backgroundImageReferences {
    final stored = _strList(_kBackgroundImagePaths);
    if (stored.isNotEmpty) return stored;
    final legacy = _str(_kBackgroundImagePath, '').trim();
    return legacy.isEmpty ? const [] : [legacy];
  }

  List<String> get backgroundImagePaths => [
    for (final reference in backgroundImageReferences)
      BackgroundImageStore.resolveReference(reference),
  ];

  int get backgroundImageIndex {
    final count = backgroundImageReferences.length;
    if (count == 0) return 0;
    return _int(_kBackgroundImageIndex, 0).clamp(0, count - 1).toInt();
  }

  String get backgroundImageReference {
    final references = backgroundImageReferences;
    return references.isEmpty ? '' : references[backgroundImageIndex];
  }

  String get backgroundImagePath =>
      BackgroundImageStore.resolveReference(backgroundImageReference);

  Future<void> setBackgroundImageReferences(
    Iterable<String> references, {
    int? selectedIndex,
    bool activate = false,
  }) async {
    final next = _sanitizeStringList(references);
    if (next.isEmpty) {
      _putAll({
        _kBackgroundImagePaths: const <String>[],
        _kBackgroundImageIndex: 0,
        _kBackgroundImagePath: '',
        _kBackgroundRotationEnabled: false,
        _kBackgroundSource: AppBackgroundSource.theme.name,
      });
      return;
    }
    final index = (selectedIndex ?? backgroundImageIndex)
        .clamp(0, next.length - 1)
        .toInt();
    _putAll({
      _kBackgroundImagePaths: next,
      _kBackgroundImageIndex: index,
      _kBackgroundImagePath: next[index],
      if (activate) _kBackgroundSource: AppBackgroundSource.image.name,
    });
  }

  Future<void> useBackgroundImages(Iterable<String> paths) async {
    final next = backgroundImageReferences.toList();
    final indices = <String, int>{
      for (var index = 0; index < next.length; index++) next[index]: index,
    };
    var selected = -1;
    for (final path in paths) {
      final reference = BackgroundImageStore.referenceForPath(path);
      if (reference.isEmpty) continue;
      var index = indices[reference];
      if (index == null) {
        index = next.length;
        next.add(reference);
        indices[reference] = index;
      }
      if (selected < 0) selected = index;
    }
    if (selected < 0) return;
    _putAll({
      _kBackgroundImagePaths: next,
      _kBackgroundImageIndex: selected,
      _kBackgroundImagePath: next[selected],
      _kBackgroundFocalX: defaultBackgroundFocalX,
      _kBackgroundFocalY: defaultBackgroundFocalY,
      _kBackgroundZoom: defaultBackgroundZoom,
      _kBackgroundSource: AppBackgroundSource.image.name,
    });
  }

  Future<void> selectBackgroundImage(int index) async {
    final references = backgroundImageReferences;
    if (index < 0 ||
        index >= references.length ||
        index == backgroundImageIndex) {
      return;
    }
    _putAll({
      _kBackgroundImageIndex: index,
      _kBackgroundImagePath: references[index],
    });
  }

  Future<void> removeBackgroundImage(int index) async {
    final references = backgroundImageReferences.toList();
    if (index < 0 || index >= references.length) return;
    final current = backgroundImageIndex;
    references.removeAt(index);
    if (references.isEmpty) {
      await clearBackgroundImage();
      return;
    }
    final nextIndex = index < current
        ? current - 1
        : index == current
        ? current.clamp(0, references.length - 1).toInt()
        : current;
    await setBackgroundImageReferences(
      references,
      selectedIndex: nextIndex,
      activate: backgroundSource == AppBackgroundSource.image,
    );
  }

  Future<void> reorderBackgroundImage(int oldIndex, int newIndex) async {
    final references = backgroundImageReferences.toList();
    if (oldIndex < 0 ||
        oldIndex >= references.length ||
        newIndex < 0 ||
        newIndex >= references.length ||
        oldIndex == newIndex) {
      return;
    }
    final current = backgroundImageReference;
    final moved = references.removeAt(oldIndex);
    references.insert(newIndex, moved);
    await setBackgroundImageReferences(
      references,
      selectedIndex: references.indexOf(current),
      activate: backgroundSource == AppBackgroundSource.image,
    );
  }

  bool get backgroundRotationEnabled =>
      _bool(_kBackgroundRotationEnabled, defaultBackgroundRotationEnabled);

  Future<void> setBackgroundRotationEnabled(bool value) async {
    if (value == backgroundRotationEnabled) return;
    _put(_kBackgroundRotationEnabled, value);
  }

  BackgroundRotationOrder get backgroundRotationOrder =>
      _decodeBackgroundRotationOrder(
        _str(_kBackgroundRotationOrder, defaultBackgroundRotationOrder.name),
      );

  Future<void> setBackgroundRotationOrder(BackgroundRotationOrder value) async {
    if (value == backgroundRotationOrder) return;
    _put(_kBackgroundRotationOrder, value.name);
  }

  BackgroundRotationTrigger get backgroundRotationTrigger =>
      _decodeBackgroundRotationTrigger(
        _str(
          _kBackgroundRotationTrigger,
          defaultBackgroundRotationTrigger.name,
        ),
      );

  Future<void> setBackgroundRotationTrigger(
    BackgroundRotationTrigger value,
  ) async {
    if (value == backgroundRotationTrigger) return;
    _put(_kBackgroundRotationTrigger, value.name);
  }

  Future<void> clearBackgroundImage() async {
    _putAll({
      _kBackgroundSource: AppBackgroundSource.theme.name,
      _kBackgroundImagePath: '',
      _kBackgroundImagePaths: const <String>[],
      _kBackgroundImageIndex: 0,
      _kBackgroundRotationEnabled: false,
    });
  }

  Future<void> resetBackgroundStyle() async {
    _putAll({
      _kBackgroundSource: defaultBackgroundSource.name,
      _kBackgroundImagePath: '',
      _kBackgroundImagePaths: const <String>[],
      _kBackgroundImageIndex: 0,
      _kBackgroundRotationEnabled: defaultBackgroundRotationEnabled,
      _kBackgroundRotationOrder: defaultBackgroundRotationOrder.name,
      _kBackgroundRotationTrigger: defaultBackgroundRotationTrigger.name,
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

  double compactControlHeight(CompactControlKind kind) {
    final range = compactHeightRange(kind);
    return _double(
      _compactStyleKey(kind, 'height'),
      _double(_compactKey(kind, 'height'), _defaultCompactHeight(kind)),
    ).clamp(range.$1, range.$2);
  }

  Future<void> setCompactControlHeight(
    CompactControlKind kind,
    double value,
  ) async {
    final range = compactHeightRange(kind);
    final next = value.clamp(range.$1, range.$2).toDouble();
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

  static UpdateChannel _decodeUpdateChannel(String? raw) {
    for (final value in UpdateChannel.values) {
      if (value.name == raw) return value;
    }
    return defaultUpdateChannel;
  }

  static AutomaticColorSource _decodeAutomaticColorSource(String? raw) {
    for (final value in AutomaticColorSource.values) {
      if (value.name == raw) return value;
    }
    return defaultAutomaticColorSource;
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

  static BackgroundRotationOrder _decodeBackgroundRotationOrder(String? raw) {
    for (final value in BackgroundRotationOrder.values) {
      if (value.name == raw) return value;
    }
    return defaultBackgroundRotationOrder;
  }

  static BackgroundRotationTrigger _decodeBackgroundRotationTrigger(
    String? raw,
  ) {
    for (final value in BackgroundRotationTrigger.values) {
      if (value.name == raw) return value;
    }
    return defaultBackgroundRotationTrigger;
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

  static ProxyProviderStyle _decodeProxyProviderStyle(String? raw) {
    for (final value in ProxyProviderStyle.values) {
      if (value.name == raw) return value;
    }
    return defaultProxyProviderStyle;
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

  static ConnectionTitleStyle _decodeConnectionTitleStyle(String? raw) {
    for (final value in ConnectionTitleStyle.values) {
      if (value.name == raw) return value;
    }
    return defaultConnectionTitleStyle;
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
