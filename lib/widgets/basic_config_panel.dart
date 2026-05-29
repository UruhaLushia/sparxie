import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import 'section_panel.dart';

/// Self-contained panel that pulls mihomo `/configs`, lets the user toggle
/// the common knobs (mode, log level, lan/ipv6/sniff/tcp-concurrent, ports)
/// and PATCHes them back. Used both inside the standard settings page and
/// as the body of the cards-mode "基础配置" destination.
class BasicConfigPanel extends StatefulWidget {
  const BasicConfigPanel({
    super.key,
    required this.store,
    this.showOutboundMode = true,
  });

  final ctl.ControllerStore store;

  /// When false, omit the 出站模式 section. Used by the cards-layout core
  /// config page, where 出站模式 is already exposed as a launcher card.
  final bool showOutboundMode;

  @override
  State<BasicConfigPanel> createState() => _BasicConfigPanelState();
}

class _BasicConfigPanelState extends State<BasicConfigPanel> {
  ctl.Controller? _activeKey;
  bool _loading = false;
  String? _error;
  String? _saving;
  Map<String, dynamic>? _configs;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _bind();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!identical(widget.store.active, _activeKey)) _bind();
  }

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
      allowInsecure: c.allowInsecure,
    );
  }

  void _bind() {
    _activeKey = widget.store.active;
    if (_activeKey == null) {
      setState(() {
        _configs = null;
        _error = '请先在“后端”中添加一个 mihomo 实例';
      });
      return;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    final target = _target();
    if (target == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await rust.configs(target: target);
      if (!mounted || !identical(widget.store.active, _activeKey)) return;
      setState(() => _configs = jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patch(String key, Map<String, dynamic> body) async {
    final target = _target();
    if (target == null) return;
    setState(() {
      _saving = key;
      _error = null;
    });
    try {
      await rust.patchConfigs(target: target, bodyJson: jsonEncode(body));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatError(e));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = _configs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_rounded, color: colorScheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (c == null && _loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (c != null) ...[
          if (widget.showOutboundMode) ...[
            _ModeSection(
              configs: c,
              saving: _saving,
              onChange: (mode) => _patch('mode', {'mode': mode}),
            ),
            const SizedBox(height: 16),
          ],
          _SwitchSection(configs: c, saving: _saving, onPatch: _patch),
          const SizedBox(height: 16),
          _PortsSection(configs: c, saving: _saving, onPatch: _patch),
        ],
      ],
    );
  }
}

class _ModeSection extends StatelessWidget {
  const _ModeSection({
    required this.configs,
    required this.saving,
    required this.onChange,
  });
  final Map<String, dynamic> configs;
  final String? saving;
  final ValueChanged<String> onChange;

  static const _modes = ['rule', 'global', 'direct'];

  @override
  Widget build(BuildContext context) {
    final current = (configs['mode'] ?? 'rule').toString().toLowerCase();
    return SectionPanel(
      title: '出站模式',
      icon: Icons.alt_route,
      child: Wrap(
        spacing: 8,
        children: [
          for (final m in _modes)
            ChoiceChip(
              label: Text(_label(m)),
              selected: current == m,
              onSelected: saving == 'mode' || current == m
                  ? null
                  : (_) => onChange(m),
            ),
          if (saving == 'mode')
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  String _label(String m) => switch (m) {
    'rule' => '规则',
    'global' => '全局',
    'direct' => '直连',
    _ => m,
  };
}

class _SwitchSection extends StatelessWidget {
  const _SwitchSection({
    required this.configs,
    required this.saving,
    required this.onPatch,
  });
  final Map<String, dynamic> configs;
  final String? saving;
  final Future<void> Function(String key, Map<String, dynamic> body) onPatch;

  @override
  Widget build(BuildContext context) {
    final tun = configs['tun'];
    final tunEnabled = tun is Map && tun['enable'] == true;
    final logLevel = (configs['log-level'] ?? 'info').toString().toLowerCase();
    return SectionPanel(
      title: '通用',
      icon: Icons.tune,
      child: Column(
        children: [
          _LogLevelRow(
            current: logLevel,
            busy: saving == 'log-level',
            onChange: (v) => onPatch('log-level', {'log-level': v}),
          ),
          if (tun is Map)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('TUN'),
              subtitle: saving == 'tun' ? const Text('保存中…') : null,
              value: tunEnabled,
              onChanged: saving == 'tun'
                  ? null
                  : (v) => onPatch('tun', {
                      'tun': {'enable': v},
                    }),
            ),
          _switchTile(
            label: '允许局域网连接',
            valueKey: 'allow-lan',
            current: configs['allow-lan'] == true,
          ),
          _switchTile(
            label: 'IPv6',
            valueKey: 'ipv6',
            current: configs['ipv6'] == true,
          ),
          _switchTile(
            label: 'TCP 并发',
            valueKey: 'tcp-concurrent',
            current: configs['tcp-concurrent'] == true,
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required String label,
    required String valueKey,
    required bool current,
  }) {
    final busy = saving == valueKey;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: busy ? const Text('保存中…') : null,
      value: current,
      onChanged: busy ? null : (v) => onPatch(valueKey, {valueKey: v}),
    );
  }
}

class _PortsSection extends StatefulWidget {
  const _PortsSection({
    required this.configs,
    required this.saving,
    required this.onPatch,
  });
  final Map<String, dynamic> configs;
  final String? saving;
  final Future<void> Function(String key, Map<String, dynamic> body) onPatch;

  @override
  State<_PortsSection> createState() => _PortsSectionState();
}

class _PortsSectionState extends State<_PortsSection> {
  final _http = TextEditingController();
  final _socks = TextEditingController();
  final _mixed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PortsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final c = widget.configs;
    _http.text = '${c['port'] ?? 0}';
    _socks.text = '${c['socks-port'] ?? 0}';
    _mixed.text = '${c['mixed-port'] ?? 0}';
  }

  @override
  void dispose() {
    _http.dispose();
    _socks.dispose();
    _mixed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: '入站端口',
      icon: Icons.cable,
      child: Column(
        children: [
          _row('HTTP', _http, 'port'),
          const SizedBox(height: 8),
          _row('SOCKS5', _socks, 'socks-port'),
          const SizedBox(height: 8),
          _row('Mixed', _mixed, 'mixed-port'),
        ],
      ),
    );
  }

  Widget _row(String label, TextEditingController c, String key) {
    final busy = widget.saving == key;
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: busy
              ? null
              : () {
                  final port = int.tryParse(c.text.trim()) ?? 0;
                  widget.onPatch(key, {key: port});
                },
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('应用'),
        ),
      ],
    );
  }
}

class _LogLevelRow extends StatelessWidget {
  const _LogLevelRow({
    required this.current,
    required this.busy,
    required this.onChange,
  });

  final String current;
  final bool busy;
  final ValueChanged<String> onChange;

  static const _levels = ['silent', 'error', 'warning', 'info', 'debug'];

  @override
  Widget build(BuildContext context) {
    final value = _levels.contains(current) ? current : 'info';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Expanded(child: Text('日志级别')),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          DropdownButton<String>(
            value: value,
            borderRadius: BorderRadius.circular(8),
            underline: const SizedBox.shrink(),
            items: [
              for (final l in _levels)
                DropdownMenuItem(value: l, child: Text(l)),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v != null && v != current) onChange(v);
                  },
          ),
        ],
      ),
    );
  }
}
