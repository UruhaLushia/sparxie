import 'dart:async';
import 'dart:io' show File, Platform;

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
import 'background_image_store.dart';
import 'config_store.dart';
import 'controller.dart';
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
import 'window_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _enableEdgeToEdge();
  // One shared config.json holds controllers, prefs and window geometry.
  final config = await JsonStore.load();
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
  await BackgroundImageStore.cleanup(prefs.backgroundImagePath);
  if (prefs.backgroundSource == AppBackgroundSource.image &&
      prefs.backgroundImagePath.isNotEmpty) {
    try {
      await BackgroundImageStore.imageSize(prefs.backgroundImagePath);
    } catch (_) {
      // Rendering falls back to the configured background color if the saved
      // image is no longer readable.
    }
  }
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
  final session = MihomoSession(store)
    ..setConnectionsInterval(prefs.connectionsRefreshMs);
  var allowInsecureOnlineResources = prefs.allowInsecureOnlineResources;
  var titleBarMode = prefs.desktopTitleBarMode;
  prefs.addListener(() {
    session.setConnectionsInterval(prefs.connectionsRefreshMs);
    systemAccentColor.setEnabled(prefs.automaticColor);
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

class _SystemBarStyle extends StatelessWidget {
  const _SystemBarStyle({required this.child});

  final Widget child;

  static const double _buttonNavThreshold = 40;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return child;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;
    final isButtonNav =
        MediaQuery.viewPaddingOf(context).bottom >= _buttonNavThreshold;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: scheme.brightness,
        systemNavigationBarColor: isButtonNav
            ? scheme.surface
            : Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}

/// Material 3's Android stretch effect transforms the scrollable subtree.
/// Backdrop filters inside that subtree can lose their sampled backdrop until
/// the overscroll gesture ends, so keep Android's normal clamping without the
/// visual stretch. Other platforms retain their native overscroll behavior.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (getPlatform(context) == TargetPlatform.android) return child;
    return super.buildOverscrollIndicator(context, child, details);
  }
}

ThemeData _appTheme({
  required Brightness brightness,
  required Color seedColor,
  required List<String> userFonts,
  required bool useAutomaticColors,
  required bool pureBlack,
  required AppBackgroundSource backgroundSource,
  required double surfaceOpacity,
  required AppSurfaceEffect surfaceEffect,
  required double surfaceBlur,
}) {
  var scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  scheme = _applyThemeColorCoverage(
    scheme,
    seedColor,
    preserveSeedPrimary: !useAutomaticColors,
  );
  if (pureBlack && brightness == Brightness.dark) {
    scheme = _pureBlackScheme(scheme);
  }
  final customBackground = backgroundSource != AppBackgroundSource.theme;
  final surfaceTheme = AppSurfaceTheme(
    enabled: customBackground,
    effect: surfaceEffect,
    blurSigma: surfaceBlur,
    opacity: surfaceOpacity,
    tintColor: seedColor,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: surfaceTheme.pageColor(scheme.surface),
    canvasColor: surfaceTheme.surfaceColor(scheme.surface),
    cardColor: surfaceTheme.surfaceColor(scheme.surfaceContainerLow),
    dividerColor: surfaceTheme.outlineColor(scheme.outlineVariant),
    focusColor: scheme.primary.withValues(alpha: 0.12),
    hoverColor: scheme.primary.withValues(alpha: 0.06),
    highlightColor: scheme.primary.withValues(alpha: 0.08),
    splashColor: scheme.primary.withValues(alpha: 0.1),
    appBarTheme: AppBarThemeData(
      backgroundColor: surfaceTheme.chromeColor(scheme.surface),
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceTheme.surfaceColor(scheme.surfaceContainerHigh),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaceTheme.surfaceColor(scheme.surfaceContainerLow),
      modalBackgroundColor: surfaceTheme.surfaceColor(
        scheme.surfaceContainerLow,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaceTheme.surfaceColor(scheme.surfaceContainerHigh),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AppHorizontalPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: AppHorizontalPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: AppHorizontalPageTransitionsBuilder(),
      },
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surfaceTheme.surfaceColor(scheme.surface),
    ),
    extensions: [surfaceTheme],
  );
  return _applyFontSet(base, userFonts);
}

ColorScheme _applyThemeColorCoverage(
  ColorScheme scheme,
  Color seedColor, {
  required bool preserveSeedPrimary,
}) {
  final dark = scheme.brightness == Brightness.dark;
  final neutral = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: scheme.brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  Color tint(Color base, double lightOpacity, double darkOpacity) =>
      Color.alphaBlend(
        seedColor.withValues(alpha: dark ? darkOpacity : lightOpacity),
        base,
      );
  final onSeed =
      ThemeData.estimateBrightnessForColor(seedColor) == Brightness.dark
      ? Colors.white
      : Colors.black;
  final surface = dark ? neutral.surface : Colors.white;
  final surfaceDim = dark ? tint(neutral.surfaceDim, 0, 0.015) : Colors.white;
  final surfaceBright = dark ? neutral.surfaceBright : Colors.white;
  final surfaceContainerLowest = dark
      ? neutral.surfaceContainerLowest
      : Colors.white;
  final surfaceContainerLow = dark
      ? tint(neutral.surfaceContainerLow, 0, 0.015)
      : tint(Colors.white, 0.01, 0);
  final surfaceContainer = dark
      ? tint(neutral.surfaceContainer, 0, 0.025)
      : tint(Colors.white, 0.025, 0);
  final surfaceContainerHigh = dark
      ? tint(neutral.surfaceContainerHigh, 0, 0.04)
      : tint(Colors.white, 0.04, 0);
  final surfaceContainerHighest = dark
      ? tint(neutral.surfaceContainerHighest, 0, 0.055)
      : tint(Colors.white, 0.06, 0);
  return scheme.copyWith(
    primary: preserveSeedPrimary ? seedColor : scheme.primary,
    onPrimary: preserveSeedPrimary ? onSeed : scheme.onPrimary,
    secondaryContainer: tint(scheme.secondaryContainer, 0.03, 0.05),
    tertiaryContainer: tint(scheme.tertiaryContainer, 0.02, 0.03),
    surface: surface,
    onSurface: neutral.onSurface,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    onSurfaceVariant: neutral.onSurfaceVariant,
    outline: tint(neutral.outline, 0.03, 0.03),
    outlineVariant: tint(neutral.outlineVariant, 0.06, 0.045),
    inverseSurface: neutral.inverseSurface,
    onInverseSurface: neutral.onInverseSurface,
    surfaceTint: seedColor,
  );
}

ColorScheme _pureBlackScheme(ColorScheme scheme) => scheme.copyWith(
  surface: Colors.black,
  surfaceDim: Colors.black,
  surfaceBright: const Color(0xff1c1c1c),
  surfaceContainerLowest: Colors.black,
  surfaceContainerLow: const Color(0xff050505),
  surfaceContainer: const Color(0xff0a0a0a),
  surfaceContainerHigh: const Color(0xff101010),
  surfaceContainerHighest: const Color(0xff181818),
);

ThemeData _applyFontSet(ThemeData base, List<String> userFonts) {
  if (userFonts.isEmpty) return base;
  return base.copyWith(
    textTheme: _applyTextThemeFontSet(base.textTheme, userFonts),
    primaryTextTheme: _applyTextThemeFontSet(base.primaryTextTheme, userFonts),
  );
}

TextTheme _applyTextThemeFontSet(TextTheme theme, List<String> userFonts) {
  return theme.copyWith(
    displayLarge: _applyTextStyleFontSet(theme.displayLarge, userFonts),
    displayMedium: _applyTextStyleFontSet(theme.displayMedium, userFonts),
    displaySmall: _applyTextStyleFontSet(theme.displaySmall, userFonts),
    headlineLarge: _applyTextStyleFontSet(theme.headlineLarge, userFonts),
    headlineMedium: _applyTextStyleFontSet(theme.headlineMedium, userFonts),
    headlineSmall: _applyTextStyleFontSet(theme.headlineSmall, userFonts),
    titleLarge: _applyTextStyleFontSet(theme.titleLarge, userFonts),
    titleMedium: _applyTextStyleFontSet(theme.titleMedium, userFonts),
    titleSmall: _applyTextStyleFontSet(theme.titleSmall, userFonts),
    bodyLarge: _applyTextStyleFontSet(theme.bodyLarge, userFonts),
    bodyMedium: _applyTextStyleFontSet(theme.bodyMedium, userFonts),
    bodySmall: _applyTextStyleFontSet(theme.bodySmall, userFonts),
    labelLarge: _applyTextStyleFontSet(theme.labelLarge, userFonts),
    labelMedium: _applyTextStyleFontSet(theme.labelMedium, userFonts),
    labelSmall: _applyTextStyleFontSet(theme.labelSmall, userFonts),
  );
}

TextStyle? _applyTextStyleFontSet(TextStyle? style, List<String> userFonts) {
  if (style == null) return null;
  final chain = <String>[];
  for (final family in userFonts) {
    if (family == AppPrefs.systemFontFamily) {
      _addSystemFontChain(chain, style);
    } else {
      _addFont(chain, family);
    }
  }
  if (chain.isEmpty) return style;
  final fallback = chain.skip(1).toList();
  return style.copyWith(
    fontFamily: chain.first,
    fontFamilyFallback: fallback.isEmpty ? null : fallback,
  );
}

void _addSystemFontChain(List<String> out, TextStyle style) {
  final family = style.fontFamily;
  if (family != null) _addFont(out, family);
  for (final family in style.fontFamilyFallback ?? const <String>[]) {
    _addFont(out, family);
  }
}

void _addFont(List<String> out, String family) {
  if (!out.contains(family)) out.add(family);
}

class MihomoControllerApp extends StatefulWidget {
  const MihomoControllerApp({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
    required this.systemAccentColor,
  });

  final ControllerStore store;
  final AppPrefs prefs;
  final MihomoSession session;
  final SystemAccentColor systemAccentColor;

  @override
  State<MihomoControllerApp> createState() => _MihomoControllerAppState();
}

class _MihomoControllerAppState extends State<MihomoControllerApp> {
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

  ControllerStore get store => widget.store;
  AppPrefs get prefs => widget.prefs;
  MihomoSession get session => widget.session;
  SystemAccentColor get systemAccentColor => widget.systemAccentColor;

  @override
  void reassemble() {
    super.reassemble();
    _lightTheme = null;
    _darkTheme = null;
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, systemAccentColor]),
      builder: (context, _) {
        final uiFonts = prefs.uiFontFamilies;
        final globalSeed = Color(prefs.globalThemeColor);
        final useAutomaticColor = prefs.automaticColor;
        final effectiveSeed = useAutomaticColor
            ? systemAccentColor.color ??
                  const Color(AppPrefs.defaultGlobalThemeColor)
            : globalSeed;
        final backgroundSource = prefs.backgroundSource;
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
        return MaterialApp(
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
          themeMode: switch (prefs.appThemeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: _lightTheme!,
          darkTheme: _darkTheme!,
          builder: (context, child) {
            CompactControlStyle styleFor(CompactControlKind kind) {
              final radius = prefs.compactBorderRadius(kind);
              final height = prefs.compactControlHeight(kind);
              final widthScale = prefs.compactWidthScale(kind);
              final navigationBar = kind == CompactControlKind.navigationBar;
              final innerRadius = navigationBar
                  ? prefs.navigationInnerBorderRadius
                  : radius;
              final innerHeight = navigationBar
                  ? prefs.navigationInnerHeight
                  : height;
              final innerWidthScale = navigationBar
                  ? prefs.navigationInnerWidthScale
                  : widthScale;
              final style = useAutomaticColor
                  ? CompactControlStyle.fromColorScheme(
                      colorScheme: Theme.of(context).colorScheme,
                      borderRadius: radius,
                      controlHeight: height,
                      widthScale: widthScale,
                      indicatorBorderRadius: innerRadius,
                      indicatorHeight: innerHeight,
                      indicatorWidthScale: innerWidthScale,
                      floatingHeightOffset:
                          prefs.navigationFloatingHeightOffset,
                    )
                  : CompactControlStyle.fromSeed(
                      seedColor: Color(prefs.effectiveCompactThemeColor(kind)),
                      selectedSeedColor: navigationBar
                          ? Color(prefs.navigationInnerThemeColor)
                          : null,
                      brightness: Theme.of(context).brightness,
                      borderRadius: radius,
                      controlHeight: height,
                      widthScale: widthScale,
                      indicatorBorderRadius: innerRadius,
                      indicatorHeight: innerHeight,
                      indicatorWidthScale: innerWidthScale,
                      floatingHeightOffset:
                          prefs.navigationFloatingHeightOffset,
                    );
              if (navigationBar ||
                  prefs.backgroundSource == AppBackgroundSource.theme) {
                return style;
              }
              return style.withSurfaceOpacity(prefs.surfaceOpacity);
            }

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
                child: CompactControlTheme(
                  buttonStyle: styleFor(CompactControlKind.button),
                  searchStyle: styleFor(CompactControlKind.search),
                  segmentedStyle: styleFor(CompactControlKind.segmented),
                  switchStyle: styleFor(CompactControlKind.toggle),
                  navigationBarStyle: styleFor(
                    CompactControlKind.navigationBar,
                  ),
                  child: _SystemBarStyle(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
          onGenerateRoute: (settings) {
            if (settings.name != Navigator.defaultRouteName) return null;
            return AppPageRoute<void>(
              settings: settings,
              builder: (_) =>
                  HomeShell(store: store, prefs: prefs, session: session),
            );
          },
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
  });

  final ControllerStore store;
  final AppPrefs prefs;
  final MihomoSession session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  // Only mobile OSes silently sever backgrounded sockets; reconnecting on
  // every desktop minimize/restore would be churn for no reason.
  static bool get _needsResumeReconnect {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (_needsResumeReconnect) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    if (_needsResumeReconnect) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.session.reconnect();
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      final nav = Navigator.maybeOf(context);
      if (nav != null && nav.canPop()) {
        nav.pop();
        return true;
      }
    }
    return false;
  }

  AppSurfaceTheme _navigationSurfaceTheme(BuildContext context) {
    final prefs = widget.prefs;
    final global = AppSurfaceTheme.of(context);
    if (prefs.navigationSurfaceFollowsGlobal) return global;
    final effect = prefs.navigationSurfaceEffect;
    return global.copyWith(
      enabled: true,
      effect: effect,
      blurSigma: prefs.navigationSurfaceBlur,
      opacity: prefs.navigationSurfaceOpacity,
      tintColor: Theme.of(context).colorScheme.primary,
      blurScale: effect == AppSurfaceEffect.acrylic
          ? AppSurfaceTheme.compactAcrylicBlurScale
          : 1,
      acrylicVeil: effect == AppSurfaceEffect.acrylic
          ? AppSurfaceTheme.compactAcrylicVeil
          : 0.18,
    );
  }

  List<AppNavDestination> _destinationsFor(
    NavLayout layout, {
    required bool isCompact,
    required bool supportsCoreConfig,
    required bool supportsCoreActions,
    required bool supportsExternalResources,
    required bool supportsRules,
    required bool supportsTailscale,
    required bool supportsDiagnostics,
  }) {
    final isStandardLike =
        layout == NavLayout.standard || layout == NavLayout.floating;
    final showOnStandardWide = isStandardLike && !isCompact;
    return [
      if (isStandardLike)
        const AppNavDestination(
          icon: Icons.space_dashboard_outlined,
          label: '概览',
        ),
      const AppNavDestination(icon: Icons.account_tree_outlined, label: '代理组'),
      if (isStandardLike)
        const AppNavDestination(icon: Icons.lan_outlined, label: '连接'),
      if (showOnStandardWide && supportsCoreConfig)
        const AppNavDestination(icon: Icons.memory_outlined, label: '核心配置'),
      const AppNavDestination(icon: Icons.terminal, label: '日志'),
      if (showOnStandardWide && supportsExternalResources)
        const AppNavDestination(icon: Icons.cloud_outlined, label: '外部资源'),
      if (showOnStandardWide && supportsCoreActions)
        const AppNavDestination(icon: Icons.build_outlined, label: '核心操作'),
      if (showOnStandardWide && supportsRules)
        const AppNavDestination(icon: Icons.rule, label: '分流规则'),
      if (showOnStandardWide && supportsTailscale)
        const AppNavDestination(
          icon: Icons.vpn_lock_outlined,
          label: 'Tailscale',
        ),
      if (showOnStandardWide && supportsDiagnostics)
        const AppNavDestination(
          icon: Icons.network_check_outlined,
          label: '网络工具',
        ),
      if (layout == NavLayout.cards && supportsExternalResources)
        const AppNavDestination(icon: Icons.cloud_outlined, label: '外部资源'),
      if (layout == NavLayout.cards && supportsTailscale)
        const AppNavDestination(
          icon: Icons.vpn_lock_outlined,
          label: 'Tailscale',
        ),
      if (layout == NavLayout.cards && supportsDiagnostics)
        const AppNavDestination(
          icon: Icons.network_check_outlined,
          label: '网络工具',
        ),
      const AppNavDestination(icon: Icons.more_horiz, label: '更多'),
    ];
  }

  Widget _buildPage(AppNavDestination dest) {
    return switch (dest.label) {
      '概览' => DashboardScreen(store: widget.store, session: widget.session),
      '代理组' => ProxiesScreen(
        store: widget.store,
        session: widget.session,
        prefs: widget.prefs,
      ),
      '连接' => ConnectionsScreen(
        store: widget.store,
        prefs: widget.prefs,
        session: widget.session,
      ),
      '核心配置' => CoreConfigScreen(store: widget.store, prefs: widget.prefs),
      '外部资源' => ResourcesScreen(store: widget.store),
      '日志' => LogsScreen(store: widget.store, session: widget.session),
      '核心操作' => CoreActionsScreen(store: widget.store, session: widget.session),
      '分流规则' => RulesScreen(store: widget.store),
      'Tailscale' => TailscaleScreen(store: widget.store),
      '网络工具' => DiagnosticsScreen(store: widget.store),
      _ => SettingsScreen(
        store: widget.store,
        prefs: widget.prefs,
        session: widget.session,
      ),
    };
  }

  // Pages are built lazily and reused per layout, so streams subscribe once.
  // Switching layouts rebuilds the cache because the destination list changes.
  NavLayout? _stackLayout;
  List<String>? _stackLabels;
  List<Widget>? _stackPages;
  List<Widget> _ensureStackPages(
    NavLayout layout,
    List<AppNavDestination> destinations,
  ) {
    final labels = [for (final d in destinations) d.label];
    if (_stackLayout != layout ||
        _stackPages == null ||
        !listEquals(_stackLabels, labels)) {
      _stackLayout = layout;
      _stackLabels = labels;
      _stackPages = [for (final d in destinations) _buildPage(d)];
      if (_index >= destinations.length ||
          (layout == NavLayout.standard && _index < 0)) {
        _index = 0;
      }
    }
    return _stackPages!;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Mouse back button (button 8) → pop the navigator if possible.
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) {
          Navigator.maybeOf(context)?.maybePop();
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.prefs,
          widget.session.supportsCoreConfig,
          widget.session.supportsCoreActions,
          widget.session.supportsExternalResources,
          widget.session.supportsRules,
          widget.session.supportsTailscale,
          widget.session.supportsDiagnostics,
        ]),
        builder: (context, _) {
          final size = MediaQuery.sizeOf(context);
          // `wide` picks rail-vs-bar chrome. In wide standard the rail gets
          // the full destination set and trims itself by measured height
          // (see _computeRail); only the compact bottom bar uses a reduced
          // set, since a NavigationBar can't grow.
          final wide = size.width >= 800;
          final layout = widget.prefs.navLayout;
          final cards = layout == NavLayout.cards;
          final destinations = _destinationsFor(
            layout,
            isCompact: !wide,
            supportsCoreConfig: widget.session.supportsCoreConfig.value,
            supportsCoreActions: widget.session.supportsCoreActions.value,
            supportsExternalResources:
                widget.session.supportsExternalResources.value,
            supportsRules: widget.session.supportsRules.value,
            supportsTailscale: widget.session.supportsTailscale.value,
            supportsDiagnostics: widget.session.supportsDiagnostics.value,
          );
          if (wide) {
            return cards
                ? _buildWideCards(destinations)
                : _buildWideStandard(destinations);
          }
          if (cards) return _buildCompactLauncher(context, destinations);
          if (layout == NavLayout.floating) {
            return _buildCompactFloating(destinations);
          }
          return _buildCompactStandard(destinations);
        },
      ),
    );
  }

  Widget _buildWideStandard(List<AppNavDestination> destinations) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final n = destinations.length;
          final otherIndex = n - 1;
          // Fixed item height (rail items never stretch). Account for the top
          // safe-area inset so the fit count matches what actually renders.
          final topInset = MediaQuery.paddingOf(context).top;
          final fit =
              ((constraints.maxHeight - topInset) /
                      SideNavigationRail.itemHeight)
                  .floor()
                  .clamp(2, n);
          final shownLeading = fit >= n ? otherIndex : fit - 1;

          final visibleReal = <int>[
            for (var i = 0; i < shownLeading; i++) i,
            otherIndex,
          ];

          // Destinations that didn't fit become tiles on the 更多 page; they
          // push a full route (with its own AppBar + back button) rather than
          // swapping the IndexedStack, so navigation is unambiguous.
          final extras = <SettingsExtra>[
            for (var i = shownLeading; i < otherIndex; i++)
              SettingsExtra(
                icon: destinations[i].icon,
                label: destinations[i].label,
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    builder: (_) => _buildPage(destinations[i]),
                  ),
                ),
              ),
          ];

          // If the current page overflowed (no longer a rail item), show 更多
          // instead — its list links to the overflowed page. Growing the
          // window back makes _index a visible rail item again, restoring it.
          final effectiveIndex = visibleReal.contains(_index)
              ? _index
              : otherIndex;

          final pages = _ensureStackPages(NavLayout.standard, destinations);
          final children = [
            for (var i = 0; i < pages.length; i++)
              if (i == otherIndex)
                SettingsScreen(
                  store: widget.store,
                  prefs: widget.prefs,
                  session: widget.session,
                  extras: extras,
                  railManagesPages: true,
                )
              else
                pages[i],
          ];

          return Row(
            children: [
              SideNavigationRail(
                destinations: [for (final i in visibleReal) destinations[i]],
                selectedIndex: visibleReal.indexOf(effectiveIndex),
                onSelected: (pos) => setState(() => _index = visibleReal[pos]),
              ),
              Expanded(
                child: IndexedStack(
                  index: effectiveIndex,
                  children: [
                    for (var i = 0; i < children.length; i++)
                      HeroMode(
                        enabled: i == effectiveIndex,
                        child: TickerMode(
                          enabled: i == effectiveIndex,
                          child: children[i],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWideCards(List<AppNavDestination> destinations) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final pages = _ensureStackPages(NavLayout.cards, destinations);
    final supportsRules = widget.session.supportsRules.value;
    final effectiveIndex = !supportsRules && _index == -3 ? 0 : _index;
    // Sentinel _index < 0 means a hero-card-driven main area:
    //   -1: 核心配置
    //   -2: 连接列表  (实时流量 / 连接 hero card)
    //   -3: 分流规则  (规则 card)
    final Widget mainArea = switch (effectiveIndex) {
      -1 => CoreConfigScreen(store: widget.store, prefs: widget.prefs),
      -2 => ConnectionsScreen(
        store: widget.store,
        prefs: widget.prefs,
        session: widget.session,
      ),
      -3 => RulesScreen(store: widget.store),
      _ => IndexedStack(
        index: effectiveIndex,
        children: [
          for (var i = 0; i < pages.length; i++)
            HeroMode(
              enabled: i == effectiveIndex,
              child: TickerMode(enabled: i == effectiveIndex, child: pages[i]),
            ),
        ],
      ),
    };
    return Scaffold(
      body: Row(
        children: [
          AppSurfaceBackdrop(
            child: Container(
              width: 300,
              color: surfaceTheme.chromeColor(scheme.surface),
              child: SafeArea(
                child: _NavCardGrid(
                  store: widget.store,
                  session: widget.session,
                  destinations: destinations,
                  selectedIndex: effectiveIndex,
                  onSelected: (i) => setState(() => _index = i),
                  onKernelTap: () => setState(() => _index = -1),
                  kernelSelected: effectiveIndex == -1,
                  onConnectionsTap: () => setState(() => _index = -2),
                  connectionsSelected: effectiveIndex == -2,
                  supportsRules: supportsRules,
                  onRulesTap: () => setState(() => _index = -3),
                  rulesSelected: effectiveIndex == -3,
                  onBackendSettingsTap: _openBackendSettings,
                ),
              ),
            ),
          ),
          Expanded(child: mainArea),
        ],
      ),
    );
  }

  Widget _buildCompactStandard(List<AppNavDestination> destinations) {
    final pages = _ensureStackPages(NavLayout.standard, destinations);
    final navigationSurface = _navigationSurfaceTheme(context);
    final navigationStyle = CompactControlTheme.navigationBarOf(context);
    final navigationBackground = navigationSurface.surfaceColor(
      navigationStyle.background(context),
    );
    final bottomBar = AppSurfaceBackdrop(
      surfaceTheme: navigationSurface,
      child: ColoredBox(
        color: navigationBackground,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: navigationStyle.buttonHeight,
            child: BottomNavBarItems(
              style: widget.prefs.navBarStyle,
              styleConfig: navigationStyle,
              destinations: destinations,
              selectedIndex: _index,
              onSelected: (i) => setState(() => _index = i),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      extendBody: true,
      body: _BodyTransitionIndexedStack(index: _index, children: pages),
      bottomNavigationBar: ClipRect(child: AppBackdropGroup(child: bottomBar)),
    );
  }

  Widget _buildCompactFloating(List<AppNavDestination> destinations) {
    final pages = _ensureStackPages(NavLayout.floating, destinations);
    final navigationStyle = CompactControlTheme.navigationBarOf(context);
    final navigationSurface = _navigationSurfaceTheme(context);
    return Stack(
      children: [
        Scaffold(
          body: Builder(
            builder: (context) {
              final data = MediaQuery.of(context);
              final navBarExtra =
                  navigationStyle.buttonHeight +
                  26 +
                  navigationStyle.floatingHeightOffset.clamp(0, 20);
              return MediaQuery(
                data: data.copyWith(
                  padding: data.padding.copyWith(
                    bottom: data.padding.bottom + navBarExtra,
                  ),
                  viewPadding: data.viewPadding.copyWith(
                    bottom: data.viewPadding.bottom + navBarExtra,
                  ),
                ),
                child: _BodyTransitionIndexedStack(
                  index: _index,
                  children: pages,
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: FloatingBottomNavBar(
            selectedIndex: _index,
            onSelected: (i) => setState(() => _index = i),
            destinations: destinations,
            style: widget.prefs.navBarStyle,
            surfaceTheme: navigationSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLauncher(
    BuildContext context,
    List<AppNavDestination> destinations,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return Scaffold(
      backgroundColor: surfaceTheme.pageColor(scheme.surfaceContainerLow),
      // Let the grid scroll behind the bottom system gesture bar instead of
      // reserving a solid strip; the ListView padding handles the inset.
      body: SafeArea(
        bottom: false,
        child: _NavCardGrid(
          store: widget.store,
          session: widget.session,
          destinations: destinations,
          selectedIndex: -1,
          onSelected: (i) => Navigator.of(context).push(
            AppPageRoute<void>(builder: (_) => _buildPage(destinations[i])),
          ),
          onKernelTap: () => Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) =>
                  CoreConfigScreen(store: widget.store, prefs: widget.prefs),
            ),
          ),
          kernelSelected: false,
          onConnectionsTap: () => Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => ConnectionsScreen(
                store: widget.store,
                prefs: widget.prefs,
                session: widget.session,
              ),
            ),
          ),
          connectionsSelected: false,
          onRulesTap: () => Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => RulesScreen(store: widget.store),
            ),
          ),
          rulesSelected: false,
          supportsRules: widget.session.supportsRules.value,
          onBackendSettingsTap: _openBackendSettings,
        ),
      ),
    );
  }

  void _openBackendSettings() {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => BackendSettingsScreen(store: widget.store),
      ),
    );
  }
}

class _NavCardGrid extends StatelessWidget {
  const _NavCardGrid({
    required this.store,
    required this.session,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onKernelTap,
    required this.kernelSelected,
    required this.onConnectionsTap,
    required this.connectionsSelected,
    required this.supportsRules,
    required this.onRulesTap,
    required this.rulesSelected,
    required this.onBackendSettingsTap,
  });

  final ControllerStore store;
  final MihomoSession session;
  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onKernelTap;
  final bool kernelSelected;
  final VoidCallback onConnectionsTap;
  final bool connectionsSelected;
  final bool supportsRules;
  final VoidCallback onRulesTap;
  final bool rulesSelected;
  final VoidCallback onBackendSettingsTap;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: onBackendSettingsTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'Sparxie',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: session.supportsCoreConfig,
            builder: (context, supported, child) =>
                supported ? child! : const SizedBox.shrink(),
            child: Column(
              children: [
                OutboundModeCard(store: store),
                const SizedBox(height: 12),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: session.supportsCoreConfig,
            builder: (context, supported, _) => Opacity(
              opacity: supported ? 1 : 0.5,
              child: _StatusHeroCard(
                store: store,
                session: session,
                selected: kernelSelected,
                onTap: supported ? onKernelTap : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TrafficHeroCard(
            session: session,
            selected: connectionsSelected,
            onTap: onConnectionsTap,
          ),
          const SizedBox(height: 12),
          ..._buildNavRows(context),
        ],
      ),
    );
  }

  List<Widget> _buildNavRows(BuildContext context) {
    final navCards = [
      for (var i = 0; i < destinations.length; i++)
        _NavCard(
          icon: destinations[i].icon,
          label: destinations[i].label,
          selected: selectedIndex == i,
          onTap: () => onSelected(i),
          badge: _badgeFor(i),
        ),
    ];
    final cards = <Widget>[...navCards];
    if (supportsRules) {
      final ruleCard = _RuleNavCard(
        session: session,
        selected: rulesSelected,
        onTap: onRulesTap,
      );
      cards.insert(cards.length < 2 ? cards.length : 2, ruleCard);
    }

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 12));
      final right = i + 1 < cards.length ? cards[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(child: cards[i]),
            const SizedBox(width: 12),
            Expanded(child: right ?? const SizedBox.shrink()),
          ],
        ),
      );
    }
    return rows;
  }

  Widget? _badgeFor(int index) {
    return switch (destinations[index].label) {
      '代理组' => _GroupCountBadge(session: session),
      '连接' => _ConnectionCountBadge(session: session),
      _ => null,
    };
  }
}

class _StatusHeroCard extends StatelessWidget {
  const _StatusHeroCard({
    required this.store,
    required this.session,
    this.selected = false,
    this.onTap,
  });

  final ControllerStore store;
  final MihomoSession session;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final name = store.active?.name ?? '未连接';
        return _CardSurface(
          height: 110,
          selected: selected,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: session.isStreaming,
                        builder: (_, live, _) => Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: live
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '核心配置',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<bool>(
                    valueListenable: session.supportsMemory,
                    builder: (_, supportsMemory, _) {
                      if (!supportsMemory) return const SizedBox.shrink();
                      return Row(
                        children: [
                          Icon(
                            Icons.memory_outlined,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: RepaintBoundary(
                              child: ValueListenableBuilder<rust.MemorySample>(
                                valueListenable: session.memory,
                                builder: (_, sample, _) {
                                  final text = sample.goroutines > 0
                                      ? '${formatBytes(sample.inuse)} · 协程 ${sample.goroutines}'
                                      : formatBytes(sample.inuse);
                                  return Text(
                                    text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrafficHeroCard extends StatelessWidget {
  const _TrafficHeroCard({
    required this.session,
    this.selected = false,
    this.onTap,
  });

  final MihomoSession session;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CardSurface(
      height: 96,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.lan_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ),
                  const Spacer(),
                  RepaintBoundary(
                    child: ValueListenableBuilder<rust.TrafficSample>(
                      valueListenable: session.traffic,
                      builder: (_, sample, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${formatBytes(sample.up)}/s',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_upward,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${formatBytes(sample.down)}/s',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_downward,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '连接',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _ConnectionCountBadge(session: session),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small grid card for 规则：same shape as [_NavCard] but with a live
// rule-count badge instead of a static one.
class _RuleNavCard extends StatelessWidget {
  const _RuleNavCard({
    required this.session,
    required this.selected,
    required this.onTap,
  });
  final MihomoSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _NavCard(
      icon: Icons.alt_route,
      label: '规则',
      selected: selected,
      onTap: onTap,
      badge: ValueListenableBuilder<int>(
        valueListenable: session.ruleCount,
        builder: (_, count, _) =>
            count == 0 ? const SizedBox.shrink() : _BadgePill(text: '$count'),
      ),
    );
  }
}

class _GroupCountBadge extends StatelessWidget {
  const _GroupCountBadge({required this.session});
  final MihomoSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.proxies,
      builder: (context, _) {
        final count = session.proxies.groups.length;
        if (count == 0) return const SizedBox.shrink();
        return _BadgePill(text: '$count');
      },
    );
  }
}

class _ConnectionCountBadge extends StatelessWidget {
  const _ConnectionCountBadge({required this.session});
  final MihomoSession session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConnectionsTotals>(
      valueListenable: session.connectionsTotals,
      builder: (_, totals, _) {
        if (totals.count == 0) return const SizedBox.shrink();
        return _BadgePill(text: '${totals.count}');
      },
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.height,
    required this.child,
    this.selected = false,
  });
  final double height;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return SizedBox(
      height: height,
      child: AppSurfaceBackdrop(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: surfaceTheme.surfaceColor(
            selected ? scheme.primaryContainer : scheme.surface,
            selected ? 0.08 : 0,
          ),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            side: selected
                ? BorderSide(color: scheme.primary, width: 1.5)
                : BorderSide.none,
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final cardColor = surfaceTheme.surfaceColor(
      selected ? scheme.primaryContainer : scheme.surface,
      selected ? 0.08 : 0,
    );
    final iconBg = selected
        ? scheme.primary.withValues(alpha: 0.18)
        : scheme.surfaceContainerHighest;
    final iconFg = selected ? scheme.onPrimaryContainer : scheme.primary;
    final labelFg = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return SizedBox(
      height: 110,
      child: AppSurfaceBackdrop(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: cardColor,
          elevation: selected ? 0 : 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, size: 16, color: iconFg),
                      ),
                      const Spacer(),
                      ?badge,
                    ],
                  ),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: labelFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyTransitionIndexedStack extends StatefulWidget {
  const _BodyTransitionIndexedStack({
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_BodyTransitionIndexedStack> createState() =>
      _BodyTransitionIndexedStackState();
}

class _BodyTransitionIndexedStackState
    extends State<_BodyTransitionIndexedStack>
    with SingleTickerProviderStateMixin {
  static const _complete = AlwaysStoppedAnimation<double>(1);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(_BodyTransitionIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: HeroMode(
              enabled: i == widget.index,
              child: TickerMode(
                enabled: i == widget.index,
                child: AppPageTransitionScope(
                  animation: i == widget.index ? _animation : _complete,
                  child: widget.children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
