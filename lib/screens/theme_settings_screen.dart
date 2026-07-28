import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../platform_capabilities.dart';
import '../widgets/color_palette_picker.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/section_panel.dart';

/// Global theme and per-component appearance settings.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主题设置'),
        flexibleSpace: const DesktopAppBarDragArea(),
      ),
      body: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          final automaticColor = prefs.automaticColor;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              SectionPanel(
                title: '主题',
                icon: Icons.palette_outlined,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '主题模式',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CompactSegmentedButton<AppThemeMode>(
                      expanded: true,
                      segments: const [
                        ButtonSegment(
                          value: AppThemeMode.system,
                          label: Text('自动'),
                        ),
                        ButtonSegment(
                          value: AppThemeMode.light,
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: AppThemeMode.dark,
                          label: Text('深色'),
                        ),
                      ],
                      selected: {prefs.appThemeMode},
                      onSelectionChanged: (selection) =>
                          prefs.setAppThemeMode(selection.first),
                    ),
                    if (supportsCustomTitleBar) ...[
                      const Divider(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '窗口标题栏',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CompactSegmentedButton<DesktopTitleBarMode>(
                        expanded: true,
                        segments: const [
                          ButtonSegment(
                            value: DesktopTitleBarMode.system,
                            label: Text('系统'),
                            icon: Icon(Icons.web_asset_outlined),
                          ),
                          ButtonSegment(
                            value: DesktopTitleBarMode.custom,
                            label: Text('自绘'),
                            icon: Icon(Icons.dashboard_customize_outlined),
                          ),
                          ButtonSegment(
                            value: DesktopTitleBarMode.hidden,
                            label: Text('完全隐藏'),
                            icon: Icon(Icons.visibility_off_outlined),
                          ),
                        ],
                        selected: {prefs.desktopTitleBarMode},
                        onSelectionChanged: (selection) =>
                            prefs.setDesktopTitleBarMode(selection.first),
                      ),
                    ],
                    const Divider(height: 24),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动取色'),
                      subtitle: const Text('自动生成配色'),
                      value: automaticColor,
                      onChanged: prefs.setAutomaticColor,
                    ),
                    const Divider(height: 16),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('纯黑模式'),
                      subtitle: const Text('深色模式下使用 OLED 纯黑背景'),
                      value: prefs.pureBlackMode,
                      onChanged: prefs.setPureBlackMode,
                    ),
                    const Divider(height: 16),
                    _ColorTile(
                      title: '全局主题色',
                      color: Color(prefs.globalThemeColor),
                      enabled: !automaticColor,
                      onTap: () => _pickGlobalColor(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: '导航',
                icon: Icons.navigation_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompactSegmentedButton<NavLayout>(
                      expanded: true,
                      segments: const [
                        ButtonSegment(
                          value: NavLayout.cards,
                          label: Text('卡片'),
                          icon: Icon(Icons.dashboard_outlined),
                        ),
                        ButtonSegment(
                          value: NavLayout.standard,
                          label: Text('标准'),
                          icon: Icon(Icons.view_sidebar_outlined),
                        ),
                        ButtonSegment(
                          value: NavLayout.floating,
                          label: Text('悬浮'),
                          icon: Icon(Icons.panorama_fish_eye_outlined),
                        ),
                      ],
                      selected: {prefs.navLayout},
                      onSelectionChanged: (selection) =>
                          prefs.setNavLayout(selection.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '卡片使用页面入口；标准使用底栏或侧栏；悬浮使用圆角悬浮底栏。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: '组件',
                icon: Icons.widgets_outlined,
                child: Column(
                  children: [
                    for (
                      var i = 0;
                      i < CompactControlKind.values.length;
                      i++
                    ) ...[
                      _ComponentTile(
                        kind: CompactControlKind.values[i],
                        color: Color(
                          prefs.effectiveCompactThemeColor(
                            CompactControlKind.values[i],
                          ),
                        ),
                        colorEnabled: !automaticColor,
                        followsGlobal: prefs.compactColorFollowsGlobal(
                          CompactControlKind.values[i],
                        ),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ComponentStyleScreen(
                              prefs: prefs,
                              kind: CompactControlKind.values[i],
                            ),
                          ),
                        ),
                      ),
                      if (i != CompactControlKind.values.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickGlobalColor(BuildContext context) async {
    final result = await showColorPalettePicker(
      context,
      title: '全局主题色',
      color: Color(prefs.globalThemeColor),
    );
    if (result != null) {
      await prefs.setGlobalThemeColor(result.toARGB32());
    }
  }
}

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
    if (automaticColor) {
      return CompactControlStyle.fromColorScheme(
        colorScheme: Theme.of(context).colorScheme,
        borderRadius: _radius,
        controlHeight: _height,
        widthScale: _widthScale,
        indicatorBorderRadius: navigationBar ? _innerRadius : _radius,
        indicatorHeight: navigationBar ? _innerHeight : _height,
        indicatorWidthScale: navigationBar ? _innerWidthScale : _widthScale,
        floatingHeightOffset: _floatingHeightOffset,
      );
    }
    return CompactControlStyle.fromSeed(
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
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    final scheme = Theme.of(context).colorScheme;
    final automaticColor = widget.prefs.automaticColor;
    final navigationBar = widget.kind == CompactControlKind.navigationBar;
    final floatingNavigationBar =
        navigationBar && widget.prefs.navLayout == NavLayout.floating;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth > 792
        ? (screenWidth - 760) / 2
        : 16.0;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('${widget.kind.label}样式'),
        flexibleSpace: const DesktopAppBarDragArea(),
        actions: [
          TextButton(onPressed: _reset, child: const Text('重置')),
          const SizedBox(width: 8),
        ],
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
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.06),
                        blurRadius: 18,
                        spreadRadius: -8,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.72),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _scrollController,
                          builder: (context, child) {
                            final offset = _scrollController.hasClients
                                ? _scrollController.offset
                                : 0.0;
                            final progress = (offset / 20).clamp(0.0, 1.0);
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainer,
                                border: Border(
                                  bottom: BorderSide(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.35 + 0.35 * progress,
                                    ),
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.shadow.withValues(
                                      alpha: 0.08 * progress,
                                    ),
                                    blurRadius: 8 * progress,
                                    offset: Offset(0, 2 * progress),
                                  ),
                                ],
                              ),
                              child: child,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 15, 20, 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.tune_outlined,
                                    size: 18,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '外观',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
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
                                        '底栏样式',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
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
                                          label: Text('M3'),
                                        ),
                                      ],
                                      selected: {widget.prefs.navBarStyle},
                                      onSelectionChanged: (selection) {
                                        widget.prefs.setNavBarStyle(
                                          selection.first,
                                        );
                                        setState(_load);
                                      },
                                    ),
                                    const Divider(height: 24),
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
                                            widget.prefs
                                                .setCompactColorFollowsGlobal(
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
                                    enabled:
                                        !automaticColor && !_followGlobalColor,
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
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
                                      onChangeEnd: (value) =>
                                          widget.prefs.setCompactBorderRadius(
                                            widget.kind,
                                            value,
                                          ),
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
                                    onChangeEnd: (value) =>
                                        widget.prefs.setCompactControlHeight(
                                          widget.kind,
                                          value,
                                        ),
                                  ),
                                  if (!navigationBar || floatingNavigationBar)
                                    _StyleSlider(
                                      label: navigationBar ? '外层长度' : '长度',
                                      valueLabel:
                                          '${(_widthScale * 100).round()}%',
                                      value: _widthScale,
                                      min: 0.75,
                                      max: 1.5,
                                      divisions: 15,
                                      onChanged: (value) =>
                                          setState(() => _widthScale = value),
                                      onChangeEnd: (value) =>
                                          widget.prefs.setCompactWidthScale(
                                            widget.kind,
                                            value,
                                          ),
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
                                      onChangeEnd: widget
                                          .prefs
                                          .setNavigationInnerBorderRadius,
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
                                      onChanged: (value) => setState(
                                        () => _innerWidthScale = value,
                                      ),
                                      onChangeEnd: widget
                                          .prefs
                                          .setNavigationInnerWidthScale,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
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
        final bar = Container(
          height: style.buttonHeight,
          decoration: BoxDecoration(
            color: style.background(context),
            borderRadius: floating ? style.borderRadius : BorderRadius.zero,
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
        );
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
      title: '底栏内层颜色',
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

class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 58),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.6),
              thumbColor: scheme.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleSectionHeader extends StatelessWidget {
  const _StyleSectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.primary),
        const SizedBox(width: 7),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.title,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.disabledLabel = '由自动取色控制',
  });

  final String title;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final String disabledLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Opacity(
              opacity: enabled ? 1 : 0.58,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          enabled ? '#${_hex(color)}' : disabledLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: enabled ? color : scheme.primary,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
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

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.kind,
    required this.color,
    required this.colorEnabled,
    required this.followsGlobal,
    required this.onTap,
  });

  final CompactControlKind kind;
  final Color color;
  final bool colorEnabled;
  final bool followsGlobal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(kind.icon),
      title: Text(kind.label),
      subtitle: Text(
        !colorEnabled
            ? '自动取色'
            : followsGlobal
            ? '跟随全局'
            : '#${_hex(color)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

extension on CompactControlKind {
  String get label => switch (this) {
    CompactControlKind.button => '按钮',
    CompactControlKind.search => '搜索框',
    CompactControlKind.segmented => '分段选择',
    CompactControlKind.toggle => '开关',
    CompactControlKind.navigationBar => '底栏',
  };

  IconData get icon => switch (this) {
    CompactControlKind.button => Icons.smart_button_outlined,
    CompactControlKind.search => Icons.search,
    CompactControlKind.segmented => Icons.view_week_outlined,
    CompactControlKind.toggle => Icons.toggle_on_outlined,
    CompactControlKind.navigationBar => Icons.space_bar_outlined,
  };
}

String _hex(Color color) =>
    color.toARGB32().toRadixString(16).substring(2).toUpperCase();

String _signedPixels(double value) {
  final rounded = value.round();
  return '${rounded > 0 ? '+' : ''}$rounded px';
}
