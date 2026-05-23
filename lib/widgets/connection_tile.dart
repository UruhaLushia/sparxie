import 'package:flutter/material.dart';

import '../session.dart';
import '../utils.dart';
import 'connection_tag.dart';

/// Connection list row:
///   line 1: `process → host`        time      close
///   line 2: chips — protocol(network), active proxy, ↑/↓ totals
class ConnectionTile extends StatelessWidget {
  const ConnectionTile({
    super.key,
    required this.row,
    required this.onTap,
    required this.onClose,
  });

  final ConnectionRow row;
  final VoidCallback onTap;
  final VoidCallback onClose;

  String get _title {
    final p = row.process.replaceAll(RegExp(r'\.exe$'), '');
    final left = p.isNotEmpty ? p : row.sourceIp;
    return left.isEmpty ? row.host : '$left → ${row.host}';
  }

  String _ago(DateTime start) {
    final diff = DateTime.now().difference(start);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s 前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m 前';
    if (diff.inHours < 24) return '${diff.inHours}h 前';
    return '${diff.inDays}d 前';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeText = row.start == null ? '' : _ago(row.start!);

    // Tile chrome rebuilds only on identity change. Bytes line repaints
    // independently when this row's counters tick.
    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (timeText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      timeText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  IconButton(
                    tooltip: '关闭',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (row.protocolLabel.isNotEmpty) ...[
                      ConnectionTag(
                        label: row.protocolLabel,
                        variant: ConnectionTagVariant.dot,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (row.activeProxy.isNotEmpty) ...[
                      ConnectionTag(
                        label: row.activeProxy,
                        variant: ConnectionTagVariant.bordered,
                      ),
                      const SizedBox(width: 6),
                    ],
                    // Only this chip rebuilds each tick; the static chips
                    // above stay stable to avoid wasted work on long lists.
                    ValueListenableBuilder<RowBytes>(
                      valueListenable: row.bytes,
                      builder: (_, bytes, _) => ConnectionTag(
                        label:
                            '↑ ${formatBytes(bytes.upload)}  ↓ ${formatBytes(bytes.download)}',
                        variant: ConnectionTagVariant.bordered,
                      ),
                    ),
                    ValueListenableBuilder<RowSpeeds>(
                      valueListenable: row.speeds,
                      builder: (_, speeds, _) {
                        if (speeds.upload == BigInt.zero &&
                            speeds.download == BigInt.zero) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ConnectionTag(
                            label:
                                '↑ ${formatBytes(speeds.upload)}/s  ↓ ${formatBytes(speeds.download)}/s',
                            variant: ConnectionTagVariant.bordered,
                            color: scheme.primary,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
