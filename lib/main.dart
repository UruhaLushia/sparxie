import 'dart:async';
import 'dart:io' show Platform;
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
import 'screens/logs_screen.dart';
import 'screens/proxies_screen.dart';
import 'screens/resources_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tailscale_screen.dart';
import 'session.dart';
import 'src/rust/frb_generated.dart';
import 'utils.dart';
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
  runApp(MihomoControllerApp(store: store, prefs: prefs, session: session));
}

Future<void> _initRust() {
  return RustLib.init(
    externalLibrary: Platform.isIOS
        ? frb.ExternalLibrary.process(
            iKnowHowToUseIt: true,
            debugInfo: 'Rust core is statically linked into Runner',
          )
        : null,
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
}) {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ),
    useMaterial3: true,
  );
  return _applyFontSet(base, userFonts);
}

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
  });

  final ControllerStore store;
  final AppPrefs prefs;
  final MihomoSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final uiFonts = prefs.uiFontFamilies;
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
          theme: _appTheme(
            brightness: Brightness.light,
            seedColor: const Color(0xff2563eb),
            userFonts: uiFonts,
          ),
          darkTheme: _appTheme(
            brightness: Brightness.dark,
            seedColor: const Color(0xff60a5fa),
            userFonts: uiFonts,
          ),
          builder: (context, child) =>
              _SystemBarStyle(child: child ?? const SizedBox.shrink()),
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

  List<_Dest> _destinationsFor(
    NavLayout layout, {
    required bool isCompact,
    required bool supportsCoreConfig,
    required bool supportsCoreActions,
    required bool supportsExternalResources,
    required bool supportsRules,
    required bool supportsTailscale,
  }) {
    final isStandardLike = layout == NavLayout.standard || layout == NavLayout.floating;
    final showOnStandardWide = isStandardLike && !isCompact;
    return [
      if (isStandardLike)
        const _Dest(icon: Icons.space_dashboard_outlined, label: '概览'),
      const _Dest(icon: Icons.account_tree_outlined, label: '代理组'),
      if (isStandardLike)
        const _Dest(icon: Icons.lan_outlined, label: '连接'),
      if (showOnStandardWide && supportsCoreConfig)
        const _Dest(icon: Icons.memory_outlined, label: '核心配置'),
      const _Dest(icon: Icons.terminal, label: '日志'),
      if (showOnStandardWide && supportsExternalResources)
        const _Dest(icon: Icons.cloud_outlined, label: '外部资源'),
      if (showOnStandardWide && supportsCoreActions)
        const _Dest(icon: Icons.build_outlined, label: '核心操作'),
      if (showOnStandardWide && supportsRules)
        const _Dest(icon: Icons.rule, label: '分流规则'),
      if (showOnStandardWide && supportsTailscale)
        const _Dest(icon: Icons.vpn_lock_outlined, label: 'Tailscale'),
      if (layout == NavLayout.cards && supportsExternalResources)
        const _Dest(icon: Icons.cloud_outlined, label: '外部资源'),
      if (layout == NavLayout.cards && supportsTailscale)
        const _Dest(icon: Icons.vpn_lock_outlined, label: 'Tailscale'),
      const _Dest(icon: Icons.more_horiz, label: '其他'),
    ];
  }

  Widget _buildPage(_Dest dest) {
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
  List<Widget> _ensureStackPages(NavLayout layout, List<_Dest> destinations) {
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

  Widget _buildWideStandard(List<_Dest> destinations) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final n = destinations.length;
          final otherIndex = n - 1;
          // Fixed item height (rail items never stretch). Account for the top
          // safe-area inset so the fit count matches what actually renders.
          final topInset = MediaQuery.paddingOf(context).top;
          final fit =
              ((constraints.maxHeight - topInset) / _SideRail.itemHeight)
                  .floor()
                  .clamp(2, n);
          final shownLeading = fit >= n ? otherIndex : fit - 1;

          final visibleReal = <int>[
            for (var i = 0; i < shownLeading; i++) i,
            otherIndex,
          ];

          // Destinations that didn't fit become tiles on the 其他 page; they
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

          // If the current page overflowed (no longer a rail item), show 其他
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
              _SideRail(
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

  Widget _buildWideCards(List<_Dest> destinations) {
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

  Widget _buildCompactStandard(List<_Dest> destinations) {
    final pages = _ensureStackPages(NavLayout.standard, destinations);
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              height: 64,
              elevation: 0,
              backgroundColor: isDark
                  ? scheme.surface.withValues(alpha: 0.6)
                  : scheme.surface.withValues(alpha: 0.7),
              indicatorColor: scheme.primaryContainer,
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  size: 22,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                );
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                );
              }),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactFloating(List<_Dest> destinations) {
    final pages = _ensureStackPages(NavLayout.floating, destinations);
    return Stack(
      children: [
        Scaffold(
          body: Builder(
            builder: (context) {
              final data = MediaQuery.of(context);
              const navBarExtra = 84.0; // 68 bar + 16 top gap
              return MediaQuery(
                data: data.copyWith(
                  padding: data.padding.copyWith(
                    bottom: data.padding.bottom + navBarExtra,
                  ),
                  viewPadding: data.viewPadding.copyWith(
                    bottom: data.viewPadding.bottom + navBarExtra,
                  ),
                ),
                child: IndexedStack(index: _index, children: pages),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _FloatingNavBar(
            selectedIndex: _index,
            onSelected: (i) => setState(() => _index = i),
            destinations: destinations,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLauncher(BuildContext context, List<_Dest> destinations) {
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
          // No main area on phone — push a route instead.
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

/// Side rail for wide standard layout. Items are a fixed height and packed
/// from the top, so spacing never changes; leftover space appears only at the
/// bottom, and only once every fitting item is already shown. The caller sizes
/// the visible set to [_SideRail.itemHeight].
class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// Fixed per-item height; the fit calculation in [_buildWideStandard] uses
  /// this same value so the rail never under- or over-fills.
  static const double itemHeight = 64;

  final List<_Dest> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Absorb a landscape left display cutout into the rail's own left padding
    // so the nav column keeps its full content width (centered) instead of
    // being squeezed — which shifted icons right and truncated labels.
    final leftInset = MediaQuery.paddingOf(context).left;
    return Container(
      width: 84 + leftInset,
      padding: EdgeInsets.only(left: leftInset),
      child: SafeArea(
        left: false,
        right: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < destinations.length; i++)
              SizedBox(
                height: itemHeight,
                child: _SideRailItem(
                  icon: destinations[i].icon,
                  label: destinations[i].label,
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                  scheme: scheme,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideRailItem extends StatelessWidget {
  const _SideRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    // Selected state and the press ripple share one rounded-rect shape over
    // the whole item, so the ripple no longer splashes past an icon-only pill.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
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
  final List<_Dest> destinations;
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
          ...(_buildNavRows(context)),
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

  Widget? _badgeFor(int i) {
    final dest = destinations[i];
    switch (dest.label) {
      case '代理组':
        return _GroupCountBadge(session: session);
      case '连接':
        return _ConnectionCountBadge(session: session);
      default:
        return null;
    }
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
                      builder: (_, t, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${formatBytes(t.up)}/s',
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
                                '${formatBytes(t.down)}/s',
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

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<_Dest> destinations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + bottomPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? scheme.surfaceContainerHigh.withValues(alpha: 0.68)
                  : scheme.surfaceContainer.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: SizedBox(
              height: 54,
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _FloatingNavItem(
                        icon: destinations[i].icon,
                        label: destinations[i].label,
                        selected: i == selectedIndex,
                        onTap: () => onSelected(i),
                        scheme: scheme,
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

class _FloatingNavItem extends StatelessWidget {
  const _FloatingNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSlide(
              offset: Offset(0, selected ? -0.08 : 0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Icon(icon, size: 22, color: fg),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: selected ? 18 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dest {
  const _Dest({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
