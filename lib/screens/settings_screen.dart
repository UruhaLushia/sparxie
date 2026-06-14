import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../rust_api.dart' as rust;
import '../session.dart';
import '../utils.dart';
import '../widgets/section_panel.dart';
import 'core_actions_screen.dart';
import 'core_config_screen.dart';
import 'resources_screen.dart';
import 'rules_screen.dart';

/// "其他" — aggregator page that lists every settings/config destination
/// as a tile. Each tile pushes a dedicated screen.
///
/// [extras] are navigation destinations that overflowed the standard-layout
/// rail (too short a window to show them all). They're merged into the tile
/// list alongside the settings tiles so every page stays reachable.
///
/// [railManagesPages] is true in wide standard layout, where 核心配置 /
/// 外部资源 / 核心操作 / 分流规则 are rail destinations (or [extras] when they
/// overflow) — so their static tiles are suppressed here to avoid a second
/// path to the same page. 后端设置 / 应用设置 always live here.
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
    return ListenableBuilder(
      listenable: Listenable.merge([
        prefs,
        session.supportsCoreConfig,
        session.supportsCoreActions,
        session.supportsExternalResources,
      ]),
      builder: (context, _) {
        final isCards = prefs.navLayout == NavLayout.cards;
        // 分流规则 has a dedicated 规则 card in cards layout; in wide standard
        // it's a rail item. Only the compact bottom bar shows its tile here.
        final showRules = !isCards && !railManagesPages;
        final showCoreActions =
            !railManagesPages && session.supportsCoreActions.value;
        // 核心配置 / 外部资源 are hero cards in cards layout and rail items in
        // wide standard; only the compact bottom bar (neither) needs the
        // static tiles below.
        final showCoreResources = !isCards && !railManagesPages;
        final showCore = showCoreResources && session.supportsCoreConfig.value;
        final showResources =
            showCoreResources && session.supportsExternalResources.value;

        // Overflow rail items lead the list, then the settings tiles — one
        // flat section, no separate 导航 grouping.
        final tiles = <Widget>[
          for (final e in extras)
            _Tile(icon: e.icon, title: e.label, onTap: e.onTap),
          _Tile(
            icon: Icons.dns_outlined,
            title: '后端设置',
            subtitle: '管理后端实例',
            onTap: () => _push(context, BackendSettingsScreen(store: store)),
          ),
          _Tile(
            icon: Icons.app_settings_alt_outlined,
            title: '应用设置',
            subtitle: '导航布局等',
            onTap: () => _push(
              context,
              AppSettingsScreen(prefs: prefs, session: session),
            ),
          ),
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
              subtitle: '重载 / 重启 / 升级、清空缓存',
              onTap: () => _push(
                context,
                CoreActionsScreen(store: store, session: session),
              ),
            ),
          if (showRules)
            _Tile(
              icon: Icons.rule,
              title: '分流规则',
              subtitle: '查看与筛选当前规则',
              onTap: () => _push(context, RulesScreen(store: store)),
            ),
          if (showResources)
            _Tile(
              icon: Icons.cloud_outlined,
              title: '外部资源',
              subtitle: '代理订阅 / 规则集',
              onTap: () => _push(context, ResourcesScreen(store: store)),
            ),
        ];

        return Scaffold(
          appBar: AppBar(title: const Text('其他')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SectionPanel(
                    title: '配置',
                    icon: Icons.tune,
                    child: Column(
                      children: [
                        for (var i = 0; i < tiles.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          tiles[i],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// A navigation destination that overflowed the standard-layout rail and is
/// surfaced in the "其他" page's 导航 section instead.
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
      appBar: AppBar(title: const Text('后端设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
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
      appBar: AppBar(title: const Text('应用设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
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
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final showFontSettings =
            !kIsWeb &&
            (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
        return SectionPanel(
          title: '应用',
          icon: Icons.app_settings_alt_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导航布局', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<NavLayout>(
                showSelectedIcon: false,
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
                ],
                selected: {prefs.navLayout},
                onSelectionChanged: (s) => prefs.setNavLayout(s.first),
              ),
              const SizedBox(height: 6),
              Text(
                '卡片：窄屏首页用网格入口、宽屏侧栏用卡片;标准:NavigationBar / NavigationRail。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
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

/// Inline row showing the current UI font with a picker that lists installed
/// system fonts (enumerated by the Rust backend), each previewed in its own
/// face. Empty selection means "follow the system default".
class _FontRow extends StatelessWidget {
  const _FontRow({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final current = prefs.uiFontFamily;
    final label = current.isEmpty ? '跟随系统' : current;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('字体', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                label,
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
          child: const Text('选择'),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FontPicker(current: prefs.uiFontFamily),
    );
    // A non-null result is a deliberate choice ('' = follow system).
    if (picked != null) await prefs.setUiFontFamily(picked);
  }
}

class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.current});
  final String current;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  List<String>? _families;
  String _filter = '';

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final all = _families;
    final filtered = all == null
        ? const <String>[]
        : (_filter.isEmpty
              ? all
              : all
                    .where(
                      (f) => f.toLowerCase().contains(_filter.toLowerCase()),
                    )
                    .toList());
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索字体',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
            ),
            Expanded(
              child: all == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: filtered.length + 1,
                      itemBuilder: (context, index) {
                        final family = index == 0 ? '' : filtered[index - 1];
                        final selected = family == widget.current;
                        return ListTile(
                          title: Text(
                            family.isEmpty ? '跟随系统' : family,
                            style: family.isEmpty
                                ? null
                                : TextStyle(fontFamily: family),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, family),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineResourcesRow extends StatelessWidget {
  const _OnlineResourcesRow({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
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

class _BackendSettingsPanelState extends State<BackendSettingsPanel> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controllers = widget.store.controllers;
    final activeId = widget.store.activeId;
    final scheme = Theme.of(context).colorScheme;
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
              if (i > 0) const Divider(height: 1),
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
              style: FilledButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit({ctl.Controller? existing}) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await widget.store.add(
        name: result.name,
        type: result.type,
        baseUrl: result.baseUrl,
        secret: result.secret,
        allowInsecure: result.allowInsecure,
      );
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
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        active ? Icons.check_circle : Icons.dns_outlined,
        color: active ? scheme.primary : null,
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

class _EditResult {
  _EditResult({
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.secret,
    required this.allowInsecure,
  });
  final String name;
  final ctl.BackendType type;
  final String baseUrl;
  final String secret;
  final bool allowInsecure;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing});
  final ctl.Controller? existing;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

enum _Scheme { http, https, unix, pipe }

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

  List<_Scheme> get _schemes => [
    _Scheme.http,
    _Scheme.https,
    if (_supportsIpc && _isUnixHost) _Scheme.unix,
    if (_supportsIpc && _isWindows) _Scheme.pipe,
  ];

  static String _schemeLabel(_Scheme s) => switch (s) {
    _Scheme.http => 'http',
    _Scheme.https => 'https',
    _Scheme.unix => 'unix',
    _Scheme.pipe => 'pipe',
  };

  bool get _isIpc => _scheme == _Scheme.unix || _scheme == _Scheme.pipe;

  String get _defaultTcpAddress => switch (_type) {
    ctl.BackendType.clash => '127.0.0.1:9090',
    ctl.BackendType.surge => '127.0.0.1:6171',
  };

  String get _addressHint => switch (_scheme) {
    _Scheme.http || _Scheme.https => _defaultTcpAddress,
    _Scheme.unix => '/path/to/clash.sock',
    _Scheme.pipe => r'\\.\pipe\clash',
  };

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _type = c?.type ?? ctl.BackendType.clash;
    final (scheme, addr) = _decompose(c?.baseUrl ?? 'http://127.0.0.1:9090');
    _scheme = _schemes.contains(scheme) ? scheme : _Scheme.http;
    _address = TextEditingController(text: addr);
    _secret = TextEditingController(text: c?.secret ?? '');
    _allowInsecure = c?.allowInsecure ?? false;
  }

  void _setType(ctl.BackendType type) {
    final oldDefault = _defaultTcpAddress;
    setState(() {
      _type = type;
      if (!_schemes.contains(_scheme)) {
        _scheme = _Scheme.http;
      }
      final addr = _address.text.trim();
      if (addr.isEmpty || addr == oldDefault) {
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
      _Scheme.http => 'http://$addr',
      _Scheme.https => 'https://$addr',
      _Scheme.unix => 'unix:$addr',
      _Scheme.pipe => 'pipe:$addr',
    };
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
      title: Text(isNew ? '新增后端' : '编辑后端'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 116,
                  child: _SchemeDropdown(
                    scheme: _scheme,
                    schemes: _schemes,
                    label: _schemeLabel,
                    onChanged: (s) => setState(() => _scheme = s),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _address,
                    decoration: InputDecoration(
                      labelText: _isIpc ? '路径' : '地址',
                      hintText: _addressHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final addr = v?.trim() ?? '';
                      if (addr.isEmpty) {
                        return _isIpc ? '请输入路径' : '请输入地址';
                      }
                      return null;
                    },
                  ),
                ),
              ],
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('跳过证书验证'),
                subtitle: const Text('用于自签名 / 域名不匹配的 https 后端'),
                value: _allowInsecure,
                onChanged: (v) => setState(() => _allowInsecure = v),
              ),
            ],
          ],
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
              _EditResult(
                name: _name.text.trim(),
                type: _type,
                baseUrl: _composeUrl(),
                // Secret is only meaningful for TCP backends.
                secret: _isIpc ? '' : _secret.text.trim(),
                allowInsecure: _scheme == _Scheme.https && _allowInsecure,
              ),
            );
          },
          child: Text(isNew ? '添加' : '保存'),
        ),
      ],
    );
  }
}

/// Compact scheme prefix selector for the backend address field. Built as a
/// form field so it shares the exact box metrics of the address TextFormField
/// beside it (same border, height, baseline) and stays aligned.
class _SchemeDropdown extends StatelessWidget {
  const _SchemeDropdown({
    required this.scheme,
    required this.schemes,
    required this.label,
    required this.onChanged,
  });

  final _Scheme scheme;
  final List<_Scheme> schemes;
  final String Function(_Scheme) label;
  final ValueChanged<_Scheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<_Scheme>(
      initialValue: scheme,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '协议',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final s in schemes)
          DropdownMenuItem(value: s, child: Text(label(s))),
      ],
      onChanged: (s) {
        if (s != null) onChanged(s);
      },
    );
  }
}
