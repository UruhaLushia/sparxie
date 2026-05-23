import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../session.dart';
import '../utils.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.store,
    required this.session,
  });

  final ctl.ControllerStore store;
  final MihomoSession session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _historyCapacity = 60;

  ctl.Controller? _activeKey;
  String? _error;

  final _SparkHistory _history = _SparkHistory(capacity: _historyCapacity);

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    widget.session.traffic.addListener(_onTraffic);
    widget.session.connectionsTotals.addListener(_onConnTotals);
    widget.session.error.addListener(_onSessionError);
    widget.session.versionString.addListener(_onVersion);
    _bind();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    widget.session.traffic.removeListener(_onTraffic);
    widget.session.connectionsTotals.removeListener(_onConnTotals);
    widget.session.error.removeListener(_onSessionError);
    widget.session.versionString.removeListener(_onVersion);
    _history.dispose();
    super.dispose();
  }

  void _onVersion() {
    if (mounted) setState(() {});
  }

  void _onStore() {
    if (!identical(widget.store.active, _activeKey)) _bind();
  }

  void _onTraffic() {
    final t = widget.session.traffic.value;
    _history.pushTraffic(_toDouble(t.up), _toDouble(t.down));
  }

  void _onConnTotals() {
    final c = widget.session.connectionsTotals.value;
    _history.pushConnections(c.count.toDouble());
  }

  void _onSessionError() {
    if (!mounted) return;
    setState(() => _error = widget.session.error.value);
  }

  void _bind() {
    _activeKey = widget.store.active;
    _history.reset();
    if (_activeKey == null) {
      setState(() => _error = '请先在“后端”中添加一个 mihomo 实例');
      return;
    }
    setState(() => _error = widget.session.error.value);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.store.active;
    final scheme = Theme.of(context).colorScheme;
    final core = widget.session.versionString.value;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(active?.name ?? '概览'),
            const SizedBox(width: 10),
            ValueListenableBuilder<bool>(
              valueListenable: widget.session.isStreaming,
              builder: (_, live, _) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live ? const Color(0xff10b981) : scheme.outlineVariant,
                ),
              ),
            ),
            if (core.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                core,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _history,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 640;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(text: _error!),
                      const SizedBox(height: 16),
                    ],
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(child: _uploadCard()),
                            const SizedBox(width: 12),
                            Expanded(child: _downloadCard()),
                          ],
                        ),
                      )
                    else ...[
                      _uploadCard(),
                      const SizedBox(height: 12),
                      _downloadCard(),
                    ],
                    const SizedBox(height: 12),
                    _connectionsCard(),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _uploadCard() {
    final t = widget.session.traffic.value;
    return _MetricChartCard(
      label: '上传',
      value: formatBytes(t.up),
      unit: '/s',
      footer: '总计 ${formatBytes(t.upTotal)}',
      samples: _history.upSnapshot,
      color: const Color(0xff60a5fa),
      formatY: (v) => '${formatBytes(BigInt.from(v.round()))}/s',
    );
  }

  Widget _downloadCard() {
    final t = widget.session.traffic.value;
    return _MetricChartCard(
      label: '下载',
      value: formatBytes(t.down),
      unit: '/s',
      footer: '总计 ${formatBytes(t.downTotal)}',
      samples: _history.downSnapshot,
      color: const Color(0xffa78bfa),
      formatY: (v) => '${formatBytes(BigInt.from(v.round()))}/s',
    );
  }

  Widget _connectionsCard() {
    final mem = widget.session.memory.value;
    final count = widget.session.connectionsTotals.value.count;
    return _MetricChartCard(
      label: '连接',
      value: '$count',
      unit: '',
      footer: '内存使用 ${formatBytes(mem.inuse)}',
      samples: _history.connSnapshot,
      color: const Color(0xff10b981),
      formatY: (v) => v.round().toString(),
      labelDot: true,
    );
  }

  static double _toDouble(BigInt v) {
    if (v.bitLength > 53) return v.toDouble();
    return v.toInt().toDouble();
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sparkline-backed metric card:
/// label · big value+unit · area chart with min/max markers · footer line.
class _MetricChartCard extends StatelessWidget {
  const _MetricChartCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.footer,
    required this.samples,
    required this.color,
    required this.formatY,
    this.labelDot = false,
  });

  final String label;
  final String value;
  final String unit;
  final String footer;
  final List<double> samples;
  final Color color;
  final String Function(double) formatY;
  final bool labelDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chartMax = _maxOf(samples);
    final chartMid = chartMax / 2;

    return Material(
      color: scheme.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (labelDot) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      unit,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: CustomPaint(
                painter: _SparklinePainter(
                  samples: samples,
                  color: color,
                  axisColor: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (chartMax > 0)
                          Text(
                            formatY(chartMax),
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        if (chartMax > 0)
                          Text(
                            formatY(chartMid),
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              footer,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static double _maxOf(List<double> s) {
    if (s.isEmpty) return 0;
    var m = 0.0;
    for (final v in s) {
      if (v > m) m = v;
    }
    return m;
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.samples,
    required this.color,
    required this.axisColor,
  });

  final List<double> samples;
  final Color color;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      axis,
    );

    if (samples.length < 2) return;

    var maxV = 0.0;
    for (final v in samples) {
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) return;

    // Build the path across the full width, normalized to [0, maxV] on Y.
    // Reserve right-side gutter for the level labels rendered by the parent.
    const rightGutter = 56.0;
    final usable = (size.width - rightGutter).clamp(40.0, size.width);
    final dx = usable / (samples.length - 1);

    final line = Path();
    final fill = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i * dx;
      final ratio = (samples[i] / maxV).clamp(0.0, 1.0);
      final y = size.height - ratio * (size.height - 4);
      if (i == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo((samples.length - 1) * dx, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.samples != samples || old.color != color;
}

/// Ring-buffer-backed sample history. Three independent series tracked at
/// whatever cadence the upstream notifiers fire (mihomo's WS streams emit at
/// ~1 Hz). Notifies listeners after each push so the dashboard repaints.
class _SparkHistory extends ChangeNotifier {
  _SparkHistory({required this.capacity});
  final int capacity;
  final List<double> _up = [];
  final List<double> _down = [];
  final List<double> _conn = [];

  List<double> get upSnapshot => List<double>.unmodifiable(_up);
  List<double> get downSnapshot => List<double>.unmodifiable(_down);
  List<double> get connSnapshot => List<double>.unmodifiable(_conn);

  void pushTraffic(double up, double down) {
    _push(_up, up);
    _push(_down, down);
    notifyListeners();
  }

  void pushConnections(double count) {
    _push(_conn, count);
    notifyListeners();
  }

  void reset() {
    if (_up.isEmpty && _down.isEmpty && _conn.isEmpty) return;
    _up.clear();
    _down.clear();
    _conn.clear();
    notifyListeners();
  }

  void _push(List<double> series, double value) {
    series.add(value);
    if (series.length > capacity) series.removeAt(0);
  }
}
