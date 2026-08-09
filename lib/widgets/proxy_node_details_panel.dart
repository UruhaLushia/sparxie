import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../session.dart';
import '../utils.dart';
import 'active_listenable_builder.dart';
import 'anchored_details_panel_surface.dart';

typedef ProxyNodeDetailsLoader = Future<String> Function();

class ProxyNodeDetailsPanel extends StatefulWidget {
  const ProxyNodeDetailsPanel({
    super.key,
    this.group,
    required this.member,
    this.loadDetails,
    this.onTestDelay,
    this.onToggleFixed,
  }) : assert(onToggleFixed == null || group != null);

  final ProxyGroup? group;
  final ProxyMember member;
  final ProxyNodeDetailsLoader? loadDetails;
  final Future<void> Function()? onTestDelay;
  final VoidCallback? onToggleFixed;

  @override
  State<ProxyNodeDetailsPanel> createState() => _ProxyNodeDetailsPanelState();
}

class _ProxyNodeDetailsPanelState extends State<ProxyNodeDetailsPanel> {
  _ProxyNodeDetails? _details;
  Animation<double>? _routeAnimation;
  var _initialLoadScheduled = false;
  var _loading = false;
  var _testing = false;

  bool get _awaitingDetails => widget.loadDetails != null && _details == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_handleRouteStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_handleRouteStatus);
    }
    _scheduleInitialLoad();
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _scheduleInitialLoad();
  }

  void _scheduleInitialLoad() {
    if (_initialLoadScheduled || widget.loadDetails == null) return;
    final animation = _routeAnimation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      return;
    }
    _initialLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = _routeAnimation;
      if (animation != null && animation.status != AnimationStatus.completed) {
        return;
      }
      unawaited(_loadDetails());
    });
  }

  Future<void> _loadDetails() async {
    final loader = widget.loadDetails;
    if (loader == null) return;
    if (!_loading) setState(() => _loading = true);
    var details = const _ProxyNodeDetails();
    try {
      details = _ProxyNodeDetails.parse(await loader());
    } catch (_) {
      // The catalog data below remains useful when a backend has no detail API.
    }
    if (!mounted) return;
    setState(() {
      _details = details;
      _loading = false;
    });
  }

  Future<void> _runDelayTest() async {
    final test = widget.onTestDelay;
    if (test == null || _testing || _loading || _awaitingDetails) return;
    setState(() => _testing = true);
    try {
      await test();
      if (mounted && widget.loadDetails != null) await _loadDetails();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final attributes = details?.attributes ?? const [];
    final capabilities = details?.capabilities ?? const [];
    final awaitingDetails = _awaitingDetails;
    final group = widget.group;
    return AnchoredDetailsPanelSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NodeHeader(
            member: widget.member,
            alive: details?.alive,
            loading: _loading && !_testing,
          ),
          const SizedBox(height: 11),
          _NodeDelayHistory(
            member: widget.member,
            samples: details?.history ?? const [],
            showPlaceholder: awaitingDetails,
          ),
          if (awaitingDetails) ...[
            const SizedBox(height: 11),
            const _NodeMetadataPlaceholder(),
          ] else if (attributes.isNotEmpty) ...[
            const SizedBox(height: 11),
            SelectionArea(child: _NodeAttributes(rows: attributes)),
          ],
          if (!awaitingDetails && capabilities.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NodeCapabilities(values: capabilities),
          ],
          if (widget.onTestDelay != null || widget.onToggleFixed != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.onTestDelay != null)
                  Expanded(
                    child: _NodeDelayTestAction(
                      testing: _testing,
                      enabled: !awaitingDetails && !_loading,
                      onPressed: _runDelayTest,
                    ),
                  ),
                if (widget.onTestDelay != null && widget.onToggleFixed != null)
                  const SizedBox(width: 8),
                if (widget.onToggleFixed != null && group != null)
                  Expanded(
                    child: _NodeFixedAction(
                      group: group,
                      member: widget.member,
                      onPressed: widget.onToggleFixed!,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    super.dispose();
  }
}

class _ProxyNodeDetails {
  const _ProxyNodeDetails({
    this.alive,
    this.attributes = const [],
    this.capabilities = const [],
    this.history = const [],
  });

  factory _ProxyNodeDetails.parse(String raw) {
    final fields = asMap(jsonDecode(raw));
    String text(String key) {
      final value = fields[key];
      return value == null || value == '' || value == 0 ? '' : '$value';
    }

    const capabilityLabels = <String, String>{
      'udp': 'UDP',
      'uot': 'UOT',
      'xudp': 'XUDP',
      'tfo': 'TFO',
      'mptcp': 'MPTCP',
      'smux': 'SMUX',
    };
    final rawHistory = fields['history'];
    return _ProxyNodeDetails(
      alive: fields['alive'] is bool ? fields['alive'] as bool : null,
      attributes: [
        for (final entry in <(String, String)>[
          ('提供者', text('provider-name')),
          ('拨号代理', text('dialer-proxy')),
          ('网络接口', text('interface')),
          ('路由标记', text('routing-mark')),
        ])
          if (entry.$2.isNotEmpty) entry,
      ],
      capabilities: [
        for (final entry in capabilityLabels.entries)
          if (fields[entry.key] == true) entry.value,
      ],
      history: rawHistory is! List
          ? const []
          : [
              for (final item in rawHistory)
                if (asMap(item) case final entry when entry['delay'] != null)
                  _NodeDelaySample(
                    delay: asInt(entry['delay']),
                    time: DateTime.tryParse(
                      '${entry['time'] ?? ''}',
                    )?.toLocal(),
                  ),
            ],
    );
  }

  final bool? alive;
  final List<(String, String)> attributes;
  final List<String> capabilities;
  final List<_NodeDelaySample> history;
}

class _NodeDelaySample {
  const _NodeDelaySample({required this.delay, required this.time});

  final int delay;
  final DateTime? time;
}

class _NodeHeader extends StatelessWidget {
  const _NodeHeader({
    required this.member,
    required this.alive,
    required this.loading,
  });

  final ProxyMember member;
  final bool? alive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.dns_rounded, size: 19, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                member.type.isEmpty ? '未知类型' : member.type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (alive != null) ...[
          const SizedBox(width: 10),
          _NodeStateBadge(
            label: alive! ? '可用' : '不可用',
            color: alive! ? const Color(0xff16a34a) : scheme.error,
          ),
        ],
      ],
    );
  }
}

class _NodeDelayHistory extends StatelessWidget {
  const _NodeDelayHistory({
    required this.member,
    required this.samples,
    required this.showPlaceholder,
  });

  final ProxyMember member;
  final List<_NodeDelaySample> samples;
  final bool showPlaceholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = samples.length > 12
        ? samples.sublist(samples.length - 12)
        : samples;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.timeline_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '历史延迟',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              ActiveValueListenableBuilder<int>(
                valueListenable: member.delay,
                builder: (_, delay, _) {
                  final color = _delayColor(scheme, delay);
                  return Text(
                    '当前 ${_delayText(delay)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (showPlaceholder && samples.isEmpty)
            SizedBox(
              height: 104,
              child: Center(
                child: Text(
                  '正在加载延迟记录…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else if (visible.isEmpty)
            Text(
              '暂无历史延迟',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            RepaintBoundary(child: _NodeDelayChart(samples: visible)),
        ],
      ),
    );
  }
}

class _NodeDelayChart extends StatelessWidget {
  const _NodeDelayChart({required this.samples});

  final List<_NodeDelaySample> samples;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final measured = samples.where((sample) => sample.delay > 0).toList();
    final minDelay = measured.isEmpty
        ? 0
        : measured
              .map((sample) => sample.delay)
              .reduce((a, b) => a < b ? a : b);
    final maxDelay = measured.isEmpty
        ? 0
        : measured
              .map((sample) => sample.delay)
              .reduce((a, b) => a > b ? a : b);
    final range = measured.isEmpty
        ? '全部超时'
        : '最低 $minDelay ms · 最高 $maxDelay ms';
    final firstTime = samples.first.time;
    final lastTime = samples.last.time;
    final padding = measured.length <= 1
        ? 1.0
        : ((maxDelay - minDelay) * 0.14).clamp(2.0, 80.0);
    final minY = measured.isEmpty
        ? 0.0
        : (minDelay - padding).clamp(0.0, double.infinity);
    final maxY = measured.isEmpty ? 1.0 : maxDelay + padding;
    final maxX = samples.length <= 1 ? 1.0 : (samples.length - 1).toDouble();
    double xFor(int index) => samples.length == 1 ? 0.5 : index.toDouble();
    final delaySpots = [
      for (var i = 0; i < samples.length; i++)
        samples[i].delay > 0
            ? FlSpot(xFor(i), samples[i].delay.toDouble())
            : FlSpot.nullSpot,
    ];
    final timeoutSpots = [
      for (var i = 0; i < samples.length; i++)
        samples[i].delay <= 0 ? FlSpot(xFor(i), minY) : FlSpot.nullSpot,
    ];
    final gridColor = scheme.outlineVariant.withValues(alpha: 0.42);
    final tooltipText = TextStyle(
      color: scheme.onInverseSurface,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: '历史延迟，$range，共 ${samples.length} 次',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 88,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                clipData: const FlClipData.all(),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) / 2,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: gridColor, strokeWidth: 0.7),
                ),
                lineTouchData: LineTouchData(
                  touchSpotThreshold: 18,
                  getTouchedSpotIndicator: (bar, indexes) {
                    final color = bar.color == Colors.transparent
                        ? scheme.error
                        : scheme.primary;
                    return [
                      for (final _ in indexes)
                        TouchedSpotIndicatorData(
                          FlLine(
                            color: color.withValues(alpha: 0.28),
                            strokeWidth: 1,
                          ),
                          FlDotData(
                            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                              radius: 4,
                              color: color,
                              strokeWidth: 1.5,
                              strokeColor: scheme.surface,
                            ),
                          ),
                        ),
                    ];
                  },
                  touchTooltipData: LineTouchTooltipData(
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    tooltipMargin: 6,
                    tooltipBorderRadius: BorderRadius.circular(8),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        if (spot.spotIndex >= 0 &&
                            spot.spotIndex < samples.length)
                          LineTooltipItem(
                            '${_delayText(samples[spot.spotIndex].delay)}\n'
                            '${_fullTime(samples[spot.spotIndex].time)}',
                            tooltipText,
                          ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: delaySpots,
                    color: scheme.primary,
                    barWidth: 2,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    preventCurveOverShooting: true,
                    isStrokeCapRound: true,
                    isStrokeJoinRound: true,
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.primary.withValues(alpha: 0.18),
                          scheme.primary.withValues(alpha: 0.01),
                        ],
                      ),
                    ),
                    dotData: FlDotData(
                      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                        radius: 2.5,
                        color: _delayColor(scheme, spot.y.round()),
                        strokeWidth: 1.2,
                        strokeColor: scheme.surface,
                      ),
                    ),
                  ),
                  LineChartBarData(
                    spots: timeoutSpots,
                    color: Colors.transparent,
                    barWidth: 0,
                    dotData: FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 2.5,
                        color: scheme.error,
                        strokeWidth: 1.2,
                        strokeColor: scheme.surface,
                      ),
                    ),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                firstTime == null ? '--:--' : _shortTime(firstTime),
                style: _chartLabelStyle(context),
              ),
              Expanded(
                child: Text(
                  range,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _chartLabelStyle(context),
                ),
              ),
              Text(
                lastTime == null ? '--:--' : _shortTime(lastTime),
                style: _chartLabelStyle(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle? _chartLabelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 9,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

Color _delayColor(ColorScheme scheme, int delay) =>
    switch (classifyDelay(delay)) {
      DelayBucket.untested => scheme.onSurfaceVariant,
      DelayBucket.timeout => scheme.error,
      DelayBucket.fast => const Color(0xff16a34a),
      DelayBucket.slow => const Color(0xffd97706),
    };

String _delayText(int delay) => switch (classifyDelay(delay)) {
  DelayBucket.untested => '未测试',
  DelayBucket.timeout => '超时',
  DelayBucket.fast || DelayBucket.slow => '$delay ms',
};

String _shortTime(DateTime time) =>
    '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';

String _fullTime(DateTime? time) => time == null
    ? '时间未知'
    : '${time.year}-${_twoDigits(time.month)}-${_twoDigits(time.day)} '
          '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:'
          '${_twoDigits(time.second)}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class _NodeMetadataPlaceholder extends StatelessWidget {
  const _NodeMetadataPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = scheme.onSurfaceVariant.withValues(alpha: 0.12);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.32),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.42,
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: mark,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.64,
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: mark,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeAttributes extends StatelessWidget {
  const _NodeAttributes({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _NodeAttributeRow(label: rows[i].$1, value: rows[i].$2),
            if (i != rows.length - 1)
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.42),
              ),
          ],
        ],
      ),
    );
  }
}

class _NodeAttributeRow extends StatelessWidget {
  const _NodeAttributeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeCapabilities extends StatelessWidget {
  const _NodeCapabilities({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '支持 ${values.join('、')}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.task_alt_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              '支持',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                values.join('  ·  '),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeFixedAction extends StatelessWidget {
  const _NodeFixedAction({
    required this.group,
    required this.member,
    required this.onPressed,
  });

  final ProxyGroup group;
  final ProxyMember member;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xfff97316);
    return ActiveValueListenableBuilder<String>(
      valueListenable: group.fixed,
      builder: (_, fixed, _) {
        final pinned = fixed == member.name;
        final button = pinned
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: orange,
                  side: const BorderSide(color: orange),
                ),
                onPressed: onPressed,
                icon: const Icon(Icons.push_pin_outlined, size: 17),
                label: const Text('取消固定'),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: orange,
                ),
                onPressed: onPressed,
                icon: const Icon(Icons.push_pin_rounded, size: 17),
                label: const Text('固定此节点'),
              );
        return SizedBox(width: double.infinity, child: button);
      },
    );
  }
}

class _NodeDelayTestAction extends StatelessWidget {
  const _NodeDelayTestAction({
    required this.testing,
    required this.enabled,
    required this.onPressed,
  });

  final bool testing;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: testing || !enabled ? null : onPressed,
        icon: testing
            ? const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.speed_rounded, size: 17),
        label: Text(testing ? '测试中' : '延迟测试'),
      ),
    );
  }
}

class _NodeStateBadge extends StatelessWidget {
  const _NodeStateBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
