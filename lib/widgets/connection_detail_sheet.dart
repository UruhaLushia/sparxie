import 'package:flutter/material.dart';

import '../session.dart';
import '../utils.dart';

class ConnectionDetailSheet extends StatelessWidget {
  const ConnectionDetailSheet({
    super.key,
    required this.row,
    required this.showConnectionLog,
    required this.onClose,
  });

  final ConnectionRow row;
  final bool showConnectionLog;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final source = '${row.sourceIp}:${row.sourcePort}';
    final dest = _destinationText(row);
    final bytes = row.bytes.value;
    final hasConnectionLogs =
        showConnectionLog && row.connectionLogs.isNotEmpty;
    final entries = <(String, String)>[
      ('主机', row.host),
      if (row.id.isNotEmpty) ('连接 ID', row.id),
      if (row.network.isNotEmpty) ('网络', row.network),
      ('类型', row.connType.isEmpty ? '-' : row.connType),
      ('来源', source),
      ('目标', dest),
      if (row.inboundIp.isNotEmpty) ('入站 IP', row.inboundIp),
      if (row.inboundPort != 0) ('入站端口', '${row.inboundPort}'),
      if (row.inboundName.isNotEmpty) ('入站名称', row.inboundName),
      if (row.dnsMode.isNotEmpty) ('DNS 模式', row.dnsMode),
      if (row.sniffHost.isNotEmpty) ('嗅探主机', row.sniffHost),
      if (row.process.isNotEmpty) ('进程名', row.process),
      if (row.processPath.isNotEmpty) ('进程路径', row.processPath),
      if (row.uid != 0) ('UID', '${row.uid}'),
      if (row.rule.isNotEmpty) ('规则类型', row.rule),
      if (row.rulePayload.isNotEmpty) ('规则内容', row.rulePayload),
      ('代理链', row.chainsLabel.isEmpty ? '-' : row.chainsLabel),
      ('上传量', formatBytes(bytes.upload)),
      ('下载量', formatBytes(bytes.download)),
      if (row.start != null) ('连接建立时间', row.start!.toLocal().toString()),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.host,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onClose != null)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('关闭'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onClose!();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length + (hasConnectionLogs ? 1 : 0),
                separatorBuilder: (_, index) => SizedBox(
                  height: hasConnectionLogs && index == entries.length - 1
                      ? 12
                      : 6,
                ),
                itemBuilder: (context, index) {
                  if (hasConnectionLogs && index == entries.length) {
                    return _ConnectionLogSection(logs: row.connectionLogs);
                  }
                  final (label, value) = entries[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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
                  child: SelectableText(logs[i], style: textStyle),
                ),
                if (i != logs.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.45),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _destinationText(ConnectionRow row) {
  final host = row.destinationIp.isEmpty ? row.host : row.destinationIp;
  if (host.isEmpty) return '-';
  if (row.destinationPort == 0) return host;
  return '$host:${row.destinationPort}';
}
