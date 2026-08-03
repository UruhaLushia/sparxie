import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../imported_fonts.dart';
import '../rust_api.dart' as rust;
import '../session.dart';
import '../utils.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/app_background.dart';
import '../widgets/app_page_route.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/page_body_transition.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';
import 'about_screen.dart';
import 'core_actions_screen.dart';
import 'core_config_screen.dart';
import 'diagnostics_screen.dart';
import 'resources_screen.dart';
import 'rules_screen.dart';
import 'tailscale_screen.dart';
import 'theme_settings_screen.dart';

/// "更多" — aggregator page that lists every settings/config destination
/// as a tile. Each tile pushes a dedicated screen.
///
/// [extras] are navigation destinations that overflowed the standard-layout
/// rail (too short a window to show them all). They're merged into the tile
/// list alongside the settings tiles so every page stays reachable.
///
/// [railManagesPages] is true in wide standard layout, where 核心配置 /
/// 外部资源 / 核心操作 / 分流规则 can be rail destinations (or [extras] when they
/// overflow) — so their static tiles are suppressed here to avoid a second
/// path to the same page. 后端设置 / 主题设置 / 应用设置 always live here.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
    this.extras = const <SettingsExtra>[],
    this.railManagesPages = false,
  });

  final ctl.ControllerStore store;
  final AppPrefs prefs;
  final MihomoSession session;
  final List<SettingsExtra> extras;
  final bool railManagesPages;

  @override
  Widget build(BuildContext context) {
    return ActiveListenableBuilder(
      listenable: Listenable.merge([
        prefs,
        session.supportsCoreConfig,
        session.supportsCoreActions,
        session.supportsExternalResources,
        session.supportsRules,
        session.supportsTailscale,
        session.supportsDiagnostics,
      ]),
      builder: (context, _) {
        final isCards = prefs.navLayout == NavLayout.cards;
        // 分流规则 has a dedicated 规则 card in cards layout; in wide standard
        // it's a rail item. Only the compact bottom bar shows its tile here.
        final showRules =
            session.supportsRules.value && !isCards && !railManagesPages;
        final showTailscale =
            session.supportsTailscale.value && !isCards && !railManagesPages;
        final showDiagnostics =
            session.supportsDiagnostics.value && !isCards && !railManagesPages;
        final showCoreActions =
            !railManagesPages && session.supportsCoreActions.value;
        // 核心配置 / 外部资源 are hero cards in cards layout and rail items in
        // wide standard; only the compact bottom bar (neither) needs the
        // static tiles below.
        final showCoreResources = !isCards && !railManagesPages;
        final showCore = showCoreResources && session.supportsCoreConfig.value;
        final showResources =
            showCoreResources && session.supportsExternalResources.value;

        final pageTiles = <Widget>[
          for (final e in extras)
            _Tile(icon: e.icon, title: e.label, onTap: e.onTap),
        ];
        final toolTiles = <Widget>[
          if (showCore)
            _Tile(
              icon: Icons.memory_outlined,
              title: '核心配置',
              subtitle: '出站模式、日志级别、端口等',
              onTap: () =>
                  _push(context, CoreConfigScreen(store: store, prefs: prefs)),
            ),
          if (showCoreActions)
            _Tile(
              icon: Icons.build_outlined,
              title: '核心操作',
              subtitle: '重载、重启、升级与缓存维护',
              onTap: () => _push(
                context,
                CoreActionsScreen(store: store, session: session),
              ),
            ),
          if (showRules)
            _Tile(
              icon: Icons.rule_outlined,
              title: '分流规则',
              subtitle: '查看与筛选当前规则',
              onTap: () => _push(context, RulesScreen(store: store)),
            ),
          if (showDiagnostics)
            _Tile(
              icon: Icons.network_check_outlined,
              title: '网络工具',
              subtitle: '网络质量与 STUN 测试',
              onTap: () => _push(context, DiagnosticsScreen(store: store)),
            ),
          if (showTailscale)
            _Tile(
              icon: Icons.vpn_lock_outlined,
              title: 'Tailscale',
              subtitle: '状态、认证与网络信息',
              onTap: () => _push(context, TailscaleScreen(store: store)),
            ),
          if (showResources)
            _Tile(
              icon: Icons.cloud_outlined,
              title: '外部资源',
              subtitle: '代理订阅与规则集',
              onTap: () =>
                  _push(context, ResourcesScreen(store: store, prefs: prefs)),
            ),
        ];
        final settingsTiles = <Widget>[
          _Tile(
            icon: Icons.dns_outlined,
            title: '后端设置',
            subtitle: '管理后端实例与连接方式',
            onTap: () => _push(context, BackendSettingsScreen(store: store)),
          ),
          _Tile(
            icon: Icons.palette_outlined,
            title: '主题设置',
            subtitle: '主题颜色与组件外观',
            onTap: () => _push(context, ThemeSettingsScreen(prefs: prefs)),
          ),
          _Tile(
            icon: Icons.app_settings_alt_outlined,
            title: '应用设置',
            subtitle: '字体与缓存设置',
            onTap: () => _push(
              context,
              AppSettingsScreen(prefs: prefs, session: session),
            ),
          ),
          _Tile(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '版本信息与检查更新',
            onTap: () => _push(context, AboutScreen(prefs: prefs)),
          ),
        ];
        final groups = <Widget>[
          if (pageTiles.isNotEmpty)
            _SettingsGroup(
              title: '页面',
              icon: Icons.grid_view_rounded,
              children: pageTiles,
            ),
          if (toolTiles.isNotEmpty)
            _SettingsGroup(
              title: '工具',
              icon: Icons.construction_outlined,
              children: toolTiles,
            ),
          _SettingsGroup(
            title: '设置',
            icon: Icons.settings_outlined,
            children: settingsTiles,
          ),
        ];

        final scheme = Theme.of(context).colorScheme;
        final compactPage = MediaQuery.sizeOf(context).width < 600;
        return Scaffold(
          backgroundColor: AppSurfaceTheme.of(
            context,
          ).pageColor(scheme.surfaceContainerLowest),
          appBar: compactPage
              ? AppRouteAppBar(
                  child: AppBar(
                    leading: AppRouteAppBar.leadingOf(context),
                    automaticallyImplyLeading: false,
                    title: const Text('更多'),
                    flexibleSpace: const DesktopAppBarDragArea(),
                  ),
                )
              : null,
          body: AppPageBodyTransition(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 600;
                const maxContentWidth = 720.0;
                final centeredGutter =
                    (constraints.maxWidth - maxContentWidth) / 2;
                final horizontal = compact
                    ? 12.0
                    : centeredGutter > 20
                    ? centeredGutter
                    : 20.0;
                return AppBackdropGroup(
                  child: CustomScrollView(
                    slivers: [
                      if (!compact)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            28,
                            horizontal,
                            8,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              '更多',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          compact ? 12 : 8,
                          horizontal,
                          20 + MediaQuery.paddingOf(context).bottom,
                        ),
                        sliver: SliverList.list(
                          children: [
                            for (var i = 0; i < groups.length; i++) ...[
                              if (i > 0) const SizedBox(height: 14),
                              groups[i],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(AppPageRoute<void>(builder: (_) => page));
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      minTileHeight: 68,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: PanelIconChip(icon: icon),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.06),
      onTap: onTap,
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanelSurface(
      groupBackdrop: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 64),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A navigation destination that overflowed the standard-layout rail and is
/// surfaced in the "更多" page's 页面 section instead.
class SettingsExtra {
  const SettingsExtra({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class BackendSettingsScreen extends StatelessWidget {
  const BackendSettingsScreen({super.key, required this.store});
  final ctl.ControllerStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('后端设置'),
          flexibleSpace: const DesktopAppBarDragArea(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            MaxWidthContent(
              maxWidth: 720,
              child: BackendSettingsPanel(store: store),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({
    super.key,
    required this.prefs,
    required this.session,
  });
  final AppPrefs prefs;
  final MihomoSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('应用设置'),
          flexibleSpace: const DesktopAppBarDragArea(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            MaxWidthContent(
              maxWidth: 720,
              child: AppSettingsPanel(prefs: prefs, session: session),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSettingsPanel extends StatelessWidget {
  const AppSettingsPanel({
    super.key,
    required this.prefs,
    required this.session,
  });
  final AppPrefs prefs;
  final MihomoSession session;

  @override
  Widget build(BuildContext context) {
    return ActiveListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final showFontSettings = !kIsWeb;
        return SectionPanel(
          title: '应用',
          icon: Icons.app_settings_alt_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showFontSettings) ...[
                _FontRow(prefs: prefs),
                const Divider(height: 24),
              ],
              _OnlineResourcesRow(prefs: prefs),
              const Divider(height: 24),
              _CacheRow(session: session),
            ],
          ),
        );
      },
    );
  }
}

/// Inline row showing the ordered UI font set. Empty selection means "follow
/// the system default".
class _FontRow extends StatelessWidget {
  const _FontRow({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final families = prefs.uiFontFamilies;
    final label = families.isEmpty
        ? '跟随系统'
        : families.map(_fontLabel).join(' / ');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('字体集', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () => _pick(context),
          child: const Text('编辑'),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FontSetEditor(prefs: prefs),
    );
  }
}

class _FontSetEditor extends StatefulWidget {
  const _FontSetEditor({required this.prefs});
  final AppPrefs prefs;

  @override
  State<_FontSetEditor> createState() => _FontSetEditorState();
}

class _FontSetEditorState extends State<_FontSetEditor> {
  List<String>? _families;
  late final List<String> _selected;
  final _fontMenuController = TextEditingController();
  bool _importingFont = false;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.of(widget.prefs.uiFontFamilies);
    rust
        .systemFontFamilies()
        .then((list) {
          if (mounted) setState(() => _families = list);
        })
        .catchError((_) {
          if (mounted) setState(() => _families = const []);
        });
  }

  @override
  void dispose() {
    _fontMenuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = _families;
    final available = all == null ? const <String>[] : _availableFamilies(all);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '字体集',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '导入字体文件',
                        onPressed: _importingFont ? null : _importFont,
                        icon: _importingFont
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                      ),
                      TextButton.icon(
                        onPressed: _selected.isEmpty ? null : _clearFamilies,
                        icon: const Icon(Icons.clear_all),
                        label: const Text('清空'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) => DropdownMenu<String>(
                      key: ValueKey(available.length),
                      controller: _fontMenuController,
                      enabled: all != null && available.isNotEmpty,
                      width: constraints.maxWidth,
                      menuHeight: 320,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      leadingIcon: const Icon(Icons.font_download_outlined),
                      hintText: all == null
                          ? '加载字体集'
                          : available.isEmpty
                          ? '没有可添加字体'
                          : '添加字体',
                      inputDecorationTheme: InputDecorationThemeData(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      dropdownMenuEntries: [
                        for (final family in available)
                          DropdownMenuEntry(
                            value: family,
                            label: _fontLabel(family),
                            labelWidget: Text(
                              _fontLabel(family),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _fontPreviewStyle(context, family),
                            ),
                          ),
                      ],
                      onSelected: _addFamily,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: all == null
                  ? const Center(child: CircularProgressIndicator())
                  : _selected.isEmpty
                  ? const Center(child: Text('跟随系统'))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.fromLTRB(
                        8,
                        4,
                        8,
                        16 + MediaQuery.paddingOf(context).bottom,
                      ),
                      proxyDecorator: _fontDragProxy,
                      itemCount: _selected.length,
                      onReorderItem: _reorderFamily,
                      itemBuilder: (context, index) {
                        final family = _selected[index];
                        final isPrimary = index == 0;
                        return Padding(
                          key: ValueKey(family),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: _FontFamilyTile(
                            family: family,
                            subtitle: isPrimary ? '主字体' : '备用字体',
                            dragHandle: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            onRemove: () => _removeFamily(index),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fontDragProxy(Widget child, int index, Animation<double> animation) {
    final shadowColor = Theme.of(context).colorScheme.shadow;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Transform.scale(
          scale: 1 + t * 0.01,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: shadowColor.withValues(alpha: 0.10 * t),
                  blurRadius: 10 * t,
                  offset: Offset(0, 3 * t),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }

  List<String> _availableFamilies(List<String> all) {
    final selected = _selected.toSet();
    final known = <String>{};
    final rest = <String>[];
    for (final family in [
      ...all,
      for (final font in widget.prefs.importedFonts) font.family,
    ]) {
      if (family == AppPrefs.systemFontFamily) continue;
      if (!selected.contains(family) && known.add(family)) {
        rest.add(family);
      }
    }
    rest.sort(_compareFamilies);
    return [
      if (!selected.contains(AppPrefs.systemFontFamily))
        AppPrefs.systemFontFamily,
      ...rest,
    ];
  }

  int _compareFamilies(String a, String b) {
    final lower = a.toLowerCase().compareTo(b.toLowerCase());
    return lower == 0 ? a.compareTo(b) : lower;
  }

  void _addFamily(String? family) {
    _fontMenuController.clear();
    if (family == null || _selected.contains(family)) return;
    setState(() => _selected.add(family));
    _saveFamilies();
  }

  Future<void> _removeFamily(int index) async {
    final family = _selected[index];
    setState(() => _selected.removeAt(index));
    _saveFamilies();
    await _deleteImportedFont(family);
  }

  Future<void> _clearFamilies() async {
    final families = List<String>.of(_selected);
    setState(_selected.clear);
    _saveFamilies();
    for (final family in families) {
      await _deleteImportedFont(family);
    }
  }

  void _reorderFamily(int oldIndex, int newIndex) {
    setState(() {
      final family = _selected.removeAt(oldIndex);
      _selected.insert(newIndex, family);
    });
    _saveFamilies();
  }

  Future<void> _importFont() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Font files',
          extensions: ['ttf', 'otf', 'ttc', 'otc'],
          uniformTypeIdentifiers: [
            'public.font',
            'public.truetype-font',
            'public.opentype-font',
            'public.truetype-ttf-font',
            'public.truetype-collection-font',
          ],
        ),
      ],
    );
    if (file == null || !mounted) return;

    setState(() => _importingFont = true);
    ImportedFont? imported;
    try {
      final newFont = await ImportedFonts.importFile(
        file.path,
        reservedFamilies: {
          AppPrefs.systemFontFamily,
          ..._selected,
          ...?_families,
          for (final font in widget.prefs.importedFonts) font.family,
        },
      );
      imported = newFont;
      await widget.prefs.addImportedFont(newFont);
      if (!mounted) return;
      setState(() {
        _selected.add(newFont.family);
        _importingFont = false;
      });
      _saveFamilies();
    } catch (e) {
      if (imported != null) {
        await ImportedFonts.delete(imported).catchError((_) {});
      }
      if (!mounted) return;
      setState(() => _importingFont = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('字体导入失败：$e')));
    }
  }

  Future<void> _deleteImportedFont(String family) async {
    final imports = widget.prefs.importedFonts;
    final index = imports.indexWhere((font) => font.family == family);
    if (index < 0) return;

    final font = imports[index];
    final next = List<ImportedFont>.of(imports)..removeAt(index);
    await widget.prefs.setImportedFonts(next);
    await ImportedFonts.delete(font).catchError((_) {});
  }

  void _saveFamilies() {
    unawaited(widget.prefs.setUiFontFamilies(List<String>.of(_selected)));
  }
}

class _FontFamilyTile extends StatelessWidget {
  const _FontFamilyTile({
    required this.family,
    required this.subtitle,
    required this.dragHandle,
    required this.onRemove,
  });

  final String family;
  final String subtitle;
  final Widget dragHandle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 54,
        dense: true,
        minLeadingWidth: 28,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsetsDirectional.only(start: 14, end: 4),
        leading: IconTheme.merge(
          data: IconThemeData(
            color: theme.colorScheme.onSurfaceVariant,
            size: 22,
          ),
          child: dragHandle,
        ),
        title: Text(
          _fontLabel(family),
          overflow: TextOverflow.ellipsis,
          style: _fontPreviewStyle(context, family),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          tooltip: '移除',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          icon: const Icon(Icons.close),
          onPressed: onRemove,
        ),
      ),
    );
  }
}

String _fontLabel(String family) =>
    family == AppPrefs.systemFontFamily ? '系统' : family;

TextStyle? _fontPreviewStyle(BuildContext context, String family) {
  if (family == AppPrefs.systemFontFamily) return null;
  final base = Theme.of(context).textTheme.bodyMedium;
  // A preview family replaces the theme primary, so restore that whole chain.
  final fallback = <String>[];

  void add(String? candidate) {
    if (candidate != null &&
        candidate != family &&
        !fallback.contains(candidate)) {
      fallback.add(candidate);
    }
  }

  add(base?.fontFamily);
  for (final candidate in base?.fontFamilyFallback ?? const <String>[]) {
    add(candidate);
  }
  return TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback.isEmpty ? null : fallback,
  );
}

class _OnlineResourcesRow extends StatelessWidget {
  const _OnlineResourcesRow({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return CompactSwitch.tile(
      contentPadding: EdgeInsets.zero,
      title: const Text('跳过在线资源证书验证'),
      subtitle: const Text('用于图标 URL 等在线资源;不影响后端连接设置'),
      value: prefs.allowInsecureOnlineResources,
      onChanged: prefs.setAllowInsecureOnlineResources,
    );
  }
}

/// Shows the on-disk cache size (icons + process icons/names) with a clear
/// button. Size is fetched from Rust and refreshed after a clear.
class _CacheRow extends StatefulWidget {
  const _CacheRow({required this.session});
  final MihomoSession session;

  @override
  State<_CacheRow> createState() => _CacheRowState();
}

class _CacheRowState extends State<_CacheRow> {
  BigInt? _size;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final size = await rust.iconCacheSize();
      if (mounted) setState(() => _size = size);
    } catch (_) {
      if (mounted) setState(() => _size = null);
    }
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await rust.clearIconCache();
      widget.session.processIcons.clearAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清理失败:$e')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sizeText = _size == null ? '—' : formatBytes(_size!);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('缓存', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                '图标与进程信息 · $sizeText',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _clearing ? null : _clear,
          icon: _clearing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline, size: 18),
          label: const Text('清空缓存'),
        ),
      ],
    );
  }
}

class BackendSettingsPanel extends StatefulWidget {
  const BackendSettingsPanel({super.key, required this.store});
  final ctl.ControllerStore store;

  @override
  State<BackendSettingsPanel> createState() => _BackendSettingsPanelState();
}

Future<ctl.ControllerDraft?> showControllerEditorDialog(
  BuildContext context, {
  ctl.Controller? existing,
  ctl.ControllerDraft? initial,
  bool importMode = false,
}) {
  assert(existing == null || initial == null);
  return showDialog<ctl.ControllerDraft>(
    context: context,
    builder: (_) => _EditDialog(
      existing: existing,
      initial: initial,
      importMode: importMode,
    ),
  );
}

class _BackendSettingsPanelState extends State<BackendSettingsPanel> {
  var _active = true;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = isUiActive(context);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted && _active) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controllers = widget.store.controllers;
    final activeId = widget.store.activeId;
    return SectionPanel(
      title: '后端',
      icon: Icons.dns_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controllers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '还没有后端，点击下方“新增”按钮添加',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (var i = 0; i < controllers.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 64),
              _ControllerTile(
                controller: controllers[i],
                active: controllers[i].id == activeId,
                canRemove: controllers.length > 1,
                onActivate: () => widget.store.activate(controllers[i].id),
                onEdit: () => _edit(existing: controllers[i]),
                onRemove: () => _confirmRemove(controllers[i]),
              ),
            ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增后端'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit({ctl.Controller? existing}) async {
    final result = await showControllerEditorDialog(
      context,
      existing: existing,
    );
    if (result == null) return;
    if (existing == null) {
      await widget.store.addDraft(result);
    } else {
      await widget.store.update(
        existing.id,
        name: result.name,
        type: result.type,
        baseUrl: result.baseUrl,
        secret: result.secret,
        allowInsecure: result.allowInsecure,
      );
    }
  }

  Future<void> _confirmRemove(ctl.Controller c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除后端'),
        content: Text('确定要删除“${c.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.store.remove(c.id);
  }
}

class _ControllerTile extends StatelessWidget {
  const _ControllerTile({
    required this.controller,
    required this.active,
    required this.canRemove,
    required this.onActivate,
    required this.onEdit,
    required this.onRemove,
  });

  final ctl.Controller controller;
  final bool active;
  final bool canRemove;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: PanelIconChip(
        icon: active ? Icons.check_rounded : Icons.dns_outlined,
        active: active,
      ),
      title: Text(controller.name),
      subtitle: Text(
        [
          controller.type.label,
          controller.baseUrl,
          if (controller.secret.isNotEmpty) '已设置密钥',
        ].join('  •  '),
      ),
      onTap: active ? null : onActivate,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'activate':
              onActivate();
            case 'edit':
              onEdit();
            case 'remove':
              onRemove();
          }
        },
        itemBuilder: (context) => [
          if (!active)
            const PopupMenuItem(value: 'activate', child: Text('设为当前')),
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          if (canRemove)
            const PopupMenuItem(value: 'remove', child: Text('删除')),
        ],
      ),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing, this.initial, this.importMode = false});
  final ctl.Controller? existing;
  final ctl.ControllerDraft? initial;
  final bool importMode;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

enum _Scheme { http, https, unix, pipe, sparkleService }

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _secret;
  late ctl.BackendType _type;
  late bool _allowInsecure;
  late _Scheme _scheme;
  final _formKey = GlobalKey<FormState>();

  static bool get _isWindows => !kIsWeb && Platform.isWindows;
  static bool get _isUnixHost =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isAndroid);

  bool get _supportsIpc => _type == ctl.BackendType.clash;
  bool get _canUseIpc => _supportsIpc && (_isUnixHost || _isWindows);
  bool get _canUseSparkleService =>
      _supportsIpc &&
      !kIsWeb &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  bool get _isIpc =>
      _scheme == _Scheme.unix ||
      _scheme == _Scheme.pipe ||
      _scheme == _Scheme.sparkleService;
  bool get _isDirectIpc => _scheme == _Scheme.unix || _scheme == _Scheme.pipe;
  bool get _isSparkleService => _scheme == _Scheme.sparkleService;

  String get _defaultTcpAddress => switch (_type) {
    ctl.BackendType.clash => '127.0.0.1:9090',
    ctl.BackendType.surge => '127.0.0.1:6171',
    ctl.BackendType.singBox => '127.0.0.1:9091',
  };

  String get _addressHint => switch (_scheme) {
    _Scheme.http || _Scheme.https => _defaultTcpAddress,
    _Scheme.unix => '/path/to/clash.sock',
    _Scheme.pipe => r'\\.\pipe\clash',
    _Scheme.sparkleService => '默认读取 Sparkle service-auth.json',
  };

  List<_Scheme> get _schemeOptions => [
    _Scheme.http,
    _Scheme.https,
    if (_canUseIpc) _isWindows ? _Scheme.pipe : _Scheme.unix,
    if (_canUseSparkleService) _Scheme.sparkleService,
  ];

  String _schemeLabel(_Scheme scheme) => switch (scheme) {
    _Scheme.http => _type == ctl.BackendType.singBox ? 'gRPC' : 'HTTP',
    _Scheme.https => _type == ctl.BackendType.singBox ? 'gRPC TLS' : 'HTTPS',
    _Scheme.unix || _Scheme.pipe => 'IPC',
    _Scheme.sparkleService => 'Sparkle 服务',
  };

  String get _addressLabel {
    if (_isSparkleService) return '鉴权文件';
    if (_isDirectIpc) return '路径';
    return _type == ctl.BackendType.singBox ? 'gRPC 地址' : '地址';
  }

  String get _tlsSkipSubtitle => _type == ctl.BackendType.singBox
      ? '用于自签名 / 域名不匹配的 gRPC TLS 后端'
      : '用于自签名 / 域名不匹配的 https 后端';

  static bool _isIpcScheme(_Scheme scheme) =>
      scheme == _Scheme.unix ||
      scheme == _Scheme.pipe ||
      scheme == _Scheme.sparkleService;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    final initial = widget.initial;
    _name = TextEditingController(text: c?.name ?? initial?.name ?? '');
    _type = c?.type ?? initial?.type ?? ctl.BackendType.clash;
    final (scheme, addr) = _decompose(
      c?.baseUrl ?? initial?.baseUrl ?? 'http://127.0.0.1:9090',
    );
    final allowed = _isSchemeAllowed(scheme);
    _scheme = allowed ? scheme : _Scheme.http;
    _address = TextEditingController(text: allowed ? addr : _defaultTcpAddress);
    _secret = TextEditingController(text: c?.secret ?? initial?.secret ?? '');
    _allowInsecure = c?.allowInsecure ?? initial?.allowInsecure ?? false;
  }

  void _setType(ctl.BackendType type) {
    if (type == _type) return;
    final oldDefault = _defaultTcpAddress;
    final oldScheme = _scheme;
    setState(() {
      _type = type;
      if (!_isSchemeAllowed(_scheme)) {
        _scheme = _Scheme.http;
      }
      final addr = _address.text.trim();
      if (addr.isEmpty || addr == oldDefault || _isIpcScheme(oldScheme)) {
        _address.text = _defaultTcpAddress;
      }
    });
  }

  bool _isSchemeAllowed(_Scheme scheme) {
    if (scheme == _Scheme.http || scheme == _Scheme.https) return true;
    if (!_supportsIpc) return false;
    return switch (scheme) {
      _Scheme.unix => _isUnixHost,
      _Scheme.pipe => _isWindows,
      _Scheme.sparkleService => _canUseSparkleService,
      _ => false,
    };
  }

  void _setScheme(_Scheme scheme) {
    if (scheme == _scheme || !_isSchemeAllowed(scheme)) return;
    final oldDefault = _defaultTcpAddress;
    final oldHint = _addressHint;
    final oldScheme = _scheme;
    setState(() {
      _scheme = scheme;
      if (_isIpc) _allowInsecure = false;

      final addr = _address.text.trim();
      if (_isSparkleService) {
        if (addr.isEmpty || addr == oldDefault || addr == oldHint) {
          _address.clear();
        }
        return;
      }
      if (_isDirectIpc) {
        if (addr.isEmpty ||
            addr == oldDefault ||
            oldScheme == _Scheme.sparkleService) {
          _address.text = _addressHint;
        }
        return;
      }
      if (addr.isEmpty ||
          addr == oldHint ||
          oldScheme == _Scheme.sparkleService) {
        _address.text = _defaultTcpAddress;
      }
    });
  }

  /// Split a stored baseUrl into (scheme, address-without-scheme).
  static (_Scheme, String) _decompose(String url) {
    final u = url.trim();
    if (u.startsWith('unix:')) {
      return (_Scheme.unix, _stripLeadingSlashes(u.substring('unix:'.length)));
    }
    if (u.startsWith('pipe:')) {
      return (_Scheme.pipe, _stripLeadingSlashes(u.substring('pipe:'.length)));
    }
    if (u == 'sparkle-service' || u.startsWith('sparkle-service:')) {
      return (
        _Scheme.sparkleService,
        _stripLeadingSlashes(
          u.substring('sparkle-service'.length).replaceFirst(':', ''),
        ),
      );
    }
    if (u.startsWith('grpcs://')) {
      return (_Scheme.https, u.substring('grpcs://'.length));
    }
    if (u.startsWith('grpc://')) {
      return (_Scheme.http, u.substring('grpc://'.length));
    }
    if (u.startsWith('https://')) {
      return (_Scheme.https, u.substring('https://'.length));
    }
    if (u.startsWith('http://')) {
      return (_Scheme.http, u.substring('http://'.length));
    }
    return (_Scheme.http, u);
  }

  static String _stripLeadingSlashes(String s) =>
      s.startsWith('//') ? s.substring(2) : s;

  String _composeUrl() {
    final addr = _address.text.trim();
    return switch (_scheme) {
      _Scheme.http =>
        '${_type == ctl.BackendType.singBox ? 'grpc' : 'http'}://$addr',
      _Scheme.https =>
        '${_type == ctl.BackendType.singBox ? 'grpcs' : 'https'}://$addr',
      _Scheme.unix => 'unix:$addr',
      _Scheme.pipe => 'pipe:$addr',
      _Scheme.sparkleService =>
        addr.isEmpty ? 'sparkle-service:' : 'sparkle-service:$addr',
    };
  }

  Future<void> _pickAuthFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
        XTypeGroup(label: 'All files'),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _address.text = file.path);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.importMode ? '导入目标服务' : (isNew ? '新增后端' : '编辑后端')),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: !widget.importMode,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：家用机',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '名称不能为空' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ctl.BackendType>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '后端类型',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final type in ctl.BackendType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (type) {
                  if (type != null) _setType(type);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_Scheme>(
                initialValue: _scheme,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '连接方式',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final scheme in _schemeOptions)
                    DropdownMenuItem(
                      value: scheme,
                      child: Text(_schemeLabel(scheme)),
                    ),
                ],
                onChanged: (scheme) {
                  if (scheme != null) _setScheme(scheme);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: InputDecoration(
                  labelText: _addressLabel,
                  hintText: _addressHint,
                  border: OutlineInputBorder(),
                  suffixIcon: _isSparkleService
                      ? IconButton(
                          tooltip: '选择鉴权文件',
                          icon: const Icon(Icons.folder_open_outlined),
                          onPressed: _pickAuthFile,
                        )
                      : null,
                ),
                validator: (v) {
                  final addr = v?.trim() ?? '';
                  if (_isSparkleService) return null;
                  if (addr.isEmpty) {
                    return _isDirectIpc ? '请输入路径' : '请输入地址';
                  }
                  return null;
                },
              ),
              if (!_isIpc) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secret,
                  decoration: const InputDecoration(
                    labelText: '密钥 (可选)',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
              ],
              if (_scheme == _Scheme.https) ...[
                const SizedBox(height: 4),
                CompactSwitch.tile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('跳过证书验证'),
                  subtitle: Text(_tlsSkipSubtitle),
                  value: _allowInsecure,
                  onChanged: (v) => setState(() => _allowInsecure = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              ctl.ControllerDraft(
                name: _name.text.trim(),
                type: _type,
                baseUrl: _composeUrl(),
                // Secret is only meaningful for TCP backends.
                secret: _isIpc ? '' : _secret.text.trim(),
                allowInsecure: _scheme == _Scheme.https && _allowInsecure,
              ),
            );
          },
          child: Text(widget.importMode ? '导入' : (isNew ? '添加' : '保存')),
        ),
      ],
    );
  }
}
