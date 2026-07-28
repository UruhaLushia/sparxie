import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../widgets/color_palette_picker.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/compact_controls.dart';
import '../widgets/section_panel.dart';

/// Global theme and per-component appearance settings.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
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
                          prefs.compactThemeColor(CompactControlKind.values[i]),
                        ),
                        colorEnabled: !automaticColor,
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
      seedColor: _color,
      selectedSeedColor: navigationBar ? _innerColor : null,
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
    final automaticColor = widget.prefs.automaticColor;
    final navigationBar = widget.kind == CompactControlKind.navigationBar;
    final floatingNavigationBar =
        navigationBar && widget.prefs.navLayout == NavLayout.floating;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.kind.label}样式'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('重置')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 82,
            child: navigationBar
                ? Align(
                    alignment: const Alignment(0, -0.12),
                    child: _preview(style),
                  )
                : Center(child: _preview(style)),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _scrollController,
                          builder: (context, child) {
                            final offset = _scrollController.hasClients
                                ? _scrollController.offset
                                : 0.0;
                            final progress = (offset / 20).clamp(0.0, 1.0);
                            final scheme = Theme.of(context).colorScheme;
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.45 * progress,
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
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                            child: Row(
                              children: [
                                const Icon(Icons.tune_outlined, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  '外观',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '外层',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                    ),
                                  _ColorTile(
                                    title: navigationBar ? '外层颜色' : '组件颜色',
                                    color: _color,
                                    enabled: !automaticColor,
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
                                    const Divider(height: 24),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '内层',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              valueLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
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
  });

  final String title;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      title: Text(title),
      subtitle: Text(enabled ? '#${_hex(color)}' : '由自动取色控制'),
      trailing: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? color : Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.kind,
    required this.color,
    required this.colorEnabled,
    required this.onTap,
  });

  final CompactControlKind kind;
  final Color color;
  final bool colorEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(kind.icon),
      title: Text(kind.label),
      subtitle: Text(colorEnabled ? '#${_hex(color)}' : '自动取色'),
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
