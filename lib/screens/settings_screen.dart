import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../session.dart';
import '../widgets/section_panel.dart';
import 'core_config_screen.dart';
import 'resources_screen.dart';

/// "其他" — aggregator page that lists every settings/config destination
/// as a tile. Each tile pushes a dedicated screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
  });

  final ctl.ControllerStore store;
  final AppPrefs prefs;
  final MihomoSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Rebuild on prefs (nav layout decides whether to show core/resources)
      // and on isCmfa (CMFA hides 内核配置).
      listenable: Listenable.merge([prefs, session.isCmfa]),
      builder: (context, _) {
        // Cards layout already exposes 内核配置 and 外部资源 as launcher
        // hero cards, so hide them here to avoid two paths to the same page.
        final showResources = prefs.navLayout != NavLayout.cards;
        final showCore = showResources && !session.isCmfa.value;
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
                        _Tile(
                          icon: Icons.dns_outlined,
                          title: '后端设置',
                          subtitle: '管理 mihomo 后端实例',
                          onTap: () => _push(
                            context,
                            BackendSettingsScreen(store: store),
                          ),
                        ),
                        const Divider(height: 1),
                        _Tile(
                          icon: Icons.app_settings_alt_outlined,
                          title: '应用设置',
                          subtitle: '导航布局等',
                          onTap: () => _push(
                            context,
                            AppSettingsScreen(prefs: prefs),
                          ),
                        ),
                        if (showCore) ...[
                          const Divider(height: 1),
                          _Tile(
                            icon: Icons.memory_outlined,
                            title: '内核配置',
                            subtitle: '出站模式、日志级别、端口等',
                            onTap: () => _push(
                              context,
                              CoreConfigScreen(
                                store: store,
                                prefs: prefs,
                              ),
                            ),
                          ),
                        ],
                        if (showResources) ...[
                          const Divider(height: 1),
                          _Tile(
                            icon: Icons.cloud_outlined,
                            title: '外部资源',
                            subtitle: '代理订阅 / 规则集',
                            onTap: () => _push(
                              context,
                              ResourcesScreen(store: store),
                            ),
                          ),
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
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
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
  const AppSettingsScreen({super.key, required this.prefs});
  final AppPrefs prefs;

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
              child: AppSettingsPanel(prefs: prefs),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSettingsPanel extends StatelessWidget {
  const AppSettingsPanel({super.key, required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        return SectionPanel(
          title: '应用',
          icon: Icons.app_settings_alt_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '导航布局',
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
            ],
          ),
        );
      },
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
        baseUrl: result.baseUrl,
        secret: result.secret,
      );
    } else {
      await widget.store.update(
        existing.id,
        name: result.name,
        baseUrl: result.baseUrl,
        secret: result.secret,
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
    required this.baseUrl,
    required this.secret,
  });
  final String name;
  final String baseUrl;
  final String secret;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing});
  final ctl.Controller? existing;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _secret;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _baseUrl = TextEditingController(
      text: c?.baseUrl ?? 'http://127.0.0.1:9090',
    );
    _secret = TextEditingController(text: c?.secret ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
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
            TextFormField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'External Controller 地址',
                hintText: 'http://127.0.0.1:9090',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final u = Uri.tryParse(v?.trim() ?? '');
                if (u == null || !(u.isScheme('http') || u.isScheme('https'))) {
                  return '请输入合法的 http(s) URL';
                }
                return null;
              },
            ),
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
                baseUrl: _baseUrl.text.trim(),
                secret: _secret.text.trim(),
              ),
            );
          },
          child: Text(isNew ? '添加' : '保存'),
        ),
      ],
    );
  }
}
