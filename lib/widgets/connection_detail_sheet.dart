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
    final entries = <(String, String)>[
      ('主机', row.host),
      if (row.id.isNotEmpty) ('连接 ID', row.id),
      ('网络', row.network.isEmpty ? '-' : row.network),
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
      ('规则', row.rule.isEmpty ? '-' : row.rule),
      if (row.rulePayload.isNotEmpty) ('匹配规则', row.rulePayload),
      ('代理链', row.chainsLabel.isEmpty ? '-' : row.chainsLabel),
      if (showConnectionLog && row.connectionLogs.isNotEmpty)
        ('连接日志', row.connectionLogs.join('\n')),
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
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
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

String _destinationText(ConnectionRow row) {
  final host = row.destinationIp.isEmpty ? row.host : row.destinationIp;
  if (host.isEmpty) return '-';
  if (row.destinationPort == 0) return host;
  return '$host:${row.destinationPort}';
}
