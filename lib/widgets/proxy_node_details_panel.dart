import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller_view_state.dart';
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
  Timer? _refreshTimer;
  Animation<double>? _routeAnimation;
  var _initialLoadScheduled = false;
  var _loading = false;
  var _refreshing = false;
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
    if (details.traffic != null) {
      _refreshTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refreshDetails()),
      );
    }
  }

  Future<void> _refreshDetails() async {
    final loader = widget.loadDetails;
    if (loader == null || _loading || _refreshing || _testing) return;
    _refreshing = true;
    try {
      final details = _ProxyNodeDetails.parse(await loader());
      if (mounted && details.traffic != null) {
        setState(() => _details = details);
      }
    } catch (_) {
      // Keep the last successful snapshot while the controller is unavailable.
    } finally {
      _refreshing = false;
    }
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
          if (awaitingDetails) const _NodeMetadataPlaceholder(),
          if (!awaitingDetails && details?.status != null)
            _NodeStatusDetails(status: details!.status!),
          if (!awaitingDetails &&
              details?.status != null &&
              details?.traffic != null)
            const SizedBox(height: 8),
          if (!awaitingDetails && details?.traffic != null)
            _NodeTrafficDetails(traffic: details!.traffic!),
          if (!awaitingDetails && attributes.isNotEmpty) ...[
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
    _refreshTimer?.cancel();
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    super.dispose();
  }
}

class _ProxyNodeDetails {
  const _ProxyNodeDetails({
    this.alive,
    this.attributes = const [],
    this.capabilities = const [],
    this.traffic,
    this.status,
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
    final traffic = _NodeTraffic.parse(fields['traffic']);
    final testError = text('test-error');
    final usage = text('usage-label');
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
      traffic: traffic,
      status: testError.isNotEmpty
          ? _NodeStatus(label: '延迟测试', value: testError, error: true)
          : usage.isNotEmpty
          ? _NodeStatus(label: '使用频率', value: usage)
          : null,
    );
  }

  final bool? alive;
  final List<(String, String)> attributes;
  final List<String> capabilities;
  final _NodeTraffic? traffic;
  final _NodeStatus? status;
}

class _NodeStatus {
  const _NodeStatus({
    required this.label,
    required this.value,
    this.error = false,
  });

  final String label;
  final String value;
  final bool error;
}

class _NodeTraffic {
  const _NodeTraffic({
    required this.upload,
    required this.download,
    required this.uploadSpeed,
    required this.downloadSpeed,
    required this.uploadMaxSpeed,
    required this.downloadMaxSpeed,
  });

  static _NodeTraffic? parse(Object? raw) {
    final traffic = asMap(raw);
    if (traffic.isEmpty) return null;
    return _NodeTraffic(
      upload: asBigInt(traffic['out']),
      download: asBigInt(traffic['in']),
      uploadSpeed: asBigInt(traffic['outCurrentSpeed']),
      downloadSpeed: asBigInt(traffic['inCurrentSpeed']),
      uploadMaxSpeed: asBigInt(traffic['outMaxSpeed']),
      downloadMaxSpeed: asBigInt(traffic['inMaxSpeed']),
    );
  }

  final BigInt upload;
  final BigInt download;
  final BigInt uploadSpeed;
  final BigInt downloadSpeed;
  final BigInt uploadMaxSpeed;
  final BigInt downloadMaxSpeed;

  BigInt get total => upload + download;
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

class _NodeTrafficDetails extends StatelessWidget {
  const _NodeTrafficDetails({required this.traffic});

  final _NodeTraffic traffic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '详细信息',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text('总计 ${formatBytes(traffic.total)}', style: valueStyle),
            ],
          ),
          const SizedBox(height: 8),
          _NodeTrafficRow(
            label: '流量',
            value:
                '上传 ${formatBytes(traffic.upload)}  下载 ${formatBytes(traffic.download)}',
          ),
          _NodeTrafficRow(
            label: '当前速度',
            value:
                '上传 ${formatBytes(traffic.uploadSpeed)}/s  下载 ${formatBytes(traffic.downloadSpeed)}/s',
          ),
          _NodeTrafficRow(
            label: '最高速度',
            value:
                '上传 ${formatBytes(traffic.uploadMaxSpeed)}/s  下载 ${formatBytes(traffic.downloadMaxSpeed)}/s',
          ),
        ],
      ),
    );
  }
}

class _NodeStatusDetails extends StatelessWidget {
  const _NodeStatusDetails({required this.status});

  final _NodeStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = status.error ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status.error ? Icons.error_outline_rounded : Icons.insights_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(
            status.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status.value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: status.error ? color : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeTrafficRow extends StatelessWidget {
  const _NodeTrafficRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
