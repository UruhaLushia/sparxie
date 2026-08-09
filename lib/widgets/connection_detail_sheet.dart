import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../layout_breakpoints.dart';
import '../controller_view_state.dart';
import '../utils.dart';
import 'active_listenable_builder.dart';
import 'app_background.dart';

const _wideDetailsBreakpoint = 560.0;

class ConnectionDetailsPanel extends StatelessWidget {
  const ConnectionDetailsPanel({
    super.key,
    required this.row,
    required this.showConnectionLog,
    required this.onClose,
    this.timeTicks,
  });

  final ConnectionRow row;
  final bool showConnectionLog;
  final VoidCallback? onClose;
  final ValueListenable<int>? timeTicks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final closeAtBottom =
        MediaQuery.sizeOf(context).width < appWideLayoutBreakpoint &&
        onClose != null;
    final source = _sourceText(row);
    final dest = _destinationText(row);
    final host = _distinctHostText(row, dest);
    final inboundAddress = _inboundAddressText(row);
    final hasConnectionLogs =
        showConnectionLog && row.connectionLogs.isNotEmpty;
    final endpointEntries = <(String, String)>[
      if (host != null) ('主机', host),
      ('来源', source),
      ('目标', dest),
    ];
    final connectionEntries = <(String, String)>[
      if (row.network.isNotEmpty) ('网络', row.network),
      ('入站类型', row.connType.isEmpty ? '-' : row.connType),
      if (row.inboundName.isNotEmpty) ('入站名称', row.inboundName),
      if (inboundAddress.isNotEmpty) ('入站地址', inboundAddress),
      if (row.dnsMode.isNotEmpty) ('DNS 模式', row.dnsMode),
      if (row.sniffHost.isNotEmpty) ('嗅探域名', row.sniffHost),
      if (row.id.isNotEmpty) ('连接 ID', row.id),
      if (row.start != null) ('建立时间', row.start!.toLocal().toString()),
    ];
    final processEntries = <(String, String)>[
      if (row.process.isNotEmpty) ('名称', row.process),
      if (row.processPath.isNotEmpty) ('路径', row.processPath),
      if (row.uid != 0) ('UID', '${row.uid}'),
    ];
    final routingEntries = <(String, String)>[
      if (row.rule.isNotEmpty) ('规则', row.rule),
      if (row.rulePayload.isNotEmpty) ('内容', row.rulePayload),
      ('代理链', row.chainsLabel.isEmpty ? '-' : row.chainsLabel),
    ];

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Material(
        color: surfaceTheme.modalSurfaceColor(scheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    10,
                    12,
                    closeAtBottom ? 8 : 13,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ConnectionHeader(
                        onClose: closeAtBottom ? null : onClose,
                      ),
                      const SizedBox(height: 8),
                      _ConnectionTransferSummary(
                        row: row,
                        timeTicks: timeTicks,
                      ),
                      const SizedBox(height: 8),
                      SelectionArea(
                        child: _ConnectionInfoBody(
                          endpointEntries: endpointEntries,
                          connectionEntries: connectionEntries,
                          processEntries: processEntries,
                          routingEntries: routingEntries,
                          logs: hasConnectionLogs ? row.connectionLogs : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (closeAtBottom) _ConnectionCloseAction(onClose: onClose!),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.hub_rounded, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '连接详情',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
              backgroundColor: scheme.errorContainer,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: onClose,
            icon: const Icon(Icons.link_off_rounded, size: 16),
            label: const Text('关闭连接'),
          ),
        ],
      ],
    );
  }
}

class _ConnectionCloseAction extends StatelessWidget {
  const _ConnectionCloseAction({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42)),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            foregroundColor: scheme.onErrorContainer,
            backgroundColor: scheme.errorContainer,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: onClose,
          icon: const Icon(Icons.link_off_rounded, size: 16),
          label: const Text('关闭连接'),
        ),
      ),
    );
  }
}

class _ConnectionTransferSummary extends StatelessWidget {
  const _ConnectionTransferSummary({required this.row, this.timeTicks});

  final ConnectionRow row;
  final ValueListenable<int>? timeTicks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = Text(
      '传输统计',
      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    );
    Widget buildDuration() => _ConnectionMetric(
      label: '持续',
      value: _formatDuration(row.start),
      emphasized: true,
    );
    final ticks = timeTicks;
    final duration = ticks == null
        ? buildDuration()
        : ValueListenableBuilder<int>(
            valueListenable: ticks,
            builder: (_, _, _) => buildDuration(),
          );
    final metrics = ActiveValueListenableBuilder<RowBytes>(
      valueListenable: row.bytes,
      builder: (_, bytes, _) => Row(
        children: [
          _ConnectionMetric(label: '上传', value: formatBytes(bytes.upload)),
          const _MetricSeparator(),
          _ConnectionMetric(label: '下载', value: formatBytes(bytes.download)),
          const _MetricSeparator(),
          duration,
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideDetailsBreakpoint;
        return Container(
          padding: wide
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : const EdgeInsets.fromLTRB(11, 9, 11, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: wide
              ? Row(
                  children: [
                    title,
                    const SizedBox(width: 18),
                    Expanded(child: metrics),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 9), metrics],
                ),
        );
      },
    );
  }
}

class _ConnectionInfoBody extends StatelessWidget {
  const _ConnectionInfoBody({
    required this.endpointEntries,
    required this.connectionEntries,
    required this.processEntries,
    required this.routingEntries,
    required this.logs,
  });

  final List<(String, String)> endpointEntries;
  final List<(String, String)> connectionEntries;
  final List<(String, String)> processEntries;
  final List<(String, String)> routingEntries;
  final List<String>? logs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final endpoint = _ConnectionInfoSection(
          title: '端点',
          icon: Icons.swap_horiz_rounded,
          entries: endpointEntries,
        );
        final connection = _ConnectionInfoSection(
          title: '连接',
          icon: Icons.lan_outlined,
          entries: connectionEntries,
        );
        final process = processEntries.isEmpty
            ? null
            : _ConnectionInfoSection(
                title: '进程',
                icon: Icons.apps_rounded,
                entries: processEntries,
              );
        final routing = _ConnectionInfoSection(
          title: '路由',
          icon: Icons.route_rounded,
          entries: routingEntries,
        );
        final logSection = logs == null
            ? null
            : _ConnectionLogSection(logs: logs!);

        if (constraints.maxWidth < _wideDetailsBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              endpoint,
              const SizedBox(height: 8),
              connection,
              if (process != null) ...[const SizedBox(height: 8), process],
              const SizedBox(height: 8),
              routing,
              if (logSection != null) ...[
                const SizedBox(height: 8),
                logSection,
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  endpoint,
                  if (process != null) ...[const SizedBox(height: 8), process],
                  const SizedBox(height: 8),
                  routing,
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  connection,
                  if (logSection != null) ...[
                    const SizedBox(height: 8),
                    logSection,
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConnectionMetric extends StatelessWidget {
  const _ConnectionMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 20,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: emphasized ? scheme.primary : scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSeparator extends StatelessWidget {
  const _MetricSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 26,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
  }
}

class _ConnectionInfoSection extends StatelessWidget {
  const _ConnectionInfoSection({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final divider = scheme.outlineVariant.withValues(alpha: 0.38);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
            child: Row(
              children: [
                Icon(icon, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: divider),
          for (var index = 0; index < entries.length; index++) ...[
            _ConnectionInfoRow(
              label: entries[index].$1,
              value: entries[index].$2,
            ),
            if (index != entries.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 78),
                child: Divider(height: 1, thickness: 0.5, color: divider),
              ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionInfoRow extends StatelessWidget {
  const _ConnectionInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionLogSection extends StatelessWidget {
  const _ConnectionLogSection({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: scheme.onSurface,
      height: 1.35,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '连接日志',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < logs.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Text(logs[i], style: textStyle),
                ),
                if (i != logs.length - 1)
                  const Divider(height: 1, thickness: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDuration(DateTime? start) {
  if (start == null) return '—';
  final duration = DateTime.now().difference(start);
  if (duration.isNegative) return '0s';
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }
  return '${duration.inSeconds}s';
}

String _sourceText(ConnectionRow row) {
  if (row.sourceIp.isEmpty) return '-';
  if (row.sourcePort == 0) return row.sourceIp;
  return '${row.sourceIp}:${row.sourcePort}';
}

String? _distinctHostText(ConnectionRow row, String destination) {
  final host = row.host.trim();
  if (host.isEmpty) return null;
  final destinationIp = row.destinationIp.trim();
  final port = row.destinationPort;
  if (host == destination || host == destinationIp) return null;
  if (destinationIp.isNotEmpty && port != 0) {
    if (host == '$destinationIp:$port' || host == '[$destinationIp]:$port') {
      return null;
    }
  }
  return host;
}

String _inboundAddressText(ConnectionRow row) {
  if (row.inboundIp.isEmpty) return '';
  if (row.inboundPort == 0) return row.inboundIp;
  return '${row.inboundIp}:${row.inboundPort}';
}

String _destinationText(ConnectionRow row) {
  final host = row.destinationIp.isEmpty ? row.host : row.destinationIp;
  if (host.isEmpty) return '-';
  if (row.destinationPort == 0) return host;
  return '$host:${row.destinationPort}';
}
