import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;

import 'app_paths.dart';
import 'app_prefs.dart';
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
import 'widgets/bottom_navigation.dart';
import 'widgets/compact_controls.dart';
import 'widgets/outbound_mode_card.dart';
import 'window_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _enableEdgeToEdge();
  // One shared config.json holds controllers, prefs and window geometry.
  final config = await JsonStore.load();
  // Restore the desktop window's saved size / position / maximized state.
  // No-op on mobile and web — `WindowState.bind` short-circuits there.
  await WindowState.bind(config);
  await _initRust();
  final prefs = await AppPrefs.load(config);
  final systemAccentColor = await SystemAccentColor.load(
    enabled: prefs.automaticColor,
  );
  await ImportedFonts.cleanup(prefs.importedFonts);
  await ImportedFonts.loadAll(prefs.importedFonts);
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
  prefs.addListener(() {
    session.setConnectionsInterval(prefs.connectionsRefreshMs);
    systemAccentColor.setEnabled(prefs.automaticColor);
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

ThemeData _appTheme({
  required Brightness brightness,
  required Color seedColor,
  required List<String> userFonts,
  required bool useAutomaticColors,
  required bool pureBlack,
}) {
  final generated = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  final onSeed =
      ThemeData.estimateBrightnessForColor(seedColor) == Brightness.dark
      ? Colors.white
      : Colors.black;
  var scheme = useAutomaticColors
      ? generated
      : generated.copyWith(primary: seedColor, onPrimary: onSeed);
  if (pureBlack && brightness == Brightness.dark) {
    scheme = _pureBlackScheme(scheme);
  }
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return _applyFontSet(base, userFonts);
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

class MihomoControllerApp extends StatelessWidget {
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
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Sparxie',
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
          theme: _appTheme(
            brightness: Brightness.light,
            seedColor: effectiveSeed,
            userFonts: uiFonts,
            useAutomaticColors: useAutomaticColor,
            pureBlack: false,
          ),
          darkTheme: _appTheme(
            brightness: Brightness.dark,
            seedColor: effectiveSeed,
            userFonts: uiFonts,
            useAutomaticColors: useAutomaticColor,
            pureBlack: prefs.pureBlackMode,
          ),
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
              if (useAutomaticColor) {
                return CompactControlStyle.fromColorScheme(
                  colorScheme: Theme.of(context).colorScheme,
                  borderRadius: radius,
                  controlHeight: height,
                  widthScale: widthScale,
                  indicatorBorderRadius: innerRadius,
                  indicatorHeight: innerHeight,
                  indicatorWidthScale: innerWidthScale,
                  floatingHeightOffset: prefs.navigationFloatingHeightOffset,
                );
              }
              return CompactControlStyle.fromSeed(
                seedColor: Color(prefs.compactThemeColor(kind)),
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
                floatingHeightOffset: prefs.navigationFloatingHeightOffset,
              );
            }

            return CompactControlTheme(
              buttonStyle: styleFor(CompactControlKind.button),
              searchStyle: styleFor(CompactControlKind.search),
              segmentedStyle: styleFor(CompactControlKind.segmented),
              switchStyle: styleFor(CompactControlKind.toggle),
              navigationBarStyle: styleFor(CompactControlKind.navigationBar),
              child: _SystemBarStyle(child: child ?? const SizedBox.shrink()),
            );
          },
          home: HomeShell(store: store, prefs: prefs, session: session),
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
                  MaterialPageRoute(
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
              const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(index: effectiveIndex, children: children),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWideCards(List<AppNavDestination> destinations) {
    final scheme = Theme.of(context).colorScheme;
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
      _ => IndexedStack(index: effectiveIndex, children: pages),
    };
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 300,
            color: scheme.surfaceContainerLow,
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
          const VerticalDivider(width: 1),
          Expanded(child: mainArea),
        ],
      ),
    );
  }

  Widget _buildCompactStandard(List<AppNavDestination> destinations) {
    final pages = _ensureStackPages(NavLayout.standard, destinations);
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final navigationStyle = CompactControlTheme.navigationBarOf(context);
    return Scaffold(
      extendBody: true,
      body: _FadeThroughIndexedStack(index: _index, children: pages),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: ColoredBox(
            color: navigationStyle
                .background(context)
                .withValues(alpha: isDark ? 0.76 : 0.86),
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
        ),
      ),
    );
  }

  Widget _buildCompactFloating(List<AppNavDestination> destinations) {
    final pages = _ensureStackPages(NavLayout.floating, destinations);
    final navigationStyle = CompactControlTheme.navigationBarOf(context);
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
                child: _FadeThroughIndexedStack(index: _index, children: pages),
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
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
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
            MaterialPageRoute(builder: (_) => _buildPage(destinations[i])),
          ),
          onKernelTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  CoreConfigScreen(store: widget.store, prefs: widget.prefs),
            ),
          ),
          kernelSelected: false,
          onConnectionsTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConnectionsScreen(
                store: widget.store,
                prefs: widget.prefs,
                session: widget.session,
              ),
            ),
          ),
          connectionsSelected: false,
          onRulesTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RulesScreen(store: widget.store)),
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
      MaterialPageRoute(
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
    return SizedBox(
      height: height,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
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
    final cardColor = selected ? scheme.primaryContainer : scheme.surface;
    final iconBg = selected
        ? scheme.primary.withValues(alpha: 0.18)
        : scheme.surfaceContainerHighest;
    final iconFg = selected ? scheme.onPrimaryContainer : scheme.primary;
    final labelFg = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return SizedBox(
      height: 110,
      child: Material(
        color: cardColor,
        elevation: selected ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    );
  }
}

class _FadeThroughIndexedStack extends StatefulWidget {
  const _FadeThroughIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_FadeThroughIndexedStack> createState() =>
      _FadeThroughIndexedStackState();
}

class _FadeThroughIndexedStackState extends State<_FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _fadeIn = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _scaleIn = Tween<double>(
    begin: 0.94,
    end: 1,
  ).animate(_fadeIn);
  late final Animation<double> _fadeOut = ReverseAnimation(
    CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.3, curve: Curves.easeIn),
    ),
  );
  int _current = 0;
  int _outgoing = -1;

  @override
  void initState() {
    super.initState();
    _current = widget.index;
    _ctrl.value = 1;
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && _outgoing >= 0) {
        setState(() => _outgoing = -1);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_FadeThroughIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      setState(() {
        _outgoing = _current;
        _current = widget.index;
      });
      _ctrl.forward(from: 0);
    }
  }

  // Every child keeps the same wrapper chain and a stable key, so moving
  // between hidden/outgoing/current only flips parameters — page state
  // (stream subscriptions etc.) survives z-order changes.
  Widget _wrap(int i) {
    final active = i == _current;
    final outgoing = i == _outgoing;
    return Offstage(
      key: ValueKey(i),
      offstage: !active && !outgoing,
      child: TickerMode(
        enabled: active || outgoing,
        child: IgnorePointer(
          ignoring: !active,
          child: FadeTransition(
            opacity: active
                ? _fadeIn
                : outgoing
                ? _fadeOut
                : const AlwaysStoppedAnimation(1),
            child: ScaleTransition(
              scale: active ? _scaleIn : const AlwaysStoppedAnimation(1),
              child: widget.children[i],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = <int>[
      for (var i = 0; i < widget.children.length; i++)
        if (i != _current && i != _outgoing) i,
      if (_outgoing >= 0) _outgoing,
      _current,
    ];
    return Stack(
      fit: StackFit.expand,
      children: [for (final i in order) _wrap(i)],
    );
  }
}
