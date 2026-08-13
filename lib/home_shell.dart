part of 'main.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
  });

  final ControllerStore store;
  final AppPrefs prefs;
  final ControllerViewState session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  int _resumeGeneration = 0;
  final _pageFocusNodes = <String, FocusScopeNode>{};
  final _bottomNavigationFocusNode = FocusScopeNode(
    debugLabel: 'Bottom navigation',
  );
  final _cardNavigationFocusNode = FocusScopeNode(
    debugLabel: 'Card navigation',
  );
  final _cardFocusNodes = <int, FocusNode>{};

  // Only mobile OSes silently sever backgrounded sockets; reconnecting on
  // every desktop minimize/restore would be churn for no reason.
  static bool get _needsResumeReconnect {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _resumeGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    for (final node in _pageFocusNodes.values) {
      node.dispose();
    }
    _bottomNavigationFocusNode.dispose();
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    _cardNavigationFocusNode.dispose();
    super.dispose();
  }

  FocusScopeNode _pageFocusNode(String page) => _pageFocusNodes.putIfAbsent(
    page,
    () => FocusScopeNode(debugLabel: 'Page $page'),
  );

  FocusNode _cardFocusNode(int index) => _cardFocusNodes.putIfAbsent(
    index,
    () => FocusNode(debugLabel: 'Card navigation item $index'),
  );

  Widget _focusablePage(String page, Widget child) {
    return FocusScope(node: _pageFocusNode(page), child: child);
  }

  void _focusPage(String page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = _pageFocusNodes[page];
      if (!mounted || node == null || !node.canRequestFocus) return;
      node.requestFocus();
      if (node.hasPrimaryFocus) node.nextFocus();
    });
  }

  bool _handleFocusBoundary(TraversalDirection direction) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    final compact = MediaQuery.sizeOf(context).width < appWideLayoutBreakpoint;
    final layout = widget.prefs.navLayout;
    if (!compact && layout == NavLayout.cards) {
      final destinations = _currentDestinations(layout, isCompact: false);
      if (_cardNavigationFocusNode.hasFocus) {
        if (direction != TraversalDirection.right) return false;
        _focusPage(_pageName(_effectiveCardIndex, destinations));
        return true;
      }
      return direction == TraversalDirection.left && _focusSelectedCard();
    }
    if (!compact || layout == NavLayout.cards) return false;

    if (_bottomNavigationFocusNode.hasFocus) {
      if (direction != TraversalDirection.up) return false;
      final destinations = _currentDestinations(
        widget.prefs.navLayout,
        isCompact: true,
      );
      _focusPage(_pageName(_index, destinations));
      return true;
    }
    if (direction != TraversalDirection.down) return false;

    final nodes = _bottomNavigationFocusNode.traversalDescendants
        .where((node) => node.canRequestFocus)
        .toList(growable: false);
    if (nodes.isEmpty) return false;
    nodes[_index.clamp(0, nodes.length - 1)].requestFocus();
    return true;
  }

  int get _effectiveCardIndex =>
      !widget.session.supportsRules.value && _index == -3 ? 0 : _index;

  bool _focusSelectedCard() {
    final node = _cardFocusNodes[_effectiveCardIndex];
    if (node == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  bool _returnToPrimaryNavigation() {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        MediaQuery.sizeOf(context).width < appWideLayoutBreakpoint ||
        widget.prefs.navLayout != NavLayout.cards ||
        _cardNavigationFocusNode.hasFocus) {
      return false;
    }
    return _focusSelectedCard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_needsResumeReconnect) return;
    final generation = ++_resumeGeneration;
    if (state != AppLifecycleState.resumed) return;
    // Let Flutter present the retained UI before restarting sockets. Reconnect
    // results can then arrive on later frames instead of competing with the
    // platform's first foreground frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _resumeGeneration ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      widget.session.reconnect();
    });
  }

  @override
  void didHaveMemoryPressure() {
    // Flutter clears its global ImageCache before notifying observers.
    widget.session.processIcons.clearImages(preserveLive: true);
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

  List<AppNavDestination> _currentDestinations(
    NavLayout layout, {
    required bool isCompact,
  }) {
    return _destinationsFor(
      layout,
      isCompact: isCompact,
      supportsCoreConfig: widget.session.supportsCoreConfig.value,
      supportsCoreActions: widget.session.supportsCoreActions.value,
      supportsExternalResources: widget.session.supportsExternalResources.value,
      supportsRules: widget.session.supportsRules.value,
      supportsTailscale: widget.session.supportsTailscale.value,
      supportsDiagnostics: widget.session.supportsDiagnostics.value,
    );
  }

  bool _switchNavigation(int delta) {
    if (!mounted || delta == 0 || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= appWideLayoutBreakpoint;
    final layout = widget.prefs.navLayout;
    if (layout == NavLayout.cards && !wide) return false;

    final supportsCoreConfig = widget.session.supportsCoreConfig.value;
    final supportsRules = widget.session.supportsRules.value;
    final destinations = _currentDestinations(layout, isCompact: !wide);
    final indices = <int>[];
    if (layout == NavLayout.cards) {
      if (supportsCoreConfig) indices.add(-1);
      indices.add(-2);
      for (var i = 0; i < destinations.length; i++) {
        indices.add(i);
        if (i == 1 && supportsRules) indices.add(-3);
      }
    } else if (wide) {
      final navigationStyle = CompactControlTheme.navigationBarOf(context);
      final itemHeight = SideNavigationRail.itemHeightFor(navigationStyle);
      final n = destinations.length;
      final otherIndex = n - 1;
      final topInset = MediaQuery.paddingOf(context).top;
      final fit = ((size.height - topInset) / itemHeight).floor().clamp(2, n);
      final shownLeading = fit >= n ? otherIndex : fit - 1;
      indices.addAll([for (var i = 0; i < shownLeading; i++) i, otherIndex]);
    } else {
      indices.addAll(List<int>.generate(destinations.length, (i) => i));
    }
    if (indices.isEmpty) return false;

    final currentPosition = indices.indexOf(_index);
    final position = currentPosition < 0 ? 0 : currentPosition;
    final nextPosition = (position + delta) % indices.length;
    final nextIndex = indices[nextPosition];
    _selectPage(nextIndex, destinations);
    return true;
  }

  String _pageName(int index, List<AppNavDestination> destinations) =>
      switch (index) {
        -1 => '核心配置',
        -2 => '连接',
        -3 => '分流规则',
        _ => destinations[index].label,
      };

  void _selectPage(int index, List<AppNavDestination> destinations) {
    if (_index != index) setState(() => _index = index);
    if (isDirectionalNavigationActive) {
      _focusPage(_pageName(index, destinations));
    }
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
      '核心配置' => RemoteCoreConfigScreen(
        store: widget.store,
        prefs: widget.prefs,
      ),
      '外部资源' => ResourcesScreen(store: widget.store, prefs: widget.prefs),
      '日志' => LogsScreen(
        store: widget.store,
        prefs: widget.prefs,
        session: widget.session,
      ),
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
      _stackPages = [
        for (final d in destinations) _focusablePage(d.label, _buildPage(d)),
      ];
      if (_index >= destinations.length ||
          (layout == NavLayout.standard && _index < 0)) {
        _index = 0;
      }
    }
    return _stackPages!;
  }

  @override
  Widget build(BuildContext context) {
    return ActiveListenableBuilder(
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
        final wide = size.width >= appWideLayoutBreakpoint;
        final layout = widget.prefs.navLayout;
        final cards = layout == NavLayout.cards;
        final destinations = _currentDestinations(layout, isCompact: !wide);
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
    );
  }

  Widget _buildWideStandard(List<AppNavDestination> destinations) {
    final navigationStyle = CompactControlTheme.navigationBarOf(context);
    final navigationSurface = _navigationSurfaceTheme(context);
    final railItemHeight = SideNavigationRail.itemHeightFor(navigationStyle);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final n = destinations.length;
          final otherIndex = n - 1;
          // Fixed item height (rail items never stretch). Account for the top
          // safe-area inset so the fit count matches what actually renders.
          final topInset = MediaQuery.paddingOf(context).top;
          final fit = ((constraints.maxHeight - topInset) / railItemHeight)
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
                _focusablePage(
                  '更多',
                  SettingsScreen(
                    store: widget.store,
                    prefs: widget.prefs,
                    session: widget.session,
                    extras: extras,
                    railManagesPages: true,
                  ),
                )
              else
                pages[i],
          ];

          return Row(
            children: [
              SideNavigationRail(
                destinations: [for (final i in visibleReal) destinations[i]],
                selectedIndex: visibleReal.indexOf(effectiveIndex),
                onSelected: (pos) =>
                    _selectPage(visibleReal[pos], destinations),
                style: widget.prefs.navBarStyle,
                styleConfig: navigationStyle,
                surfaceTheme: navigationSurface,
              ),
              Expanded(
                child: _LazyIndexedStack(
                  index: effectiveIndex,
                  children: children,
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
    final effectiveIndex = _effectiveCardIndex;
    // Sentinel _index < 0 means a hero-card-driven main area:
    //   -1: 核心配置
    //   -2: 连接列表  (实时流量 / 连接 hero card)
    //   -3: 分流规则  (规则 card)
    final Widget mainArea = switch (effectiveIndex) {
      -1 => _focusablePage(
        '核心配置',
        RemoteCoreConfigScreen(store: widget.store, prefs: widget.prefs),
      ),
      -2 => _focusablePage(
        '连接',
        ConnectionsScreen(
          store: widget.store,
          prefs: widget.prefs,
          session: widget.session,
        ),
      ),
      -3 => _focusablePage('分流规则', RulesScreen(store: widget.store)),
      _ => _LazyIndexedStack(index: effectiveIndex, children: pages),
    };
    return ListenableBuilder(
      listenable: _cardNavigationFocusNode,
      builder: (context, child) => PopScope<void>(
        canPop: _cardNavigationFocusNode.hasFocus,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _focusSelectedCard();
        },
        child: child!,
      ),
      child: Scaffold(
        body: Row(
          children: [
            AppSurfaceBackdrop(
              child: Container(
                width: 300,
                color: surfaceTheme.chromeColor(scheme.surface),
                child: FocusScope(
                  node: _cardNavigationFocusNode,
                  child: _NavCardGrid(
                    store: widget.store,
                    session: widget.session,
                    destinations: destinations,
                    selectedIndex: effectiveIndex,
                    focusNodeFor: _cardFocusNode,
                    onSelected: (i) => _selectPage(i, destinations),
                    onKernelTap: () => _selectPage(-1, destinations),
                    kernelSelected: effectiveIndex == -1,
                    onConnectionsTap: () => _selectPage(-2, destinations),
                    connectionsSelected: effectiveIndex == -2,
                    supportsRules: supportsRules,
                    onRulesTap: () => _selectPage(-3, destinations),
                    rulesSelected: effectiveIndex == -3,
                    onBackendSettingsTap: _openBackendSettings,
                  ),
                ),
              ),
            ),
            Expanded(child: mainArea),
          ],
        ),
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
              onSelected: (i) => _selectPage(i, destinations),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      extendBody: true,
      body: Builder(
        builder: (context) {
          final data = MediaQuery.of(context);
          // `extendBody` updates padding, while nested Scaffolds position FABs
          // from viewPadding. Mirror the actual bar inset for both.
          return MediaQuery(
            data: data.copyWith(
              viewPadding: data.viewPadding.copyWith(
                bottom: data.padding.bottom,
              ),
            ),
            child: _BodyTransitionIndexedStack(index: _index, children: pages),
          );
        },
      ),
      bottomNavigationBar: FocusScope(
        node: _bottomNavigationFocusNode,
        child: ClipRect(child: AppBackdropGroup(child: bottomBar)),
      ),
    );
  }

  Widget _buildCompactFloating(List<AppNavDestination> destinations) {
    final pages = _ensureStackPages(NavLayout.floating, destinations);
    final navigationSurface = _navigationSurfaceTheme(context);
    // Scaffold must own the floating bar so SnackBars use its visual top.
    return Scaffold(
      extendBody: true,
      body: Builder(
        builder: (context) {
          final data = MediaQuery.of(context);
          final bodyBottom = data.padding.bottom + 20;
          return MediaQuery(
            data: data.copyWith(
              padding: data.padding.copyWith(bottom: bodyBottom),
              viewPadding: data.viewPadding.copyWith(bottom: bodyBottom),
            ),
            child: _BodyTransitionIndexedStack(index: _index, children: pages),
          );
        },
      ),
      bottomNavigationBar: FocusScope(
        node: _bottomNavigationFocusNode,
        child: FloatingBottomNavBar(
          selectedIndex: _index,
          onSelected: (i) => _selectPage(i, destinations),
          destinations: destinations,
          style: widget.prefs.navBarStyle,
          surfaceTheme: navigationSurface,
        ),
      ),
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
              builder: (_) => RemoteCoreConfigScreen(
                store: widget.store,
                prefs: widget.prefs,
              ),
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
    this.focusNodeFor,
  });

  final ControllerStore store;
  final ControllerViewState session;
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
  final FocusNode Function(int index)? focusNodeFor;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16 + MediaQuery.paddingOf(context).top,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppFocusHighlight(
                borderRadius: BorderRadius.circular(8),
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
          ),
          ActiveValueListenableBuilder<bool>(
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
          ActiveValueListenableBuilder<bool>(
            valueListenable: session.supportsCoreConfig,
            builder: (context, supported, _) => Opacity(
              opacity: supported ? 1 : 0.5,
              child: _StatusHeroCard(
                store: store,
                session: session,
                selected: kernelSelected,
                onTap: supported ? onKernelTap : null,
                focusNode: focusNodeFor?.call(-1),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TrafficHeroCard(
            session: session,
            selected: connectionsSelected,
            onTap: onConnectionsTap,
            focusNode: focusNodeFor?.call(-2),
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
          focusNode: focusNodeFor?.call(i),
          badge: _badgeFor(i, selected: selectedIndex == i),
        ),
    ];
    final cards = <Widget>[...navCards];
    if (supportsRules) {
      final ruleCard = _RuleNavCard(
        session: session,
        selected: rulesSelected,
        onTap: onRulesTap,
        focusNode: focusNodeFor?.call(-3),
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

  Widget? _badgeFor(int index, {required bool selected}) {
    return switch (destinations[index].label) {
      '代理组' => _GroupCountBadge(session: session, selected: selected),
      '连接' => _ConnectionCountBadge(session: session, selected: selected),
      _ => null,
    };
  }
}

({Color foreground, Color secondary, Color accent}) _navCardColors(
  ColorScheme scheme,
  bool selected,
) {
  final selectedForeground = scheme.onPrimaryContainer;
  return (
    foreground: selected ? selectedForeground : scheme.onSurface,
    secondary: selected
        ? selectedForeground.withValues(alpha: 0.72)
        : scheme.onSurfaceVariant,
    accent: selected ? selectedForeground : scheme.primary,
  );
}

class _StatusHeroCard extends StatelessWidget {
  const _StatusHeroCard({
    required this.store,
    required this.session,
    this.selected = false,
    this.onTap,
    this.focusNode,
  });

  final ControllerStore store;
  final ControllerViewState session;
  final bool selected;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _navCardColors(scheme, selected);
    return ActiveListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final name = store.active?.name ?? '未连接';
        return _CardSurface(
          height: 110,
          selected: selected,
          child: InkWell(
            focusNode: focusNode,
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
                              ?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      ActiveValueListenableBuilder<bool>(
                        valueListenable: session.isStreaming,
                        builder: (_, live, _) => Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: live
                                ? colors.accent
                                : colors.secondary.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '核心配置',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.secondary),
                  ),
                  const Spacer(),
                  ActiveValueListenableBuilder<bool>(
                    valueListenable: session.supportsMemory,
                    builder: (_, supportsMemory, _) {
                      if (!supportsMemory) return const SizedBox.shrink();
                      return Row(
                        children: [
                          Icon(
                            Icons.memory_outlined,
                            size: 16,
                            color: colors.accent.withValues(
                              alpha: selected ? 0.72 : 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: RepaintBoundary(
                              child:
                                  ActiveValueListenableBuilder<
                                    rust.MemorySample
                                  >(
                                    valueListenable: session.memory,
                                    pauseWhileScrolling: true,
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
                                            ?.copyWith(
                                              color: colors.foreground,
                                              fontWeight: FontWeight.w600,
                                            ),
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
    this.focusNode,
  });

  final ControllerViewState session;
  final bool selected;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _navCardColors(scheme, selected);
    return _CardSurface(
      height: 96,
      selected: selected,
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(
                      Icons.lan_outlined,
                      size: 16,
                      color: colors.accent,
                    ),
                  ),
                  const Spacer(),
                  RepaintBoundary(
                    child: ActiveValueListenableBuilder<rust.TrafficSample>(
                      valueListenable: session.traffic,
                      pauseWhileScrolling: true,
                      builder: (context, sample, _) {
                        final textStyle = Theme.of(context).textTheme.bodySmall
                            ?.copyWith(
                              color: colors.foreground,
                              fontWeight: FontWeight.w600,
                            );
                        final arrowColor = colors.accent.withValues(
                          alpha: selected ? 0.72 : 0.8,
                        );
                        Widget rate(String value, IconData arrow) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(value, style: textStyle),
                            const SizedBox(width: 4),
                            Icon(arrow, size: 13, color: arrowColor),
                          ],
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            rate(
                              '${formatBytes(sample.up)}/s',
                              Icons.arrow_upward,
                            ),
                            const SizedBox(height: 2),
                            rate(
                              '${formatBytes(sample.down)}/s',
                              Icons.arrow_downward,
                            ),
                          ],
                        );
                      },
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
                      color: colors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _ConnectionCountBadge(session: session, selected: selected),
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
    this.focusNode,
  });
  final ControllerViewState session;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return _NavCard(
      icon: Icons.alt_route,
      label: '规则',
      selected: selected,
      onTap: onTap,
      focusNode: focusNode,
      badge: ActiveValueListenableBuilder<int>(
        valueListenable: session.ruleCount,
        builder: (_, count, _) => count == 0
            ? const SizedBox.shrink()
            : _BadgeLabel(text: '$count', selected: selected),
      ),
    );
  }
}

class _GroupCountBadge extends StatelessWidget {
  const _GroupCountBadge({required this.session, required this.selected});
  final ControllerViewState session;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ActiveListenableSelector<int>(
      listenable: session.proxies,
      selector: () => session.proxies.groups.length,
      builder: (context, count, _) {
        if (count == 0) return const SizedBox.shrink();
        return _BadgeLabel(text: '$count', selected: selected);
      },
    );
  }
}

class _ConnectionCountBadge extends StatelessWidget {
  const _ConnectionCountBadge({required this.session, required this.selected});
  final ControllerViewState session;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ActiveValueListenableSelector<ConnectionsTotals, int>(
      valueListenable: session.connectionsTotals,
      pauseWhileScrolling: true,
      selector: (totals) => totals.count,
      builder: (_, count, _) {
        if (count == 0) return const SizedBox.shrink();
        return _BadgeLabel(text: '$count', selected: selected);
      },
    );
  }
}

class _BadgeLabel extends StatelessWidget {
  const _BadgeLabel({required this.text, required this.selected});
  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _navCardColors(scheme, selected);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colors.accent,
        ),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.height,
    required this.child,
    required this.selected,
  });
  final double height;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AppFocusHighlight(
      borderRadius: kAppPanelRadius,
      child: SizedBox(
        height: height,
        child: AppPanelSurface(
          outlined: !selected,
          selected: selected,
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
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? badge;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _navCardColors(scheme, selected);

    return _CardSurface(
      height: 110,
      selected: selected,
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(icon, size: 16, color: colors.accent),
                  ),
                  const Spacer(),
                  ?badge,
                ],
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
    with TickerProviderStateMixin {
  static const _complete = AlwaysStoppedAnimation<double>(1);
  static const _duration = Duration(milliseconds: 240);

  late final Set<int> _visited;
  AnimationController? _controller;
  CurvedAnimation? _animation;
  var _tickerEnabled = true;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _visited = {widget.index};
  }

  @override
  void didUpdateWidget(_BodyTransitionIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.removeWhere((index) => index >= widget.children.length);
    _visited.add(widget.index);
    if (oldWidget.index != widget.index) _startTransition();
  }

  void _startTransition() {
    if (!_tickerEnabled) return;
    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: _duration,
    );
    _animation ??= CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );
    final generation = ++_generation;
    controller.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted ||
          generation != _generation ||
          !identical(_controller, controller) ||
          !controller.isCompleted) {
        return;
      }
      final animation = _animation;
      setState(() {
        _animation = null;
        _controller = null;
      });
      animation?.dispose();
      controller.dispose();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = isUiActive(context);
    if (!_tickerEnabled && _controller != null) {
      _generation++;
      final animation = _animation;
      final controller = _controller;
      _animation = null;
      _controller = null;
      animation?.dispose();
      controller?.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    final animation = _animation;
    final controller = _controller;
    _animation = null;
    _controller = null;
    animation?.dispose();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeActive = isUiActive(context);
    final animation = _animation;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_visited.contains(i))
            Offstage(
              key: ValueKey(i),
              offstage: i != widget.index,
              child: ExcludeFocus(
                excluding: i != widget.index,
                child: _DeferredPageTheme(
                  active: routeActive && i == widget.index,
                  child: HeroMode(
                    enabled: i == widget.index,
                    child: TickerMode(
                      enabled: routeActive && i == widget.index,
                      child: AppPageTransitionScope(
                        animation: i == widget.index && animation != null
                            ? animation
                            : _complete,
                        child: widget.children[i],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late final Set<int> _visited;

  @override
  void initState() {
    super.initState();
    _visited = {widget.index};
  }

  @override
  void didUpdateWidget(_LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.removeWhere((index) => index >= widget.children.length);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    final routeActive = isUiActive(context);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_visited.contains(i))
            ExcludeFocus(
              key: ValueKey(i),
              excluding: i != widget.index,
              child: _DeferredPageTheme(
                active: routeActive && i == widget.index,
                child: HeroMode(
                  enabled: i == widget.index,
                  child: TickerMode(
                    enabled: routeActive && i == widget.index,
                    child: widget.children[i],
                  ),
                ),
              ),
            )
          else
            const SizedBox.shrink(),
      ],
    );
  }
}

class _DeferredPageTheme extends StatefulWidget {
  const _DeferredPageTheme({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_DeferredPageTheme> createState() => _DeferredPageThemeState();
}

class _DeferredPageThemeState extends State<_DeferredPageTheme> {
  ThemeData? _theme;
  CompactControlTheme? _controls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controls = CompactControlTheme.maybeOf(context)!;
    if (_theme == null || widget.active) {
      _theme = theme;
      _controls = controls;
    }
    return Theme(data: _theme!, child: _controls!.wrap(context, widget.child));
  }
}

class _DeferredRouteTheme extends StatelessWidget {
  const _DeferredRouteTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _DeferredPageTheme(active: isUiActive(context), child: child);
}
