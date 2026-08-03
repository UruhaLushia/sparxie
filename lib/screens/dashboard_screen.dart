import 'dart:collection';

import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../session.dart';
import '../utils.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/app_background.dart';
import '../widgets/backend_switcher.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/page_body_transition.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

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
  var _active = true;

  final _SparkHistory _history = _SparkHistory(capacity: _historyCapacity);

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    widget.session.traffic.addListener(_onTraffic);
    widget.session.memory.addListener(_onMemory);
    widget.session.supportsMemory.addListener(_onSupportsMemory);
    widget.session.error.addListener(_onSessionError);
    widget.session.versionString.addListener(_onVersion);
    _bind();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    widget.session.traffic.removeListener(_onTraffic);
    widget.session.memory.removeListener(_onMemory);
    widget.session.supportsMemory.removeListener(_onSupportsMemory);
    widget.session.error.removeListener(_onSessionError);
    widget.session.versionString.removeListener(_onVersion);
    _history.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = isRealtimeUiActive(context);
    if (_active == active) return;
    _active = active;
    if (active) _error = widget.session.error.value;
  }

  void _onVersion() {
    if (mounted && _active) setState(() {});
  }

  void _onStore() {
    if (!identical(widget.store.active, _activeKey)) _bind();
  }

  void _onTraffic() {
    final t = widget.session.traffic.value;
    _history.pushTraffic(_toDouble(t.up), _toDouble(t.down), notify: _active);
  }

  void _onMemory() {
    if (!widget.session.supportsMemory.value) return;
    _history.pushMemory(
      _toDouble(widget.session.memory.value.inuse),
      notify: _active,
    );
  }

  void _onSupportsMemory() {
    if (!widget.session.supportsMemory.value) {
      _history.clearMemory(notify: false);
    }
    if (mounted && _active) setState(() {});
  }

  void _onSessionError() {
    if (!mounted) return;
    _error = widget.session.error.value;
    if (_active) setState(() {});
  }

  void _bind() {
    _activeKey = widget.store.active;
    _history.reset(notify: false);
    _error = _activeKey == null ? '请先在“后端”中添加一个后端' : widget.session.error.value;
    if (mounted && _active) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final core = widget.session.versionString.value;
    final showVersion = widget.store.active?.type != ctl.BackendType.surge;

    return Scaffold(
      backgroundColor: surfaceTheme.pageColor(scheme.surfaceContainerLowest),
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          backgroundColor: surfaceTheme.chromeColor(scheme.surface),
          scrolledUnderElevation: 0,
          flexibleSpace: const DesktopAppBarDragArea(),
          title: Row(
            children: [
              Flexible(
                child: BackendSwitcher(
                  store: widget.store,
                  textStyle: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 10),
              ActiveValueListenableBuilder<bool>(
                valueListenable: widget.session.isStreaming,
                builder: (_, live, _) => Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live
                        ? const Color(0xff10b981)
                        : scheme.outlineVariant,
                  ),
                ),
              ),
              if (showVersion && core.isNotEmpty) ...[
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
      ),
      body: AppPageBodyTransition(
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              return AppBackdropGroup(
                child: ListView(
                  addRepaintBoundaries: false,
                  addAutomaticKeepAlives: false,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(text: _error!),
                      const SizedBox(height: 16),
                    ],
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _uploadCard()),
                          const SizedBox(width: 12),
                          Expanded(child: _downloadCard()),
                        ],
                      )
                    else ...[
                      _uploadCard(),
                      const SizedBox(height: 12),
                      _downloadCard(),
                    ],
                    const SizedBox(height: 12),
                    if (widget.session.supportsMemory.value) ...[
                      _memoryCard(),
                      const SizedBox(height: 12),
                    ],
                    _connectionsCard(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _uploadCard() {
    return ActiveValueListenableBuilder<int>(
      valueListenable: _history.trafficRevision,
      pauseWhileScrolling: true,
      builder: (context, _, _) {
        final t = widget.session.traffic.value;
        return _MetricChartCard(
          icon: Icons.arrow_upward_rounded,
          label: '上传',
          value: formatBytes(t.up),
          unit: '/s',
          footer: '总计 ${formatBytes(t.upTotal)}',
          samples: _history.upSamples,
          sampleRevision: _history.trafficDataRevision,
          color: const Color(0xff60a5fa),
          formatY: (v) => '${formatBytes(BigInt.from(v.round()))}/s',
        );
      },
    );
  }

  Widget _downloadCard() {
    return ActiveValueListenableBuilder<int>(
      valueListenable: _history.trafficRevision,
      pauseWhileScrolling: true,
      builder: (context, _, _) {
        final t = widget.session.traffic.value;
        return _MetricChartCard(
          icon: Icons.arrow_downward_rounded,
          label: '下载',
          value: formatBytes(t.down),
          unit: '/s',
          footer: '总计 ${formatBytes(t.downTotal)}',
          samples: _history.downSamples,
          sampleRevision: _history.trafficDataRevision,
          color: const Color(0xffa78bfa),
          formatY: (v) => '${formatBytes(BigInt.from(v.round()))}/s',
        );
      },
    );
  }

  Widget _connectionsCard() {
    return ActiveValueListenableSelector<ConnectionsTotals, (int, int, int)>(
      valueListenable: widget.session.connectionsTotals,
      pauseWhileScrolling: true,
      selector: (totals) =>
          (totals.connectionsIn, totals.connectionsOut, totals.count),
      builder: (context, totals, _) {
        final hasBreakdown = totals.$1 > 0 || totals.$2 > 0;
        return _MetricChartCard(
          icon: Icons.hub_outlined,
          label: '连接',
          value: hasBreakdown ? '${totals.$1} / ${totals.$2}' : '${totals.$3}',
          unit: '',
          footer: hasBreakdown ? '入站 / 出站' : null,
          samples: const <double>[],
          color: const Color(0xff10b981),
          formatY: (v) => '${v.round()}',
          showChart: false,
        );
      },
    );
  }

  Widget _memoryCard() {
    return ActiveValueListenableBuilder<int>(
      valueListenable: _history.memoryRevision,
      pauseWhileScrolling: true,
      builder: (context, _, _) {
        final mem = widget.session.memory.value;
        final limit = mem.oslimit > BigInt.zero
            ? '上限 ${formatBytes(mem.oslimit)}'
            : null;
        final footer = [
          ?limit,
          if (mem.goroutines > 0) '协程 ${mem.goroutines}',
        ].join(' · ');
        return _MetricChartCard(
          icon: Icons.memory_outlined,
          label: '内存',
          value: formatBytes(mem.inuse),
          unit: '',
          footer: footer.isEmpty ? '当前使用' : footer,
          samples: _history.memorySamples,
          sampleRevision: _history.memoryDataRevision,
          color: const Color(0xfff59e0b),
          formatY: (v) => formatBytes(BigInt.from(v.round())),
        );
      },
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
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

/// Sparkline-backed metric card with a compact header and peak summary.
class _MetricChartCard extends StatelessWidget {
  const _MetricChartCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.samples,
    required this.color,
    required this.formatY,
    this.sampleRevision = 0,
    this.footer,
    this.showChart = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String? footer;
  final List<double> samples;
  final int sampleRevision;
  final Color color;
  final String Function(double) formatY;
  final bool showChart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chartMax = _maxOf(samples);
    final peak = showChart && chartMax > 0 ? formatY(chartMax) : null;
    final chartBackground = Color.alphaBlend(
      color.withValues(alpha: 0.025),
      scheme.surfaceContainerHigh,
    );

    return AppPanelSurface(
      groupBackdrop: true,
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
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
                                style: textTheme.headlineMedium?.copyWith(
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
                                  style: textTheme.titleMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (showChart) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 78,
                  decoration: BoxDecoration(
                    color: chartBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _SparklinePainter(
                        samples: samples,
                        revision: sampleRevision,
                        maxValue: chartMax,
                        color: color,
                        gridColor: scheme.outlineVariant.withValues(
                          alpha: 0.24,
                        ),
                        pointBorderColor: chartBackground,
                      ),
                    ),
                  ),
                ),
              ],
              if (footer != null || peak != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (footer != null)
                      Expanded(
                        child: Text(
                          footer!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (peak != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _MetricPill(text: '峰值 $peak', color: color),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
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

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.samples,
    required this.revision,
    required this.maxValue,
    required this.color,
    required this.gridColor,
    required this.pointBorderColor,
  });

  final List<double> samples;
  final int revision;
  final double maxValue;
  final Color color;
  final Color gridColor;
  final Color pointBorderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final ratio in const [0.25, 0.5, 0.75]) {
      final y = size.height * ratio;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (samples.length < 2) return;

    if (maxValue <= 0) return;

    const horizontalPadding = 2.0;
    const topPadding = 4.0;
    const bottomPadding = 4.0;
    final usableWidth = size.width > horizontalPadding * 2
        ? size.width - horizontalPadding * 2
        : size.width;
    final usableHeight = size.height > topPadding + bottomPadding
        ? size.height - topPadding - bottomPadding
        : size.height;
    final dx = usableWidth / (samples.length - 1);
    final scaleMax = maxValue * 1.12;
    final lastIndex = samples.length - 1;
    final firstX = horizontalPadding;
    final firstY = _sampleY(samples.first, scaleMax, topPadding, usableHeight);
    final lastX = horizontalPadding + lastIndex * dx;
    final lastY = _sampleY(samples.last, scaleMax, topPadding, usableHeight);
    final line = Path()..moveTo(firstX, firstY);
    if (samples.length == 2) {
      line.lineTo(lastX, lastY);
    } else {
      for (var i = 1; i < lastIndex; i++) {
        final currentX = horizontalPadding + i * dx;
        final currentY = _sampleY(
          samples[i],
          scaleMax,
          topPadding,
          usableHeight,
        );
        final nextX = horizontalPadding + (i + 1) * dx;
        final nextY = _sampleY(
          samples[i + 1],
          scaleMax,
          topPadding,
          usableHeight,
        );
        line.quadraticBezierTo(
          currentX,
          currentY,
          (currentX + nextX) / 2,
          (currentY + nextY) / 2,
        );
      }
      line.quadraticBezierTo(
        horizontalPadding + (lastIndex - 1) * dx,
        _sampleY(samples[lastIndex - 1], scaleMax, topPadding, usableHeight),
        lastX,
        lastY,
      );
    }
    final fill = Path.from(line)
      ..lineTo(lastX, size.height)
      ..lineTo(firstX, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.03)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final glow = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(line, glow);

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(line, stroke);

    final last = Offset(lastX, lastY);
    canvas.drawCircle(
      last,
      5.5,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    canvas.drawCircle(last, 3.2, Paint()..color = color);
    canvas.drawCircle(
      last,
      3.2,
      Paint()
        ..color = pointBorderColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  static double _sampleY(
    double sample,
    double scaleMax,
    double topPadding,
    double usableHeight,
  ) {
    final ratio = (sample / scaleMax).clamp(0.0, 1.0);
    return topPadding + (1 - ratio) * usableHeight;
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.revision != revision ||
      old.maxValue != maxValue ||
      old.samples != samples ||
      old.color != color ||
      old.gridColor != gridColor ||
      old.pointBorderColor != pointBorderColor;
}

/// Ring-buffer-backed sample history. Traffic and memory revisions are kept
/// separate so one telemetry stream does not rebuild every dashboard card.
class _SparkHistory {
  _SparkHistory({required this.capacity});
  final int capacity;
  final List<double> _up = [];
  final List<double> _down = [];
  final List<double> _mem = [];
  late final List<double> upSamples = UnmodifiableListView(_up);
  late final List<double> downSamples = UnmodifiableListView(_down);
  late final List<double> memorySamples = UnmodifiableListView(_mem);
  final trafficRevision = ValueNotifier(0);
  final memoryRevision = ValueNotifier(0);
  int _trafficDataRevision = 0;
  int _memoryDataRevision = 0;

  int get trafficDataRevision => _trafficDataRevision;
  int get memoryDataRevision => _memoryDataRevision;

  void pushTraffic(double up, double down, {bool notify = true}) {
    _push(_up, up);
    _push(_down, down);
    _trafficDataRevision++;
    if (notify) trafficRevision.value += 1;
  }

  void pushMemory(double inuse, {bool notify = true}) {
    _push(_mem, inuse);
    _memoryDataRevision++;
    if (notify) memoryRevision.value += 1;
  }

  void clearMemory({bool notify = true}) {
    if (_mem.isEmpty) return;
    _mem.clear();
    _memoryDataRevision++;
    if (notify) memoryRevision.value += 1;
  }

  void reset({bool notify = true}) {
    final hadTraffic = _up.isNotEmpty || _down.isNotEmpty;
    final hadMemory = _mem.isNotEmpty;
    if (!hadTraffic && !hadMemory) return;
    _up.clear();
    _down.clear();
    _mem.clear();
    if (hadTraffic) _trafficDataRevision++;
    if (hadMemory) _memoryDataRevision++;
    if (notify && hadTraffic) trafficRevision.value += 1;
    if (notify && hadMemory) memoryRevision.value += 1;
  }

  void _push(List<double> series, double value) {
    series.add(value);
    if (series.length > capacity) series.removeAt(0);
  }

  void dispose() {
    trafficRevision.dispose();
    memoryRevision.dispose();
  }
}
