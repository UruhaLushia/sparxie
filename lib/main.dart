import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;

import 'app_paths.dart';
import 'app_prefs.dart';
import 'app_update_cleanup.dart';
import 'background_accent_color.dart';
import 'background_image_store.dart';
import 'config_store.dart';
import 'controller.dart';
import 'controller_uri_import.dart';
import 'imported_fonts.dart';
import 'rust_api.dart' as rust;
import 'screens/core_config_screen.dart';
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
import 'session.dart';
import 'src/rust/frb_generated.dart';
import 'system_accent_color.dart';
import 'utils.dart';
import 'widgets/app_background.dart';
import 'widgets/app_page_route.dart';
import 'widgets/bottom_navigation.dart';
import 'widgets/compact_controls.dart';
import 'widgets/desktop_title_bar.dart';
import 'widgets/outbound_mode_card.dart';
import 'widgets/page_body_transition.dart';
import 'widgets/section_panel.dart';
import 'window_state.dart';

part 'app_theme.dart';
part 'home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(AppUpdateCleanup.removePending());
  final appLinks = AppLinks();
  _enableEdgeToEdge();
  // One shared config.json holds controllers, prefs and window geometry.
  final config = await JsonStore.load();
  await BackgroundImageStore.initialize();
  final prefs = await AppPrefs.load(config);
  // Restore the desktop window's saved size / position / maximized state.
  // No-op on mobile and web — `WindowState.bind` short-circuits there.
  final windowState = await WindowState.bind(
    config,
    titleBarHidden: prefs.desktopTitleBarMode != DesktopTitleBarMode.system,
  );
  await _initRust();
  final systemAccentColor = await SystemAccentColor.load(
    enabled: prefs.automaticColor,
  );
  await ImportedFonts.cleanup(prefs.importedFonts);
  await ImportedFonts.loadAll(prefs.importedFonts);
  final backgroundImageReference = prefs.backgroundImageReference;
  final normalizedBackgroundImageReference =
      await BackgroundImageStore.normalizeReference(backgroundImageReference);
  if (normalizedBackgroundImageReference != backgroundImageReference) {
    await prefs.setBackgroundImageReference(normalizedBackgroundImageReference);
    await config.flush();
  }
  final backgroundImagePath = prefs.backgroundImagePath;
  await BackgroundImageStore.cleanup(backgroundImagePath);
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
  final session = MihomoSession(
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
      unawaited(
        windowState?.setTitleBarHidden(
          nextTitleBarMode != DesktopTitleBarMode.system,
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
  final MihomoSession session;
  final SystemAccentColor systemAccentColor;
  final BackgroundAccentColor backgroundAccentColor;
  final AppLinks appLinks;

  @override
  State<MihomoControllerApp> createState() => _MihomoControllerAppState();
}

class _MihomoControllerAppState extends State<MihomoControllerApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ControllerUriImporter _controllerUriImporter;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;
  int? _themeSeed;
  bool? _themeUsesAutomaticColors;
  bool? _themePureBlack;
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
  MihomoSession get session => widget.session;
  SystemAccentColor get systemAccentColor => widget.systemAccentColor;
  BackgroundAccentColor get backgroundAccentColor =>
      widget.backgroundAccentColor;

  @override
  void initState() {
    super.initState();
    _controllerUriImporter = ControllerUriImporter(
      widget.appLinks,
      store: store,
      navigatorKey: _navigatorKey,
    )..start();
  }

  @override
  void dispose() {
    _controllerUriImporter.dispose();
    super.dispose();
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
    return ListenableBuilder(
      listenable: Listenable.merge([
        prefs,
        systemAccentColor,
        backgroundAccentColor,
      ]),
      builder: (context, _) {
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
          builder: (context, child) {
            final compactStyles =
                Theme.of(context).brightness == Brightness.dark
                ? _darkCompactStyles
                : _lightCompactStyles;

            return AppBackgroundFrame(
              source: prefs.backgroundSource,
              color: Color(prefs.backgroundColor),
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
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            );
          },
          onGenerateRoute: (settings) {
            if (settings.name != Navigator.defaultRouteName) return null;
            return AppPageRoute<void>(
              settings: settings,
              builder: (_) => _DeferredRouteTheme(
                child: HomeShell(store: store, prefs: prefs, session: session),
              ),
            );
          },
        );
      },
    );
  }
}
