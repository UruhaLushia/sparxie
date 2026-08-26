import 'package:flutter/material.dart';

import '../core/core_controller.dart';
import '../widgets/app_page_route.dart';
import 'core_access_screen.dart';
import '../rust_api.dart' as rust;
import '../widgets/compact_controls.dart';
import '../widgets/section_panel.dart';

class CoreConfigScreen extends StatefulWidget {
  const CoreConfigScreen({super.key, required this.core});

  final CoreController core;

  @override
  State<CoreConfigScreen> createState() => _CoreConfigScreenState();
}

class _CoreConfigScreenState extends State<CoreConfigScreen> {
  void _applyTun(rust.TunSettings Function(rust.TunSettings current) update) {
    widget.core.updateTun(update);
  }

  Future<void> _applyPorts({
    required int mixed,
    required int port,
    required int socks,
    required bool allowLan,
  }) {
    return widget.core.updateSettings(
      (settings) => rust.CoreConfig(
        mixedPort: mixed,
        port: port,
        socksPort: socks,
        allowLan: allowLan,
        logLevel: settings.logLevel,
        externalController: settings.externalController,
        secret: settings.secret,
        tun: settings.tun,
      ),
    );
  }

  Future<void> _openCustomBypass(rust.TunSettings tun) async {
    final saved = await Navigator.of(context).push<List<String>>(
      AppPageRoute(
        builder: (_) => CustomBypassScreen(
          initial: tun.bypassCustom
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        ),
      ),
    );
    if (saved != null) {
      _applyTun((current) => current.copyWith(bypassCustom: saved.join(',')));
    }
  }

  Future<void> _applyController({
    required bool enabled,
    required String address,
    required String secret,
  }) {
    return widget.core.updateSettings(
      (settings) => rust.CoreConfig(
        mixedPort: settings.mixedPort,
        port: settings.port,
        socksPort: settings.socksPort,
        allowLan: settings.allowLan,
        logLevel: settings.logLevel,
        externalController: enabled ? address : '',
        secret: secret,
        tun: settings.tun,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final core = widget.core;
    return Scaffold(
      appBar: AppBar(title: const Text('基础配置')),
      body: ListenableBuilder(
        listenable: core,
        builder: (context, _) {
          final settings = core.settings;
          final tun = settings.tun;
          final running = core.running;
          final tunIpv6 = core.tunIpv6;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PortsPanel(
                settings: settings,
                running: running,
                onApply: _applyPorts,
              ),
              const SizedBox(height: 16),
              _ControllerPanel(
                settings: settings,
                running: running,
                onApply: _applyController,
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: 'TUN (VPN)',
                icon: Icons.vpn_lock_outlined,
                child: Column(
                  children: [
                    if (core.tunAttached && tun.ipv6 && !tunIpv6)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: const Text('IPv6 不可用'),
                        subtitle: const Text(
                          '当前设备无法分配 IPv6 隧道地址，已使用 IPv4-only',
                        ),
                      ),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用 TUN'),
                      subtitle: const Text('通过系统 VPN 接管设备流量'),
                      value: tun.enabled,
                      onChanged: running
                          ? null
                          : (v) => _applyTun(
                              (current) => current.copyWith(enabled: v),
                            ),
                    ),
                    const Divider(height: 1, indent: 64),
                    _TunSegmentedRow<String>(
                      label: '协议栈',
                      segments: const [
                        ButtonSegment(value: 'system', label: Text('System')),
                        ButtonSegment(value: 'gvisor', label: Text('gVisor')),
                        ButtonSegment(value: 'mixed', label: Text('Mixed')),
                      ],
                      selected: {tun.stack},
                      onSelectionChanged: running
                          ? (_) {}
                          : (selection) {
                              if (selection.isNotEmpty) {
                                _applyTun(
                                  (current) =>
                                      current.copyWith(stack: selection.first),
                                );
                              }
                            },
                    ),
                    const Divider(height: 1, indent: 64),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('附加系统代理'),
                      subtitle: const Text('将内核端口通告为系统 HTTP 代理'),
                      value: tun.systemProxy,
                      onChanged: running
                          ? null
                          : (v) => _applyTun(
                              (current) => current.copyWith(systemProxy: v),
                            ),
                    ),
                    const Divider(height: 1, indent: 64),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('IPv6'),
                      subtitle: const Text('为隧道分配 IPv6 地址与路由'),
                      value: tun.ipv6,
                      onChanged: running
                          ? null
                          : (v) => _applyTun(
                              (current) => current.copyWith(ipv6: v),
                            ),
                    ),
                    const Divider(height: 1, indent: 64),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许绕过'),
                      subtitle: const Text('允许应用自行选择绕过 VPN'),
                      value: tun.allowBypass,
                      onChanged: running
                          ? null
                          : (v) => _applyTun(
                              (current) => current.copyWith(allowBypass: v),
                            ),
                    ),
                    const Divider(height: 1, indent: 64),
                    _TunSegmentedRow<String>(
                      label: '绕过模式',
                      segments: const [
                        ButtonSegment(value: 'off', label: Text('关闭')),
                        ButtonSegment(value: 'lan', label: Text('局域网')),
                        ButtonSegment(value: 'custom', label: Text('自定义')),
                      ],
                      selected: {tun.bypassMode},
                      onSelectionChanged: running
                          ? (_) {}
                          : (selection) {
                              if (selection.isNotEmpty) {
                                _applyTun(
                                  (current) => current.copyWith(
                                    bypassMode: selection.first,
                                  ),
                                );
                              }
                            },
                    ),
                    if (tun.bypassMode == 'custom') ...[
                      const Divider(height: 1, indent: 64),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自定义绕过段'),
                        subtitle: Text(
                          tun.bypassCustom.isEmpty ? '未设置' : tun.bypassCustom,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        enabled: !running,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: running ? null : () => _openCustomBypass(tun),
                      ),
                    ],
                    const Divider(height: 1, indent: 64),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('MTU'),
                      enabled: !running,
                      trailing: SizedBox(
                        width: 120,
                        child: TextFormField(
                          key: ValueKey(tun.mtu),
                          initialValue: tun.mtu.toString(),
                          enabled: !running,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onFieldSubmitted: (v) {
                            final mtu = int.tryParse(v.trim());
                            if (mtu != null && mtu >= 576 && mtu <= 20000) {
                              _applyTun(
                                (current) => current.copyWith(mtu: mtu),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 64),
                    _TunSegmentedRow<String>(
                      label: '访问控制',
                      segments: const [
                        ButtonSegment(value: 'accept_all', label: Text('允许所有')),
                        ButtonSegment(
                          value: 'accept_selected',
                          label: Text('仅所选'),
                        ),
                        ButtonSegment(
                          value: 'reject_selected',
                          label: Text('排除所选'),
                        ),
                      ],
                      selected: {tun.accessMode},
                      onSelectionChanged: running
                          ? (_) {}
                          : (selection) {
                              if (selection.isNotEmpty) {
                                _applyTun(
                                  (current) => current.copyWith(
                                    accessMode: selection.first,
                                  ),
                                );
                              }
                            },
                    ),
                    if (tun.accessMode != 'accept_all')
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('应用包列表'),
                        subtitle: Text(
                          tun.accessPackages.isEmpty
                              ? '未选择'
                              : '已选择 ${tun.accessPackages.length} 个应用',
                        ),
                        enabled: !running,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: running
                            ? null
                            : () async {
                                final result = await Navigator.of(context)
                                    .push<List<String>>(
                                      AppPageRoute(
                                        builder: (_) => CoreAccessScreen(
                                          selected: tun.accessPackages.toSet(),
                                        ),
                                      ),
                                    );
                                if (result != null) {
                                  _applyTun(
                                    (current) => current.copyWith(
                                      accessPackages: result,
                                    ),
                                  );
                                }
                              },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TunSegmentedRow<T> extends StatelessWidget {
  const _TunSegmentedRow({
    required this.label,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
  });

  final String label;
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: CompactSegmentedButton<T>(
              expanded: true,
              segments: segments,
              selected: selected,
              onSelectionChanged: onSelectionChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortsPanel extends StatefulWidget {
  const _PortsPanel({
    required this.settings,
    required this.running,
    required this.onApply,
  });

  final rust.CoreConfig settings;
  final bool running;
  final Future<void> Function({
    required int mixed,
    required int port,
    required int socks,
    required bool allowLan,
  })
  onApply;

  @override
  State<_PortsPanel> createState() => _PortsPanelState();
}

class _PortsPanelState extends State<_PortsPanel> {
  late final _mixed = TextEditingController(
    text: '${widget.settings.mixedPort}',
  );
  late final _http = TextEditingController(text: '${widget.settings.port}');
  late final _socks = TextEditingController(
    text: '${widget.settings.socksPort}',
  );
  @override
  void didUpdateWidget(covariant _PortsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.mixedPort != widget.settings.mixedPort) {
      _mixed.text = '${widget.settings.mixedPort}';
    }
    if (oldWidget.settings.port != widget.settings.port) {
      _http.text = '${widget.settings.port}';
    }
    if (oldWidget.settings.socksPort != widget.settings.socksPort) {
      _socks.text = '${widget.settings.socksPort}';
    }
  }

  @override
  void dispose() {
    _mixed.dispose();
    _http.dispose();
    _socks.dispose();
    super.dispose();
  }

  Future<void> _submit({bool? allowLan}) async {
    await widget.onApply(
      mixed: int.tryParse(_mixed.text.trim()) ?? 0,
      port: int.tryParse(_http.text.trim()) ?? 0,
      socks: int.tryParse(_socks.text.trim()) ?? 0,
      allowLan: allowLan ?? widget.settings.allowLan,
    );
    if (!mounted) return;
    _mixed.text = '${widget.settings.mixedPort}';
    _http.text = '${widget.settings.port}';
    _socks.text = '${widget.settings.socksPort}';
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String label, TextEditingController c) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(label)),
            Expanded(
              child: TextField(
                controller: c,
                enabled: !widget.running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
      );
    }

    return SectionPanel(
      title: '端口配置',
      icon: Icons.cable,
      child: Column(
        children: [
          row('Mixed', _mixed),
          row('HTTP', _http),
          row('SOCKS5', _socks),
          const Divider(height: 1, indent: 12),
          CompactSwitch.tile(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许局域网连接'),
            subtitle: const Text('允许局域网设备访问代理端口'),
            value: widget.settings.allowLan,
            onChanged: widget.running
                ? null
                : (value) => _submit(allowLan: value),
          ),
        ],
      ),
    );
  }
}

class _ControllerPanel extends StatefulWidget {
  const _ControllerPanel({
    required this.settings,
    required this.running,
    required this.onApply,
  });

  final rust.CoreConfig settings;
  final bool running;
  final Future<void> Function({
    required bool enabled,
    required String address,
    required String secret,
  })
  onApply;

  @override
  State<_ControllerPanel> createState() => _ControllerPanelState();
}

class _ControllerPanelState extends State<_ControllerPanel> {
  late final _address = TextEditingController(
    text: widget.settings.externalController,
  );
  late final _secret = TextEditingController(text: widget.settings.secret);

  @override
  void didUpdateWidget(covariant _ControllerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.externalController !=
        widget.settings.externalController) {
      _address.text = widget.settings.externalController;
    }
    if (oldWidget.settings.secret != widget.settings.secret) {
      _secret.text = widget.settings.secret;
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _submit({bool? enabled}) async {
    final nextEnabled =
        enabled ?? widget.settings.externalController.isNotEmpty;
    final address = _address.text.trim();
    await widget.onApply(
      enabled: nextEnabled,
      address: nextEnabled && address.isEmpty ? '127.0.0.1:9090' : address,
      secret: _secret.text.trim(),
    );
    if (!mounted) return;
    _address.text = widget.settings.externalController;
    _secret.text = widget.settings.secret;
  }

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: '控制器',
      icon: Icons.settings_ethernet,
      child: Column(
        children: [
          CompactSwitch.tile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用外部控制器'),
            subtitle: const Text('监听 RESTful API（默认关闭，注意安全）'),
            value: widget.settings.externalController.isNotEmpty,
            onChanged: widget.running
                ? null
                : (value) => _submit(enabled: value),
          ),
          if (widget.settings.externalController.isNotEmpty) ...[
            const Divider(height: 1, indent: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextField(
                controller: _address,
                enabled: !widget.running,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '监听地址',
                  hintText: '0.0.0.0:9090',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextField(
                controller: _secret,
                enabled: !widget.running,
                obscureText: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Secret (密钥)',
                  hintText: '留空不启用认证',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CustomBypassScreen extends StatefulWidget {
  const CustomBypassScreen({super.key, required this.initial});

  final List<String> initial;

  @override
  State<CustomBypassScreen> createState() => _CustomBypassScreenState();
}

class _CustomBypassScreenState extends State<CustomBypassScreen> {
  late final List<String> _items = [...widget.initial];

  Future<void> _add() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加绕过段'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'CIDR 段',
            hintText: '192.168.1.0/24',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    if (_items.contains(value)) return;
    setState(() => _items.add(value));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义绕过段'),
        actions: [
          IconButton(
            tooltip: '添加',
            onPressed: _add,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
              child: Text(
                '暂无绕过段',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, i) => ListTile(
                dense: true,
                title: Text(_items[i]),
                trailing: IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _items.removeAt(i)),
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(_items),
            child: const Text('保存'),
          ),
        ),
      ),
    );
  }
}
