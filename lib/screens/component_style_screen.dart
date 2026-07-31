part of 'theme_settings_screen.dart';

class ComponentStyleScreen extends StatefulWidget {
  const ComponentStyleScreen({
    super.key,
    required this.prefs,
    required this.kind,
  });

  final AppPrefs prefs;
  final CompactControlKind kind;

  @override
  State<ComponentStyleScreen> createState() => _ComponentStyleScreenState();
}

class _ComponentStyleScreenState extends State<ComponentStyleScreen> {
  late Color _color;
  late bool _followGlobalColor;
  late double _radius;
  late double _height;
  late double _widthScale;
  late Color _innerColor;
  late bool _innerColorFollowsOuter;
  late double _innerRadius;
  late double _innerHeight;
  late double _innerWidthScale;
  late double _floatingHeightOffset;
  late bool _followGlobalSurface;
  late AppSurfaceEffect _navigationSurfaceEffect;
  late double _navigationSurfaceOpacity;
  late double _navigationSurfaceBlur;
  int _previewNavigationIndex = 2;
  int _previewSegment = 0;
  bool _previewSwitchValue = true;
  final _searchController = TextEditingController(text: 'Search');
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _color = Color(widget.prefs.compactThemeColor(widget.kind));
    _followGlobalColor = widget.prefs.compactColorFollowsGlobal(widget.kind);
    _radius = widget.prefs.compactBorderRadius(widget.kind);
    _height = widget.prefs.compactControlHeight(widget.kind);
    _widthScale = widget.prefs.compactWidthScale(widget.kind);
    _innerColor = Color(widget.prefs.navigationInnerThemeColor);
    _innerColorFollowsOuter = !widget.prefs.hasNavigationInnerThemeColor;
    _innerRadius = widget.prefs.navigationInnerBorderRadius;
    _innerHeight = widget.prefs.navigationInnerHeight;
    _innerWidthScale = widget.prefs.navigationInnerWidthScale;
    _floatingHeightOffset = widget.prefs.navigationFloatingHeightOffset;
    _followGlobalSurface = widget.prefs.navigationSurfaceFollowsGlobal;
    _navigationSurfaceEffect = widget.prefs.navigationSurfaceEffect;
    _navigationSurfaceOpacity = widget.prefs.navigationSurfaceOpacity;
    _navigationSurfaceBlur = widget.prefs.navigationSurfaceBlur;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  CompactControlStyle _style(BuildContext context) {
    final automaticColor = widget.prefs.automaticColor;
    final navigationBar = widget.kind == CompactControlKind.navigationBar;
    final outerColor = _followGlobalColor
        ? Color(widget.prefs.globalThemeColor)
        : _color;
    final style = automaticColor
        ? CompactControlStyle.fromColorScheme(
            colorScheme: Theme.of(context).colorScheme,
            borderRadius: _radius,
            controlHeight: _height,
            widthScale: _widthScale,
            indicatorBorderRadius: navigationBar ? _innerRadius : _radius,
            indicatorHeight: navigationBar ? _innerHeight : _height,
            indicatorWidthScale: navigationBar ? _innerWidthScale : _widthScale,
            floatingHeightOffset: _floatingHeightOffset,
          )
        : CompactControlStyle.fromSeed(
            seedColor: outerColor,
            selectedSeedColor: navigationBar
                ? _innerColorFollowsOuter
                      ? outerColor
                      : _innerColor
                : null,
            brightness: Theme.of(context).brightness,
            borderRadius: _radius,
            controlHeight: _height,
            widthScale: _widthScale,
            indicatorBorderRadius: navigationBar ? _innerRadius : _radius,
            indicatorHeight: navigationBar ? _innerHeight : _height,
            indicatorWidthScale: navigationBar ? _innerWidthScale : _widthScale,
            floatingHeightOffset: _floatingHeightOffset,
          );
    return style;
  }

  AppSurfaceTheme _navigationSurfaceTheme(BuildContext context) {
    final global = AppSurfaceTheme.of(context);
    if (_followGlobalSurface) return global;
    final acrylic = _navigationSurfaceEffect == AppSurfaceEffect.acrylic;
    return global.copyWith(
      enabled: true,
      effect: _navigationSurfaceEffect,
      opacity: _navigationSurfaceOpacity,
      blurSigma: _navigationSurfaceBlur,
      tintColor: Theme.of(context).colorScheme.primary,
      blurScale: acrylic ? AppSurfaceTheme.compactAcrylicBlurScale : 1,
      acrylicVeil: acrylic ? AppSurfaceTheme.compactAcrylicVeil : 0.18,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final automaticColor = widget.prefs.automaticColor;
    final navigationBar = widget.kind == CompactControlKind.navigationBar;
    final floatingNavigationBar =
        navigationBar && widget.prefs.navLayout == NavLayout.floating;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth > 792
        ? (screenWidth - 760) / 2
        : 16.0;
    return Scaffold(
      backgroundColor: surfaceTheme.pageColor(scheme.surfaceContainerLowest),
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: Text('${widget.kind.label}样式'),
          flexibleSpace: const DesktopAppBarDragArea(),
          actions: [
            TextButton(onPressed: _reset, child: const Text('重置')),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 104,
            child: navigationBar
                ? Align(
                    alignment: const Alignment(0, -0.05),
                    child: _preview(style),
                  )
                : Center(child: _preview(style)),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                child: CompactSettingsPanel(
                  surfaceTheme: surfaceTheme,
                  expandBody: true,
                  header: AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, _) {
                      final offset = _scrollController.hasClients
                          ? _scrollController.offset
                          : 0.0;
                      return CompactSettingsPanelHeader(
                        title: '外观',
                        icon: Icons.tune_outlined,
                        elevation: (offset / 20).clamp(0.0, 1.0),
                      );
                    },
                  ),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      children: [
                        Column(
                          children: [
                            if (navigationBar) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '导航栏样式',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              CompactSegmentedButton<NavBarStyle>(
                                expanded: true,
                                segments: const [
                                  ButtonSegment(
                                    value: NavBarStyle.capsule,
                                    label: Text('胶囊'),
                                  ),
                                  ButtonSegment(
                                    value: NavBarStyle.pill,
                                    label: Text('药丸'),
                                  ),
                                  ButtonSegment(
                                    value: NavBarStyle.tint,
                                    label: Text('素色'),
                                  ),
                                  ButtonSegment(
                                    value: NavBarStyle.m3,
                                    label: Text('MD3'),
                                  ),
                                ],
                                selected: {widget.prefs.navBarStyle},
                                onSelectionChanged: (selection) {
                                  widget.prefs.setNavBarStyle(selection.first);
                                  setState(_load);
                                },
                              ),
                              const Divider(height: 32),
                              const _StyleSectionHeader(
                                icon: Icons.blur_on_rounded,
                                label: '表面',
                              ),
                              CompactSwitch.tile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('跟随全局表面效果'),
                                value: _followGlobalSurface,
                                onChanged: (value) async {
                                  await widget.prefs
                                      .setNavigationSurfaceFollowsGlobal(value);
                                  if (mounted) setState(_load);
                                },
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                child: _followGlobalSurface
                                    ? const SizedBox.shrink()
                                    : Column(
                                        children: [
                                          const SizedBox(height: 8),
                                          CompactSegmentedButton<
                                            AppSurfaceEffect
                                          >(
                                            expanded: true,
                                            segments: const [
                                              ButtonSegment(
                                                value: AppSurfaceEffect.solid,
                                                label: Text('透明'),
                                              ),
                                              ButtonSegment(
                                                value: AppSurfaceEffect.blur,
                                                label: Text('模糊'),
                                              ),
                                              ButtonSegment(
                                                value: AppSurfaceEffect.acrylic,
                                                label: Text('亚克力'),
                                              ),
                                            ],
                                            selected: {
                                              _navigationSurfaceEffect,
                                            },
                                            onSelectionChanged: (selection) {
                                              final effect = selection.first;
                                              setState(
                                                () => _navigationSurfaceEffect =
                                                    effect,
                                              );
                                              widget.prefs
                                                  .setNavigationSurfaceEffect(
                                                    effect,
                                                  );
                                            },
                                          ),
                                          _StyleSlider(
                                            label: '透明度',
                                            valueLabel:
                                                '${((1 - _navigationSurfaceOpacity) * 100).round()}%',
                                            value:
                                                1 - _navigationSurfaceOpacity,
                                            min: 0,
                                            max: 0.95,
                                            divisions: 95,
                                            onChanged: (value) => setState(
                                              () => _navigationSurfaceOpacity =
                                                  1 - value,
                                            ),
                                            onChangeEnd: (value) => widget.prefs
                                                .setNavigationSurfaceOpacity(
                                                  1 - value,
                                                ),
                                          ),
                                          AnimatedSize(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            child:
                                                _navigationSurfaceEffect ==
                                                    AppSurfaceEffect.solid
                                                ? const SizedBox.shrink()
                                                : _StyleSlider(
                                                    label: '模糊强度',
                                                    valueLabel:
                                                        _navigationSurfaceBlur
                                                            .round()
                                                            .toString(),
                                                    value:
                                                        _navigationSurfaceBlur,
                                                    min: 0,
                                                    max: 40,
                                                    divisions: 40,
                                                    onChanged: (value) => setState(
                                                      () =>
                                                          _navigationSurfaceBlur =
                                                              value,
                                                    ),
                                                    onChangeEnd: widget
                                                        .prefs
                                                        .setNavigationSurfaceBlur,
                                                  ),
                                          ),
                                        ],
                                      ),
                              ),
                              const Divider(height: 32),
                            ],
                            if (navigationBar)
                              const _StyleSectionHeader(
                                icon: Icons.crop_square_rounded,
                                label: '外层',
                              ),
                            CompactSwitch.tile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('跟随全局主题色'),
                              value: _followGlobalColor,
                              onChanged: automaticColor
                                  ? null
                                  : (value) {
                                      setState(
                                        () => _followGlobalColor = value,
                                      );
                                      widget.prefs.setCompactColorFollowsGlobal(
                                        widget.kind,
                                        value,
                                      );
                                    },
                            ),
                            _ColorTile(
                              title: navigationBar ? '外层颜色' : '组件颜色',
                              color: _followGlobalColor
                                  ? Color(widget.prefs.globalThemeColor)
                                  : _color,
                              enabled: !automaticColor && !_followGlobalColor,
                              disabledLabel: automaticColor
                                  ? '由自动取色控制'
                                  : '跟随全局主题色',
                              onTap: () => _pickColor(context),
                            ),
                            if (automaticColor)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '自动取色已接管颜色，可在主题设置中关闭。',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ),
                            if (!navigationBar || floatingNavigationBar)
                              _StyleSlider(
                                label: navigationBar ? '外层圆角' : '圆角',
                                valueLabel: '${_radius.round()} px',
                                value: _radius,
                                min: 0,
                                max: navigationBar ? 36 : 28,
                                divisions: navigationBar ? 36 : 28,
                                onChanged: (value) =>
                                    setState(() => _radius = value),
                                onChangeEnd: (value) => widget.prefs
                                    .setCompactBorderRadius(widget.kind, value),
                              ),
                            _StyleSlider(
                              label: navigationBar ? '外层高度' : '高度',
                              valueLabel: '${_height.round()} px',
                              value: _height,
                              min: navigationBar ? 52 : 32,
                              max: navigationBar ? 76 : 52,
                              divisions: navigationBar ? 24 : 20,
                              onChanged: (value) =>
                                  setState(() => _height = value),
                              onChangeEnd: (value) => widget.prefs
                                  .setCompactControlHeight(widget.kind, value),
                            ),
                            if (!navigationBar || floatingNavigationBar)
                              _StyleSlider(
                                label: navigationBar ? '外层长度' : '长度',
                                valueLabel: '${(_widthScale * 100).round()}%',
                                value: _widthScale,
                                min: 0.75,
                                max: 1.5,
                                divisions: 15,
                                onChanged: (value) =>
                                    setState(() => _widthScale = value),
                                onChangeEnd: (value) => widget.prefs
                                    .setCompactWidthScale(widget.kind, value),
                              ),
                            if (floatingNavigationBar)
                              _StyleSlider(
                                label: '高度偏移',
                                valueLabel: _signedPixels(
                                  _floatingHeightOffset,
                                ),
                                value: _floatingHeightOffset,
                                min: -20,
                                max: 20,
                                divisions: 40,
                                onChanged: (value) => setState(
                                  () => _floatingHeightOffset = value,
                                ),
                                onChangeEnd: widget
                                    .prefs
                                    .setNavigationFloatingHeightOffset,
                              ),
                            if (navigationBar) ...[
                              const Divider(height: 36),
                              const _StyleSectionHeader(
                                icon: Icons.toggle_on_outlined,
                                label: '内层',
                              ),
                              _ColorTile(
                                title: '内层颜色',
                                color: _innerColor,
                                enabled: !automaticColor,
                                onTap: () => _pickInnerColor(context),
                              ),
                              _StyleSlider(
                                label: '内层圆角',
                                valueLabel: '${_innerRadius.round()} px',
                                value: _innerRadius,
                                min: 0,
                                max: 36,
                                divisions: 36,
                                onChanged: (value) =>
                                    setState(() => _innerRadius = value),
                                onChangeEnd:
                                    widget.prefs.setNavigationInnerBorderRadius,
                              ),
                              _StyleSlider(
                                label: '内层高度',
                                valueLabel: '${_innerHeight.round()} px',
                                value: _innerHeight,
                                min: 24,
                                max: 68,
                                divisions: 44,
                                onChanged: (value) =>
                                    setState(() => _innerHeight = value),
                                onChangeEnd:
                                    widget.prefs.setNavigationInnerHeight,
                              ),
                              _StyleSlider(
                                label: '内层长度',
                                valueLabel:
                                    '${(_innerWidthScale * 100).round()}%',
                                value: _innerWidthScale,
                                min: 0.75,
                                max: 1.5,
                                divisions: 15,
                                onChanged: (value) =>
                                    setState(() => _innerWidthScale = value),
                                onChangeEnd:
                                    widget.prefs.setNavigationInnerWidthScale,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(CompactControlStyle style) {
    switch (widget.kind) {
      case CompactControlKind.button:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CompactMenuButton<int>(
              value: 0,
              label: 'Button',
              semanticLabel: '预览按钮',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Button')),
              ],
              onSelected: (_) {},
              style: style,
            ),
            const SizedBox(width: 12),
            CompactIconButton(
              semanticLabel: '预览图标按钮',
              icon: const Icon(Icons.tune),
              onPressed: () {},
              style: style,
            ),
          ],
        );
      case CompactControlKind.search:
        return SizedBox(
          width: (260 * _widthScale).clamp(
            180,
            MediaQuery.sizeOf(context).width - 32,
          ),
          child: CompactSearchField(
            controller: _searchController,
            hintText: 'Search',
            onChanged: (_) {},
            onClear: _searchController.clear,
            style: style,
          ),
        );
      case CompactControlKind.segmented:
        return CompactSegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Active')),
            ButtonSegment(value: 1, label: Text('Closed')),
          ],
          selected: {_previewSegment},
          onSelectionChanged: (selection) => setState(() {
            _previewSegment = selection.first;
          }),
          style: style,
        );
      case CompactControlKind.toggle:
        return CompactSwitch(
          value: _previewSwitchValue,
          onChanged: (value) => setState(() {
            _previewSwitchValue = value;
          }),
          style: style,
        );
      case CompactControlKind.navigationBar:
        final floating = widget.prefs.navLayout == NavLayout.floating;
        final borderRadius = floating ? style.borderRadius : BorderRadius.zero;
        final surfaceTheme = _navigationSurfaceTheme(context);
        final surface = AppSurfaceBackdrop(
          borderRadius: borderRadius,
          surfaceTheme: surfaceTheme,
          child: Container(
            height: style.buttonHeight,
            decoration: BoxDecoration(
              color: surfaceTheme.surfaceColor(style.background(context)),
              borderRadius: borderRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: BottomNavBarItems(
              style: widget.prefs.navBarStyle,
              styleConfig: style,
              destinations: const [
                AppNavDestination(
                  icon: Icons.space_dashboard_outlined,
                  label: '概览',
                ),
                AppNavDestination(
                  icon: Icons.account_tree_outlined,
                  label: '代理组',
                ),
                AppNavDestination(icon: Icons.lan_outlined, label: '连接'),
                AppNavDestination(icon: Icons.terminal, label: '日志'),
                AppNavDestination(icon: Icons.more_horiz, label: '更多'),
              ],
              selectedIndex: _previewNavigationIndex,
              onSelected: (index) => setState(() {
                _previewNavigationIndex = index;
              }),
            ),
          ),
        );
        final bar = AppBackdropGroup(child: surface);
        if (floating) {
          return SizedBox(
            width: (300 * _widthScale).clamp(
              220,
              MediaQuery.sizeOf(context).width - 32,
            ),
            child: Transform.translate(
              offset: Offset(0, -style.floatingHeightOffset),
              child: bar,
            ),
          );
        }
        return SizedBox(width: double.infinity, child: bar);
    }
  }

  Future<void> _pickColor(BuildContext context) async {
    final result = await showColorPalettePicker(
      context,
      title: '${widget.kind.label}颜色',
      color: _color,
    );
    if (result == null) return;
    setState(() {
      _color = result;
      if (widget.kind == CompactControlKind.navigationBar &&
          _innerColorFollowsOuter) {
        _innerColor = result;
      }
    });
    await widget.prefs.setCompactThemeColor(widget.kind, result.toARGB32());
  }

  Future<void> _pickInnerColor(BuildContext context) async {
    final result = await showColorPalettePicker(
      context,
      title: '导航栏内层颜色',
      color: _innerColor,
    );
    if (result == null) return;
    setState(() {
      _innerColor = result;
      _innerColorFollowsOuter = false;
    });
    await widget.prefs.setNavigationInnerThemeColor(result.toARGB32());
  }

  Future<void> _reset() async {
    await widget.prefs.resetCompactStyle(widget.kind);
    if (mounted) setState(_load);
  }
}
