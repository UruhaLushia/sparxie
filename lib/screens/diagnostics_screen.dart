import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../utils.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  String? _targetKey;
  rust.BackendTarget? _target;
  List<rust.OutboundEntry> _outbounds = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_restart);
    _restart(force: true);
  }

  @override
  void didUpdateWidget(covariant DiagnosticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store.removeListener(_restart);
    widget.store.addListener(_restart);
    _restart(force: true);
  }

  @override
  void dispose() {
    widget.store.removeListener(_restart);
    super.dispose();
  }

  void _restart({bool force = false}) {
    final controller = widget.store.active;
    final key = controller == null ? null : _controllerKey(controller);
    if (!force && key == _targetKey) return;
    _targetKey = key;
    if (controller == null || controller.type != ctl.BackendType.singBox) {
      setState(() {
        _target = null;
        _outbounds = const [];
        _error = controller == null ? '请先在“后端”中添加一个后端' : '当前后端不支持网络诊断工具';
      });
      return;
    }
    final target = rust.backendTargetForController(controller);
    setState(() {
      _target = target;
      _outbounds = const [];
      _error = null;
    });
    unawaited(_loadOutbounds(target, key));
  }

  Future<void> _loadOutbounds(rust.BackendTarget target, String? key) async {
    try {
      final list = await rust.diagnosticsOutbounds(target: target);
      if (!mounted || _targetKey != key) return;
      setState(() => _outbounds = list);
    } catch (_) {
      // Picker falls back to the default outbound only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('网络工具'),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _error != null || target == null
                  ? SectionPanel(
                      title: '状态',
                      icon: Icons.network_check_outlined,
                      child: _MessageBox(_error ?? '未连接后端', error: true),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _QualityPanel(
                          key: ValueKey('quality|$_targetKey'),
                          target: target,
                          outbounds: _outbounds,
                        ),
                        const SizedBox(height: 16),
                        _StunPanel(
                          key: ValueKey('stun|$_targetKey'),
                          target: target,
                          outbounds: _outbounds,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityPanel extends StatefulWidget {
  const _QualityPanel({
    super.key,
    required this.target,
    required this.outbounds,
  });

  final rust.BackendTarget target;
  final List<rust.OutboundEntry> outbounds;

  @override
  State<_QualityPanel> createState() => _QualityPanelState();
}

class _QualityPanelState extends State<_QualityPanel> {
  static const _defaultConfigUrl =
      'https://mensura.cdn-apple.com/api/v1/gm/config';

  StreamSubscription<rust.NetworkQualityProgress>? _sub;
  late final TextEditingController _configCtl = TextEditingController(
    text: _defaultConfigUrl,
  );
  rust.NetworkQualityProgress? _progress;
  String? _error;
  bool _running = false;
  bool _serial = false;
  bool _http3 = false;
  int _maxRuntime = 20;
  String _outbound = '';

  @override
  void dispose() {
    _sub?.cancel();
    _configCtl.dispose();
    super.dispose();
  }

  void _start() {
    _sub?.cancel();
    setState(() {
      _running = true;
      _progress = null;
      _error = null;
    });
    _sub = rust
        .networkQualityTestStream(
          target: widget.target,
          configUrl: _configCtl.text.trim(),
          outboundTag: _outbound,
          serial: _serial,
          maxRuntimeSeconds: _maxRuntime,
          http3: _http3,
        )
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              if (progress.error.isNotEmpty) _error = progress.error;
              if (progress.isFinal) _running = false;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _error = formatError(e);
              _running = false;
            });
          },
          onDone: () {
            if (mounted && _running) setState(() => _running = false);
          },
        );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return SectionPanel(
      title: '网络质量测试',
      icon: Icons.speed_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _configCtl,
            enabled: !_running,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '配置地址',
              hintText: _defaultConfigUrl,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OutboundDropdown(
                  value: _outbound,
                  outbounds: widget.outbounds,
                  enabled: !_running,
                  onChanged: (v) => setState(() => _outbound = v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _running ? _stop : _start,
                icon: Icon(_running ? Icons.stop : Icons.play_arrow, size: 18),
                label: Text(_running ? '停止' : '开始'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('串行测试'),
                selected: _serial,
                onSelected: _running
                    ? null
                    : (v) => setState(() => _serial = v),
              ),
              FilterChip(
                label: const Text('HTTP/3'),
                selected: _http3,
                onSelected: _running ? null : (v) => setState(() => _http3 = v),
              ),
              CompactSegmentedButton<int>(
                segments: [
                  for (final seconds in const [20, 30, 60])
                    ButtonSegment(
                      value: seconds,
                      enabled: !_running,
                      label: Text('${seconds}s'),
                    ),
                ],
                selected: {_maxRuntime},
                onSelectionChanged: (selection) =>
                    setState(() => _maxRuntime = selection.first),
              ),
            ],
          ),
          if (_running) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(switch (progress?.phase) {
              1 => '下载测试中…',
              2 => '上传测试中…',
              _ => '准备中…',
            }, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (progress != null) ...[
            const SizedBox(height: 14),
            _ResultRows(
              rows: [
                (
                  '空闲延迟',
                  progress.idleLatencyMs > 0
                      ? '${progress.idleLatencyMs} ms'
                      : '-',
                ),
                (
                  '下载带宽',
                  _withAccuracy(
                    _bitrate(progress.downloadCapacity),
                    progress.isFinal,
                    progress.downloadCapacityAccuracy,
                  ),
                ),
                (
                  '上传带宽',
                  _withAccuracy(
                    _bitrate(progress.uploadCapacity),
                    progress.isFinal,
                    progress.uploadCapacityAccuracy,
                  ),
                ),
                (
                  '下载 RPM',
                  _withAccuracy(
                    progress.downloadRpm > 0 ? '${progress.downloadRpm}' : '-',
                    progress.isFinal,
                    progress.downloadRpmAccuracy,
                  ),
                ),
                (
                  '上传 RPM',
                  _withAccuracy(
                    progress.uploadRpm > 0 ? '${progress.uploadRpm}' : '-',
                    progress.isFinal,
                    progress.uploadRpmAccuracy,
                  ),
                ),
                ('用时', _seconds(progress.elapsedMs)),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBox(_error!, error: true),
          ],
        ],
      ),
    );
  }
}

class _StunPanel extends StatefulWidget {
  const _StunPanel({super.key, required this.target, required this.outbounds});

  final rust.BackendTarget target;
  final List<rust.OutboundEntry> outbounds;

  @override
  State<_StunPanel> createState() => _StunPanelState();
}

class _StunPanelState extends State<_StunPanel> {
  static const _defaultServer = 'stun.voipgate.com:3478';

  StreamSubscription<rust.StunTestProgress>? _sub;
  late final TextEditingController _serverCtl = TextEditingController(
    text: _defaultServer,
  );
  rust.StunTestProgress? _progress;
  String? _error;
  bool _running = false;
  String _outbound = '';

  @override
  void dispose() {
    _sub?.cancel();
    _serverCtl.dispose();
    super.dispose();
  }

  void _start() {
    _sub?.cancel();
    setState(() {
      _running = true;
      _progress = null;
      _error = null;
    });
    _sub = rust
        .stunTestStream(
          target: widget.target,
          server: _serverCtl.text.trim(),
          outboundTag: _outbound,
        )
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              if (progress.error.isNotEmpty) _error = progress.error;
              if (progress.isFinal) _running = false;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _error = formatError(e);
              _running = false;
            });
          },
          onDone: () {
            if (mounted && _running) setState(() => _running = false);
          },
        );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return SectionPanel(
      title: 'STUN 测试',
      icon: Icons.travel_explore_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _serverCtl,
            enabled: !_running,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'STUN 服务器',
              hintText: _defaultServer,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OutboundDropdown(
                  value: _outbound,
                  outbounds: widget.outbounds,
                  enabled: !_running,
                  onChanged: (v) => setState(() => _outbound = v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _running ? _stop : _start,
                icon: Icon(_running ? Icons.stop : Icons.play_arrow, size: 18),
                label: Text(_running ? '停止' : '开始'),
              ),
            ],
          ),
          if (_running) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
          if (progress != null) ...[
            const SizedBox(height: 14),
            _ResultRows(
              rows: [
                (
                  '外部地址',
                  progress.externalAddr.isEmpty ? '-' : progress.externalAddr,
                ),
                (
                  '延迟',
                  progress.latencyMs > 0 ? '${progress.latencyMs} ms' : '-',
                ),
                if (progress.isFinal && !progress.natTypeSupported)
                  ('NAT 检测', '服务器不支持 (RFC 5780)')
                else ...[
                  (
                    'NAT 映射',
                    progress.natMapping > 0
                        ? _natMapping(progress.natMapping)
                        : '-',
                  ),
                  (
                    'NAT 过滤',
                    progress.natFiltering > 0
                        ? _natFiltering(progress.natFiltering)
                        : '-',
                  ),
                ],
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBox(_error!, error: true),
          ],
        ],
      ),
    );
  }
}

class _OutboundDropdown extends StatelessWidget {
  const _OutboundDropdown({
    required this.value,
    required this.outbounds,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final List<rust.OutboundEntry> outbounds;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = outbounds.any((entry) => entry.tag == value);
    return DropdownButtonFormField<String>(
      initialValue: known ? value : '',
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        labelText: '出站',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('默认')),
        for (final entry in outbounds)
          DropdownMenuItem(
            value: entry.tag,
            child: Text(
              entry.outboundType.isEmpty
                  ? entry.tag
                  : '${entry.tag}  ·  ${entry.outboundType}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled ? (v) => onChanged(v ?? '') : null,
    );
  }
}

class _ResultRows extends StatelessWidget {
  const _ResultRows({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  rows[i].$1,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rows[i].$2,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = error ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final fg = error ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: fg)),
    );
  }
}

String _controllerKey(ctl.Controller c) =>
    '${c.id}\u{1f}${c.type.name}\u{1f}${c.baseUrl}\u{1f}${c.secret}\u{1f}${c.allowInsecure}';

String _withAccuracy(String value, bool isFinal, int accuracy) {
  if (!isFinal || value == '-') return value;
  final label = switch (accuracy) {
    2 => '高',
    1 => '中',
    _ => '低',
  };
  return '$value(精度:$label)';
}

String _bitrate(Object bps) {
  final value = asBigInt(bps).toDouble();
  if (value <= 0) return '-';
  if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)} Gbps';
  if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)} Mbps';
  if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)} kbps';
  return '${value.round()} bps';
}

String _seconds(Object millis) {
  final value = asBigInt(millis).toDouble();
  if (value <= 0) return '-';
  return '${(value / 1000).toStringAsFixed(1)} s';
}

String _natMapping(int value) => switch (value) {
  2 => '端点无关',
  3 => '地址相关',
  4 => '地址和端口相关',
  _ => '未知',
};

String _natFiltering(int value) => switch (value) {
  1 => '端点无关',
  2 => '地址相关',
  3 => '地址和端口相关',
  _ => '未知',
};
