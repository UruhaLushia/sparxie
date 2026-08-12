import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gamepads/flutter_gamepads.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:gamepads/gamepads.dart';

import 'app_paths.dart';
import 'app_prefs.dart';
import 'app_update_cleanup.dart';
import 'background_accent_color.dart';
import 'background_image_store.dart';
import 'background_rotation.dart';
import 'config_store.dart';
import 'controller.dart';
import 'controller_uri_import.dart';
import 'gamepad_navigation.dart';
import 'imported_fonts.dart';
import 'layout_breakpoints.dart';
import 'rust_api.dart' as rust;
import 'screens/remote_core_config_screen.dart';
import 'screens/connections_screen.dart';
import 'screens/core_actions_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/diagnostics_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/proxies_screen.dart';
import 'screens/resources_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tailscale_screen.dart';
import 'controller_view_state.dart';
import 'src/rust/frb_generated.dart';
import 'system_accent_color.dart';
import 'utils.dart';
import 'widgets/active_listenable_builder.dart';
import 'widgets/app_background.dart';
import 'widgets/app_page_route.dart';
import 'widgets/bottom_navigation.dart';
import 'widgets/compact_controls.dart';
import 'widgets/desktop_title_bar.dart';
import 'widgets/outbound_mode_card.dart';
import 'widgets/page_body_transition.dart';
import 'widgets/section_panel.dart';
import 'platform_capabilities.dart';
import 'window_state.dart';

part 'app_theme.dart';
part 'home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureImageCache();
  unawaited(AppUpdateCleanup.removePending());
  final appLinks = AppLinks();
  _enableEdgeToEdge();
  // One shared config.json holds controllers, prefs and window geometry.
  final config = await JsonStore.load();
  await BackgroundImageStore.initialize();
  final prefs = await AppPrefs.load(config);
  // Restore the desktop window's saved size / position / maximized state.
  // No-op on mobile and web — `WindowState.bind` short-circuits there.
  final titleBarConfig = _windowTitleBarConfig(prefs.desktopTitleBarMode);
  final windowState = await WindowState.bind(
    config,
    titleBarHidden: titleBarConfig.titleBarHidden,
    windowButtonVisibility: titleBarConfig.windowButtonVisibility,
  );
  await _initRust();
  final systemAccentColor = await SystemAccentColor.load(
    enabled: prefs.automaticColor,
  );
  await ImportedFonts.cleanup(prefs.importedFonts);
  await ImportedFonts.loadAll(prefs.importedFonts);
  await _normalizeBackgroundImages(prefs);
  await config.flush();
  final backgroundImagePath = prefs.backgroundImagePath;
  await BackgroundImageStore.cleanup(prefs.backgroundImagePaths);
  if (prefs.backgroundSource == AppBackgroundSource.image &&
      backgroundImagePath.isNotEmpty) {
    try {
      await BackgroundImageStore.imageSize(backgroundImagePath);
    } catch (_) {
      // Rendering falls back to the configured background color if the saved
      // image is no longer readable.
    }
  }
  final backgroundAccentColor = await BackgroundAccentColor.load(
    enabled: _usesBackgroundAccent(prefs),
    imagePath: backgroundImagePath,
  );
  // Hand the platform's app cache dir to Rust so it can persist proxy
  // icon bytes across launches; failures here are non-fatal — icons just
  // fall back to letter chips when unreachable.
  try {
    final dir = await AppPaths.cacheDir();
    await rust.initCache(
      cacheDir: dir.path,
      allowInsecureOnlineResources: prefs.allowInsecureOnlineResources,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('cache init failed: $e');
  }
  final store = await ControllerStore.load(config);
  final session = ControllerViewState(
    store,
    connectionsIntervalMs: prefs.connectionsRefreshMs,
    closedConnectionsCapacity: prefs.closedConnectionsCapacity,
    logInfoCapacity: prefs.logInfoCapacity,
  );
  var allowInsecureOnlineResources = prefs.allowInsecureOnlineResources;
  var titleBarMode = prefs.desktopTitleBarMode;
  prefs.addListener(() {
    session.setConnectionsInterval(prefs.connectionsRefreshMs);
    session.setClosedConnectionsCapacity(prefs.closedConnectionsCapacity);
    session.setLogInfoCapacity(prefs.logInfoCapacity);
    systemAccentColor.setEnabled(prefs.automaticColor);
    unawaited(
      backgroundAccentColor.update(
        enabled: _usesBackgroundAccent(prefs),
        imagePath: prefs.backgroundImagePath,
      ),
    );
    final nextTitleBarMode = prefs.desktopTitleBarMode;
    if (nextTitleBarMode != titleBarMode) {
      titleBarMode = nextTitleBarMode;
      final titleBarConfig = _windowTitleBarConfig(nextTitleBarMode);
      unawaited(
        windowState?.setTitleBarHidden(
          titleBarConfig.titleBarHidden,
          windowButtonVisibility: titleBarConfig.windowButtonVisibility,
        ),
      );
    }
    final next = prefs.allowInsecureOnlineResources;
    if (next != allowInsecureOnlineResources) {
      allowInsecureOnlineResources = next;
      unawaited(
        rust
            .setOnlineResourceAllowInsecure(allowInsecure: next)
            .catchError((_) {}),
      );
    }
  });
  runApp(
    MihomoControllerApp(
      store: store,
      prefs: prefs,
      session: session,
      systemAccentColor: systemAccentColor,
      backgroundAccentColor: backgroundAccentColor,
      appLinks: appLinks,
    ),
  );
}

({bool titleBarHidden, bool windowButtonVisibility}) _windowTitleBarConfig(
  DesktopTitleBarMode mode,
) {
  final nativeMacButtons =
      isMacOSPlatform && mode == DesktopTitleBarMode.custom;
  return (
    titleBarHidden: mode != DesktopTitleBarMode.system,
    windowButtonVisibility:
        mode == DesktopTitleBarMode.system || nativeMacButtons,
  );
}

Future<void> _normalizeBackgroundImages(AppPrefs prefs) async {
  final backgroundImageReferences = prefs.backgroundImageReferences;
  final selectedIndex = prefs.backgroundImageIndex;
  final normalizedBackgroundImageReferences = <String>[];
  final normalizedIndices = <String, int>{};
  var normalizedSelectedIndex = 0;
  for (var index = 0; index < backgroundImageReferences.length; index++) {
    final reference = backgroundImageReferences[index];
    final normalized = await BackgroundImageStore.normalizeReference(reference);
    if (normalized.isEmpty) continue;
    var normalizedIndex = normalizedIndices[normalized];
    if (normalizedIndex == null) {
      normalizedIndex = normalizedBackgroundImageReferences.length;
      normalizedBackgroundImageReferences.add(normalized);
      normalizedIndices[normalized] = normalizedIndex;
    }
    if (index == selectedIndex) normalizedSelectedIndex = normalizedIndex;
  }
  await prefs.setBackgroundImageReferences(
    normalizedBackgroundImageReferences,
    selectedIndex: normalizedSelectedIndex,
  );
}

void _configureImageCache() {
  if (kIsWeb) return;
  final mobile = Platform.isAndroid || Platform.isIOS;
  // Keep visible backgrounds/icons hot while bounding offscreen image data.
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = mobile ? 512 : 768;
  cache.maximumSizeBytes = (mobile ? 64 : 96) << 20;
}

Future<void> _initRust() {
  return RustLib.init(
    externalLibrary: Platform.isIOS
        ? frb.ExternalLibrary.process(
            iKnowHowToUseIt: true,
            debugInfo: 'Rust core is statically linked into Runner',
          )
        : Platform.isLinux
        ? _linuxBundledRustLibrary()
        : null,
  );
}

frb.ExternalLibrary? _linuxBundledRustLibrary() {
  final executableDir = File(Platform.resolvedExecutable).parent;
  final library = File('${executableDir.path}/lib/libsparxie.so');
  if (!library.existsSync()) return null;
  return frb.ExternalLibrary.open(
    library.path,
    debugInfo: 'Rust core bundled beside Linux runner',
  );
}

void _enableEdgeToEdge() {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

bool _usesBackgroundAccent(AppPrefs prefs) =>
    prefs.automaticColor &&
    prefs.automaticColorSource == AutomaticColorSource.wallpaper &&
    prefs.backgroundSource == AppBackgroundSource.image &&
    prefs.backgroundImagePath.isNotEmpty;

class MihomoControllerApp extends StatefulWidget {
  const MihomoControllerApp({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
    required this.systemAccentColor,
    required this.backgroundAccentColor,
    required this.appLinks,
  });

  final ControllerStore store;
  final AppPrefs prefs;
  final ControllerViewState session;
  final SystemAccentColor systemAccentColor;
  final BackgroundAccentColor backgroundAccentColor;
  final AppLinks appLinks;

  @override
  State<MihomoControllerApp> createState() => _MihomoControllerAppState();
}

@immutable
class _AppVisualSnapshot {
  const _AppVisualSnapshot(this.values);

  final List<Object?> values;

  @override
  bool operator ==(Object other) =>
      other is _AppVisualSnapshot && listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);
}

class _MihomoControllerAppState extends State<MihomoControllerApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _homeShellKey = GlobalKey<_HomeShellState>();
  final _focusNavigatorObserver = DirectionalFocusNavigatorObserver();
  final _navigationInputController = NavigationInputController();
  late final StreamSubscription<NormalizedGamepadEvent> _gamepadEvents;
  late final ControllerUriImporter _controllerUriImporter;
  late final BackgroundRotationController _backgroundRotation;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;
  int? _themeSeed;
  bool? _themeUsesAutomaticColors;
  bool? _themePureBlack;
  bool? _themeShowDividers;
  AppBackgroundSource? _themeBackgroundSource;
  double? _themeSurfaceOpacity;
  AppSurfaceEffect? _themeSurfaceEffect;
  double? _themeSurfaceBlur;
  List<String> _themeFonts = const [];
  List<Object?> _compactStyleKey = const [];
  Map<CompactControlKind, CompactControlStyle> _lightCompactStyles = const {};
  Map<CompactControlKind, CompactControlStyle> _darkCompactStyles = const {};

  ControllerStore get store => widget.store;
  AppPrefs get prefs => widget.prefs;
  ControllerViewState get session => widget.session;
  SystemAccentColor get systemAccentColor => widget.systemAccentColor;
  BackgroundAccentColor get backgroundAccentColor =>
      widget.backgroundAccentColor;

  _AppVisualSnapshot _visualSnapshot() {
    final fonts = prefs.uiFontFamilies;
    return _AppVisualSnapshot(
      List<Object?>.unmodifiable([
        prefs.appThemeMode,
        prefs.globalThemeColor,
        prefs.automaticColor,
        prefs.pureBlackMode,
        prefs.showDividers,
        prefs.backgroundSource,
        prefs.backgroundImagePath,
        prefs.backgroundFit,
        prefs.backgroundFocalX,
        prefs.backgroundFocalY,
        prefs.backgroundZoom,
        prefs.surfaceOpacity,
        prefs.surfaceEffect,
        prefs.surfaceBlur,
        prefs.desktopTitleBarMode,
        systemAccentColor.color,
        backgroundAccentColor.color,
        fonts.length,
        ...fonts,
        for (final kind in CompactControlKind.values) ...[
          prefs.compactBorderRadius(kind),
          prefs.compactControlHeight(kind),
          prefs.compactWidthScale(kind),
          prefs.effectiveCompactThemeColor(kind),
        ],
        prefs.navigationInnerThemeColor,
        prefs.navigationInnerBorderRadius,
        prefs.navigationInnerHeight,
        prefs.navigationInnerWidthScale,
        prefs.navigationFloatingHeightOffset,
      ]),
    );
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _gamepadEvents = Gamepads.normalizedEvents.listen(
      _handleGamepadEvent,
      onError: (_) {},
    );
    _controllerUriImporter = ControllerUriImporter(
      widget.appLinks,
      store: store,
      navigatorKey: _navigatorKey,
    )..start();
    _backgroundRotation = BackgroundRotationController(prefs)..start();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    unawaited(_gamepadEvents.cancel());
    _navigationInputController.dispose();
    _controllerUriImporter.dispose();
    _backgroundRotation.dispose();
    super.dispose();
  }

  bool _requestBackNavigation() {
    if (_homeShellKey.currentState?._returnToPrimaryNavigation() ?? false) {
      return true;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    unawaited(navigator.maybePop());
    return true;
  }

  bool _handleGamepadIntent(GamepadActivator _, Intent intent) {
    activateDirectionalNavigation();
    if (intent is GamepadDirectionalFocusIntent) {
      _moveFocus(intent.direction, allowFromEditable: true);
      return false;
    }
    if (intent is SwitchPageIntent) {
      _homeShellKey.currentState?._switchNavigation(intent.delta);
      return false;
    }
    if (intent is DismissIntent &&
        (_dismissTextInput() || _requestBackNavigation())) {
      return false;
    }
    return true;
  }

  void _handleGamepadEvent(NormalizedGamepadEvent event) {
    final button = event.button;
    if (button == GamepadButton.a) {
      final source = (event.gamepadId, button);
      if (event.value == 0) {
        _navigationInputController.release(source);
      } else {
        activateDirectionalNavigation();
        _navigationInputController.press(source);
      }
      return;
    }

    final axis = event.axis;
    if (axis != GamepadAxis.rightStickX && axis != GamepadAxis.rightStickY) {
      return;
    }
    final value =
        axis == GamepadAxis.rightStickY &&
            defaultTargetPlatform == TargetPlatform.android
        ? -event.value
        : event.value;
    if (value.abs() > 0.16) activateDirectionalNavigation();
    _navigationInputController.updateScrollAxis(
      horizontal: axis == GamepadAxis.rightStickX ? value : null,
      vertical: axis == GamepadAxis.rightStickY ? value : null,
    );
  }

  bool _handleActivationKey(KeyEvent event) {
    final key = event.logicalKey;
    final activationKey =
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.gameButton1 ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!activationKey ||
        (_isEditableTextFocused() &&
            (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter))) {
      return false;
    }

    final source = event.physicalKey;
    if (event is KeyUpEvent) {
      _navigationInputController.release(source);
    } else if (event is KeyDownEvent) {
      activateDirectionalNavigation();
      _navigationInputController.press(source);
    }
    return true;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_handleActivationKey(event)) return true;
    final action = gamepadNavigationActionFor(event.logicalKey);
    if (action == GamepadNavigationAction.back ||
        event.physicalKey == PhysicalKeyboardKey.browserBack) {
      if (event is! KeyDownEvent) return false;
      return _dismissTextInput() || _requestBackNavigation();
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      activateDirectionalNavigation();
      return false;
    }
    if (action == GamepadNavigationAction.previousPage ||
        action == GamepadNavigationAction.nextPage) {
      if (event is! KeyDownEvent) return true;
      activateDirectionalNavigation();
      _homeShellKey.currentState?._switchNavigation(
        action == GamepadNavigationAction.previousPage ? -1 : 1,
      );
      return true;
    }
    final direction = switch (action) {
      GamepadNavigationAction.up => TraversalDirection.up,
      GamepadNavigationAction.down => TraversalDirection.down,
      GamepadNavigationAction.left => TraversalDirection.left,
      GamepadNavigationAction.right => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return false;
    activateDirectionalNavigation();
    if (_isSliderFocused() &&
        (direction == TraversalDirection.left ||
            direction == TraversalDirection.right)) {
      return false;
    }
    _moveFocus(direction, allowFromEditable: _usesDirectionalNavigation());
    return true;
  }

  bool _moveFocus(
    TraversalDirection direction, {
    bool allowFromEditable = false,
  }) {
    if (!allowFromEditable && _isEditableTextFocused()) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus == FocusManager.instance.rootScope) {
      return _focusFirst();
    }
    return focus.focusInDirection(direction) ||
        (_homeShellKey.currentState?._handleFocusBoundary(direction) ?? false);
  }

  bool _isEditableTextFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _isSliderFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is Slider ||
        context?.findAncestorWidgetOfExactType<Slider>() != null;
  }

  bool _usesDirectionalNavigation() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional;
  }

  bool _dismissTextInput() {
    if (!_isEditableTextFocused()) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    return true;
  }

  bool _focusFirst() {
    final context = _navigatorKey.currentContext;
    if (context == null) return false;
    return FocusScope.of(context).nextFocus();
  }

  void _handlePointerDown(PointerDownEvent event) {
    deactivateDirectionalNavigation();
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kBackMouseButton != 0) {
      _requestBackNavigation();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _lightTheme = null;
    _darkTheme = null;
    _compactStyleKey = const [];
  }

  void _ensureThemes({
    required Color seedColor,
    required List<String> userFonts,
    required bool useAutomaticColors,
    required bool pureBlack,
    required bool showDividers,
    required AppBackgroundSource backgroundSource,
    required double surfaceOpacity,
    required AppSurfaceEffect surfaceEffect,
    required double surfaceBlur,
  }) {
    final seed = seedColor.toARGB32();
    if (_lightTheme != null &&
        _themeSeed == seed &&
        _themeUsesAutomaticColors == useAutomaticColors &&
        _themePureBlack == pureBlack &&
        _themeShowDividers == showDividers &&
        _themeBackgroundSource == backgroundSource &&
        _themeSurfaceOpacity == surfaceOpacity &&
        _themeSurfaceEffect == surfaceEffect &&
        _themeSurfaceBlur == surfaceBlur &&
        listEquals(_themeFonts, userFonts)) {
      return;
    }
    _themeSeed = seed;
    _themeUsesAutomaticColors = useAutomaticColors;
    _themePureBlack = pureBlack;
    _themeShowDividers = showDividers;
    _themeBackgroundSource = backgroundSource;
    _themeSurfaceOpacity = surfaceOpacity;
    _themeSurfaceEffect = surfaceEffect;
    _themeSurfaceBlur = surfaceBlur;
    _themeFonts = List.unmodifiable(userFonts);
    _lightTheme = _appTheme(
      brightness: Brightness.light,
      seedColor: seedColor,
      userFonts: userFonts,
      useAutomaticColors: useAutomaticColors,
      pureBlack: false,
      showDividers: showDividers,
      backgroundSource: backgroundSource,
      surfaceOpacity: surfaceOpacity,
      surfaceEffect: surfaceEffect,
      surfaceBlur: surfaceBlur,
    );
    _darkTheme = _appTheme(
      brightness: Brightness.dark,
      seedColor: seedColor,
      userFonts: userFonts,
      useAutomaticColors: useAutomaticColors,
      pureBlack: pureBlack,
      showDividers: showDividers,
      backgroundSource: backgroundSource,
      surfaceOpacity: surfaceOpacity,
      surfaceEffect: surfaceEffect,
      surfaceBlur: surfaceBlur,
    );
  }

  void _ensureCompactStyles({
    required bool useAutomaticColor,
    required AppBackgroundSource backgroundSource,
    required double surfaceOpacity,
  }) {
    final key = <Object?>[
      useAutomaticColor,
      backgroundSource,
      surfaceOpacity,
      _lightTheme!.colorScheme,
      _darkTheme!.colorScheme,
      for (final kind in CompactControlKind.values) ...[
        prefs.compactBorderRadius(kind),
        prefs.compactControlHeight(kind),
        prefs.compactWidthScale(kind),
        prefs.effectiveCompactThemeColor(kind),
      ],
      prefs.navigationInnerThemeColor,
      prefs.navigationInnerBorderRadius,
      prefs.navigationInnerHeight,
      prefs.navigationInnerWidthScale,
      prefs.navigationFloatingHeightOffset,
    ];
    if (listEquals(_compactStyleKey, key)) return;
    _compactStyleKey = List.unmodifiable(key);
    _lightCompactStyles = _buildCompactStyles(
      brightness: Brightness.light,
      colorScheme: _lightTheme!.colorScheme,
      useAutomaticColor: useAutomaticColor,
      backgroundSource: backgroundSource,
      surfaceOpacity: surfaceOpacity,
    );
    _darkCompactStyles = _buildCompactStyles(
      brightness: Brightness.dark,
      colorScheme: _darkTheme!.colorScheme,
      useAutomaticColor: useAutomaticColor,
      backgroundSource: backgroundSource,
      surfaceOpacity: surfaceOpacity,
    );
  }

  Map<CompactControlKind, CompactControlStyle> _buildCompactStyles({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required bool useAutomaticColor,
    required AppBackgroundSource backgroundSource,
    required double surfaceOpacity,
  }) {
    return Map.unmodifiable({
      for (final kind in CompactControlKind.values)
        kind: _buildCompactStyle(
          kind: kind,
          brightness: brightness,
          colorScheme: colorScheme,
          useAutomaticColor: useAutomaticColor,
          backgroundSource: backgroundSource,
          surfaceOpacity: surfaceOpacity,
        ),
    });
  }

  CompactControlStyle _buildCompactStyle({
    required CompactControlKind kind,
    required Brightness brightness,
    required ColorScheme colorScheme,
    required bool useAutomaticColor,
    required AppBackgroundSource backgroundSource,
    required double surfaceOpacity,
  }) {
    final radius = prefs.compactBorderRadius(kind);
    final height = prefs.compactControlHeight(kind);
    final widthScale = prefs.compactWidthScale(kind);
    final navigationBar = kind == CompactControlKind.navigationBar;
    final innerRadius = navigationBar
        ? prefs.navigationInnerBorderRadius
        : null;
    final innerHeight = navigationBar ? prefs.navigationInnerHeight : height;
    final innerWidthScale = navigationBar
        ? prefs.navigationInnerWidthScale
        : widthScale;
    final style = useAutomaticColor
        ? CompactControlStyle.fromColorScheme(
            colorScheme: colorScheme,
            borderRadius: radius,
            controlHeight: height,
            widthScale: widthScale,
            indicatorBorderRadius: innerRadius,
            indicatorHeight: innerHeight,
            indicatorWidthScale: innerWidthScale,
            floatingHeightOffset: prefs.navigationFloatingHeightOffset,
          )
        : CompactControlStyle.fromSeed(
            seedColor: Color(prefs.effectiveCompactThemeColor(kind)),
            selectedSeedColor: navigationBar
                ? Color(prefs.navigationInnerThemeColor)
                : null,
            brightness: brightness,
            borderRadius: radius,
            controlHeight: height,
            widthScale: widthScale,
            indicatorBorderRadius: innerRadius,
            indicatorHeight: innerHeight,
            indicatorWidthScale: innerWidthScale,
            floatingHeightOffset: prefs.navigationFloatingHeightOffset,
          );
    if (navigationBar || backgroundSource == AppBackgroundSource.theme) {
      return style;
    }
    return style.withSurfaceOpacity(surfaceOpacity);
  }

  @override
  Widget build(BuildContext context) {
    return ActiveListenableSelector<_AppVisualSnapshot>(
      listenable: Listenable.merge([
        prefs,
        systemAccentColor,
        backgroundAccentColor,
      ]),
      selector: _visualSnapshot,
      builder: (context, _, _) {
        final uiFonts = prefs.uiFontFamilies;
        final globalSeed = Color(prefs.globalThemeColor);
        final useAutomaticColor = prefs.automaticColor;
        final backgroundSource = prefs.backgroundSource;
        final automaticSeed = _usesBackgroundAccent(prefs)
            ? backgroundAccentColor.color ?? systemAccentColor.color
            : systemAccentColor.color;
        final effectiveSeed = useAutomaticColor
            ? automaticSeed ?? const Color(AppPrefs.defaultGlobalThemeColor)
            : globalSeed;
        final surfaceOpacity = prefs.surfaceOpacity;
        final surfaceEffect = prefs.surfaceEffect;
        final surfaceBlur = prefs.surfaceBlur;
        _ensureThemes(
          seedColor: effectiveSeed,
          userFonts: uiFonts,
          useAutomaticColors: useAutomaticColor,
          pureBlack: prefs.pureBlackMode,
          showDividers: prefs.showDividers,
          backgroundSource: backgroundSource,
          surfaceOpacity: surfaceOpacity,
          surfaceEffect: surfaceEffect,
          surfaceBlur: surfaceBlur,
        );
        _ensureCompactStyles(
          useAutomaticColor: useAutomaticColor,
          backgroundSource: backgroundSource,
          surfaceOpacity: surfaceOpacity,
        );
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Sparxie',
          scrollBehavior: const _AppScrollBehavior(),
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN')],
          // Interpolating ThemeData rebuilds every retained page on each frame.
          // Swap once and leave motion to the lightweight local controls.
          themeAnimationDuration: Duration.zero,
          themeMode: switch (prefs.appThemeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: _lightTheme!,
          darkTheme: _darkTheme!,
          navigatorObservers: [_focusNavigatorObserver],
          builder: (context, child) {
            final compactStyles =
                Theme.of(context).brightness == Brightness.dark
                ? _darkCompactStyles
                : _lightCompactStyles;

            final appFrame = AppBackgroundFrame(
              source: prefs.backgroundSource,
              imagePath: prefs.backgroundImagePath,
              fit: prefs.backgroundFit,
              focalPoint: Alignment(
                prefs.backgroundFocalX,
                prefs.backgroundFocalY,
              ),
              zoom: prefs.backgroundZoom,
              child: DesktopTitleBarFrame(
                showTitleBar:
                    prefs.desktopTitleBarMode == DesktopTitleBarMode.custom,
                enableContentDragging:
                    prefs.desktopTitleBarMode != DesktopTitleBarMode.system,
                child: _ThemeModeTransition(
                  brightness: Theme.of(context).brightness,
                  surfaceColor: Theme.of(context).colorScheme.surface,
                  child: CompactControlTheme(
                    buttonStyle: compactStyles[CompactControlKind.button]!,
                    searchStyle: compactStyles[CompactControlKind.search]!,
                    segmentedStyle:
                        compactStyles[CompactControlKind.segmented]!,
                    switchStyle: compactStyles[CompactControlKind.toggle]!,
                    navigationBarStyle:
                        compactStyles[CompactControlKind.navigationBar]!,
                    child: _SystemBarStyle(
                      child: UiScrollActivityScope(
                        child: GamepadControl(
                          onBeforeIntent: _handleGamepadIntent,
                          shortcuts: gamepadShortcuts,
                          repeatIntents: gamepadRepeatIntents,
                          child: FocusTraversalGroup(
                            child: child ?? const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              child: appFrame,
            );
          },
          onGenerateRoute: (settings) {
            if (settings.name != Navigator.defaultRouteName) return null;
            return AppPageRoute<void>(
              settings: settings,
              builder: (_) => _DeferredRouteTheme(
                child: HomeShell(
                  key: _homeShellKey,
                  store: store,
                  prefs: prefs,
                  session: session,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
