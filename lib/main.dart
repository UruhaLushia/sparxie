import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_prefs.dart';
import 'controller.dart';
import 'rust_api.dart' as rust;
import 'screens/core_config_screen.dart';
import 'screens/connections_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/proxies_screen.dart';
import 'screens/resources_screen.dart';
import 'screens/settings_screen.dart';
import 'session.dart';
import 'src/rust/frb_generated.dart';
import 'utils.dart';
import 'widgets/outbound_mode_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Constrain the desktop window to a width that fits the multi-control
  // toolbars without overflow. window_manager only supports desktop —
  // probing kIsWeb keeps mobile builds happy without an `import 'dart:io'`
  // crash on web.
  if (!kIsWeb &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(380, 600));
  }
  await RustLib.init();
  // Hand the platform's app cache dir to Rust so it can persist proxy
  // icon bytes across launches; failures here are non-fatal — icons just
  // fall back to letter chips when unreachable.
  try {
    final dir = await getApplicationCacheDirectory();
    await rust.initIconCache(cacheDir: dir.path);
  } catch (e) {
    if (kDebugMode) debugPrint('icon cache init failed: $e');
  }
  final store = await ControllerStore.load();
  final prefs = await AppPrefs.load();
  final session = MihomoSession(store)
    ..setConnectionsInterval(prefs.connectionsRefreshMs);
  prefs.addListener(() {
    session.setConnectionsInterval(prefs.connectionsRefreshMs);
  });
  runApp(MihomoControllerApp(store: store, prefs: prefs, session: session));
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mihomo Controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2563eb),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff60a5fa),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeShell(store: store, prefs: prefs, session: session),
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

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
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

  // Standard layout exposes 概览 as the first tab. Cards layout drops 概览
  // (the launcher already surfaces overview info), 连接 (the traffic hero
  // card opens it directly) and 内核配置 (a dedicated hero card opens it);
  // 外部资源 lives in the nav grid as a small card on cards mode.
  // On phones the standard nav is also capped at 5 items; 内核配置 and
  // 外部资源 move into the 其他 page.
  // CMFA builds disable mihomo's `/configs` knobs, so 内核配置 is also
  // dropped from the standard wide nav when [isCmfa] is true.
  List<_Dest> _destinationsFor(
    NavLayout layout, {
    required bool isCompact,
    required bool isCmfa,
  }) {
    final showOnStandardWide = layout == NavLayout.standard && !isCompact;
    return [
      if (layout == NavLayout.standard)
        const _Dest(icon: Icons.space_dashboard_outlined, label: '概览'),
      const _Dest(icon: Icons.account_tree_outlined, label: '代理组'),
      if (layout == NavLayout.standard)
        const _Dest(icon: Icons.lan_outlined, label: '连接'),
      if (showOnStandardWide && !isCmfa)
        const _Dest(icon: Icons.memory_outlined, label: '内核配置'),
      if (showOnStandardWide)
        const _Dest(icon: Icons.cloud_outlined, label: '外部资源'),
      const _Dest(icon: Icons.terminal, label: '日志'),
      if (layout == NavLayout.cards)
        const _Dest(icon: Icons.cloud_outlined, label: '外部资源'),
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
      '内核配置' =>
        CoreConfigScreen(store: widget.store, prefs: widget.prefs),
      '外部资源' => ResourcesScreen(store: widget.store),
      '日志' => LogsScreen(store: widget.store),
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
  List<Widget>? _stackPages;
  List<Widget> _ensureStackPages(NavLayout layout, List<_Dest> destinations) {
    if (_stackLayout != layout || _stackPages == null) {
      _stackLayout = layout;
      _stackPages = [for (final d in destinations) _buildPage(d)];
      if (_index >= destinations.length) _index = 0;
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
      // Rebuild on prefs (nav layout) and on isCmfa (drops 内核配置 nav).
      listenable: Listenable.merge([widget.prefs, widget.session.isCmfa]),
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 800;
        final cards = widget.prefs.navLayout == NavLayout.cards;
        final destinations = _destinationsFor(
          widget.prefs.navLayout,
          isCompact: !wide,
          isCmfa: widget.session.isCmfa.value,
        );
        if (wide) {
          return cards
              ? _buildWideCards(destinations)
              : _buildWideStandard(destinations);
        }
        return cards
            ? _buildCompactLauncher(context, destinations)
            : _buildCompactStandard(destinations);
      },
      ),
    );
  }

  Widget _buildWideStandard(List<_Dest> destinations) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children:
                  _ensureStackPages(NavLayout.standard, destinations),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideCards(List<_Dest> destinations) {
    final scheme = Theme.of(context).colorScheme;
    // Sentinel _index < 0 means a hero-card-driven main area:
    //   -1: 内核配置  (内核设置 hero card)
    //   -2: 连接列表  (实时流量 / 连接 hero card)
    final Widget mainArea = switch (_index) {
      -1 => CoreConfigScreen(store: widget.store, prefs: widget.prefs),
      -2 => ConnectionsScreen(
          store: widget.store,
          prefs: widget.prefs,
          session: widget.session,
        ),
      _ => IndexedStack(
          index: _index,
          children: _ensureStackPages(NavLayout.cards, destinations),
        ),
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
                selectedIndex: _index,
                onSelected: (i) => setState(() => _index = i),
                onKernelTap: () => setState(() => _index = -1),
                kernelSelected: _index == -1,
                onConnectionsTap: () => setState(() => _index = -2),
                connectionsSelected: _index == -2,
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
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _ensureStackPages(NavLayout.standard, destinations),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }

  Widget _buildCompactLauncher(BuildContext context, List<_Dest> destinations) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: SafeArea(
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Mihomo',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        // CMFA builds disable mihomo's `/configs` mode endpoint, so hide the
        // launcher control entirely while connected to one. The listener
        // keeps it cheap — no rebuilds on traffic / proxies updates.
        ValueListenableBuilder<bool>(
          valueListenable: session.isCmfa,
          builder: (context, cmfa, child) =>
              cmfa ? const SizedBox.shrink() : child!,
          child: Column(
            children: [
              OutboundModeCard(store: store),
              const SizedBox(height: 12),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: session.isCmfa,
          builder: (context, cmfa, _) => Opacity(
            opacity: cmfa ? 0.5 : 1,
            child: _StatusHeroCard(
              store: store,
              session: session,
              selected: kernelSelected,
              onTap: cmfa ? null : onKernelTap,
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
    );
  }

  List<Widget> _buildNavRows(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < destinations.length; i += 2) {
      if (i > 0) tiles.add(const SizedBox(height: 12));
      final left = destinations[i];
      final right = i + 1 < destinations.length ? destinations[i + 1] : null;
      tiles.add(
        Row(
          children: [
            Expanded(
              child: _NavCard(
                icon: left.icon,
                label: left.label,
                selected: selectedIndex == i,
                onTap: () => onSelected(i),
                badge: _badgeFor(i),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _NavCard(
                      icon: right.icon,
                      label: right.label,
                      selected: selectedIndex == i + 1,
                      onTap: () => onSelected(i + 1),
                      badge: _badgeFor(i + 1),
                    ),
            ),
          ],
        ),
      );
    }
    return tiles;
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
        final active = store.active;
        final name = active?.name ?? '未连接';
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
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
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
                  '内核设置',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.memory_outlined,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RepaintBoundary(
                        child: ValueListenableBuilder<rust.MemorySample>(
                          valueListenable: session.memory,
                          builder: (_, sample, _) => Text(
                            formatBytes(sample.inuse),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                    child: Icon(Icons.lan_outlined,
                        size: 16, color: scheme.primary),
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
                              Icon(Icons.arrow_upward,
                                  size: 14, color: scheme.onSurfaceVariant),
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
                              Icon(Icons.arrow_downward,
                                  size: 14, color: scheme.onSurfaceVariant),
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
    );
  }
}

class _Dest {
  const _Dest({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
