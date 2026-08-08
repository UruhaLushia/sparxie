import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import 'compact_controls.dart';
import 'section_panel.dart';

/// Self-contained panel that pulls backend `/configs`, lets the user toggle
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
  rust.ControllerConfig? _configs;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  rust.BackendTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.backendTargetForController(c);
  }

  void _bind() {
    _activeKey = widget.store.active;
    if (_activeKey == null) {
      setState(() {
        _configs = null;
        _error = '请先在“后端”中添加一个后端';
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
      final configs = await rust.controllerConfigs(target: target);
      if (!mounted || !identical(widget.store.active, _activeKey)) return;
      setState(() => _configs = configs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(
    String key,
    Future<void> Function(rust.BackendTarget target) action,
  ) async {
    final target = _target();
    if (target == null || _readOnly) return;
    setState(() {
      _saving = key;
      _error = null;
    });
    try {
      await action(target);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError(e));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _setMode(String mode) async {
    final target = _target();
    if (target == null || _readOnly) return;
    setState(() {
      _saving = 'mode';
      _error = null;
    });
    try {
      await rust.controllerSetConfigMode(target: target, mode: mode);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError(e));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  String _formatError(Object error) =>
      formatError(error, backendName: _activeKey?.name);

  bool get _readOnly => _activeKey?.type == ctl.BackendType.surge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = _configs;
    final readOnly = _readOnly;
    final modeChoices =
        c?.modeChoices(
          useDefaultModes: _activeKey?.type != ctl.BackendType.singBox,
        ) ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: colorScheme.onErrorContainer,
                ),
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
          if (widget.showOutboundMode && modeChoices.isNotEmpty) ...[
            _ModeSection(
              current: c.mode ?? '',
              options: modeChoices,
              saving: _saving,
              readOnly: readOnly,
              onChange: _setMode,
            ),
            const SizedBox(height: 16),
          ],
          if (c.hasSwitches) ...[
            _SwitchSection(
              configs: c,
              saving: _saving,
              readOnly: readOnly,
              onLogLevel: (level) => _save(
                'log-level',
                (target) => rust.controllerSetConfigLogLevel(
                  target: target,
                  level: level,
                ),
              ),
              onTun: (enabled) => _save(
                'tun',
                (target) => rust.controllerSetConfigTunEnabled(
                  target: target,
                  enabled: enabled,
                ),
              ),
              onBool: (key, value) => _save(
                key,
                (target) => rust.controllerSetConfigBool(
                  target: target,
                  key: key,
                  value: value,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (c.hasPorts)
            _PortsSection(
              configs: c,
              saving: _saving,
              readOnly: readOnly,
              onPort: (key, value) => _save(
                key,
                (target) => rust.controllerSetConfigPort(
                  target: target,
                  key: key,
                  value: value,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ModeSection extends StatelessWidget {
  const _ModeSection({
    required this.current,
    required this.options,
    required this.saving,
    required this.readOnly,
    required this.onChange,
  });
  final String current;
  final List<String> options;
  final String? saving;
  final bool readOnly;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    String? selected;
    for (final mode in options) {
      if (_sameMode(current, mode)) {
        selected = mode;
        break;
      }
    }
    final busy = saving == 'mode';
    final control = CompactSegmentedButton<String>(
      expanded: options.length <= 3,
      segments: [
        for (final mode in options)
          ButtonSegment(
            value: mode,
            enabled: !readOnly && !busy,
            icon: busy && _sameMode(current, mode)
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            label: Text(_label(mode)),
          ),
      ],
      selected: selected == null ? const <String>{} : {selected},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChange(selection.first);
      },
    );
    return SectionPanel(
      title: '出站模式',
      icon: Icons.alt_route,
      child: options.length <= 3
          ? control
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: control,
            ),
    );
  }
}

class _SwitchSection extends StatelessWidget {
  const _SwitchSection({
    required this.configs,
    required this.saving,
    required this.readOnly,
    required this.onLogLevel,
    required this.onTun,
    required this.onBool,
  });
  final rust.ControllerConfig configs;
  final String? saving;
  final bool readOnly;
  final ValueChanged<String> onLogLevel;
  final ValueChanged<bool> onTun;
  final void Function(String key, bool value) onBool;

  @override
  Widget build(BuildContext context) {
    final logLevel = configs.logLevel ?? 'info';
    return SectionPanel(
      title: '通用',
      icon: Icons.tune,
      child: Column(
        children: [
          if (configs.logLevel != null)
            _LogLevelRow(
              current: logLevel,
              busy: saving == 'log-level',
              readOnly: readOnly,
              onChange: onLogLevel,
            ),
          if (configs.tunEnabled != null)
            CompactSwitch.tile(
              contentPadding: EdgeInsets.zero,
              title: const Text('TUN'),
              subtitle: saving == 'tun' ? const Text('保存中…') : null,
              value: configs.tunEnabled!,
              onChanged: readOnly || saving == 'tun' ? null : onTun,
            ),
          if (configs.allowLan != null)
            _switchTile(
              label: '允许局域网连接',
              valueKey: 'allow-lan',
              current: configs.allowLan!,
            ),
          if (configs.ipv6 != null)
            _switchTile(
              label: 'IPv6',
              valueKey: 'ipv6',
              current: configs.ipv6!,
            ),
          if (configs.tcpConcurrent != null)
            _switchTile(
              label: 'TCP 并发',
              valueKey: 'tcp-concurrent',
              current: configs.tcpConcurrent!,
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
    return CompactSwitch.tile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: busy ? const Text('保存中…') : null,
      value: current,
      onChanged: readOnly || busy ? null : (v) => onBool(valueKey, v),
    );
  }
}

class _PortsSection extends StatefulWidget {
  const _PortsSection({
    required this.configs,
    required this.saving,
    required this.readOnly,
    required this.onPort,
  });
  final rust.ControllerConfig configs;
  final String? saving;
  final bool readOnly;
  final void Function(String key, int value) onPort;

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
    _http.text = '${c.port ?? 0}';
    _socks.text = '${c.socksPort ?? 0}';
    _mixed.text = '${c.mixedPort ?? 0}';
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
    final rows = <Widget>[];
    void addRow(Widget row) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(row);
    }

    if (widget.configs.port != null) {
      addRow(_row('HTTP', _http, 'port'));
    }
    if (widget.configs.socksPort != null) {
      addRow(_row('SOCKS5', _socks, 'socks-port'));
    }
    if (widget.configs.mixedPort != null) {
      addRow(_row('Mixed', _mixed, 'mixed-port'));
    }

    return SectionPanel(
      title: '入站端口',
      icon: Icons.cable,
      child: Column(children: rows),
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
            readOnly: widget.readOnly,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(72, 45),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: busy || widget.readOnly
              ? null
              : () {
                  final port = int.tryParse(c.text.trim()) ?? 0;
                  widget.onPort(key, port);
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
    required this.readOnly,
    required this.onChange,
  });

  final String current;
  final bool busy;
  final bool readOnly;
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
          CompactMenuButton<String>(
            value: value,
            label: value,
            semanticLabel: '日志级别',
            enabled: !readOnly && !busy,
            itemBuilder: (_) => [
              for (final l in _levels) PopupMenuItem(value: l, child: Text(l)),
            ],
            onSelected: (v) {
              if (v != current) onChange(v);
            },
          ),
        ],
      ),
    );
  }
}

extension _CoreConfigView on rust.ControllerConfig {
  static const _defaultModes = ['rule', 'global', 'direct'];

  List<String> modeChoices({required bool useDefaultModes}) {
    final choices = modeOptions.isEmpty && useDefaultModes
        ? _defaultModes
        : modeOptions;
    final out = <String>[];
    for (final value in choices) {
      if (value.isEmpty || out.any((item) => _sameMode(item, value))) continue;
      out.add(value);
    }
    final current = mode;
    if (current != null &&
        current.isNotEmpty &&
        !out.any((item) => _sameMode(item, current))) {
      out.insert(0, current);
    }
    return out;
  }

  bool get hasSwitches =>
      logLevel != null ||
      tunEnabled != null ||
      allowLan != null ||
      ipv6 != null ||
      tcpConcurrent != null;

  bool get hasPorts => port != null || socksPort != null || mixedPort != null;
}

bool _sameMode(String a, String b) => a.toLowerCase() == b.toLowerCase();

String _label(String m) => switch (m.toLowerCase()) {
  'rule' => '规则',
  'global' => '全局',
  'direct' => '直连',
  _ => m,
};
