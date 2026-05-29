import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../session.dart';
import '../utils.dart';
import 'connection_tag.dart';
import 'process_icon.dart';

/// Connection list row:
///   line 1: `process → host` (or just host for group members) · time · close
///   line 2: chips — protocol(network), active proxy, ↑/↓ totals
class ConnectionTile extends StatelessWidget {
  const ConnectionTile({
    super.key,
    required this.row,
    required this.onTap,
    required this.onClose,
    this.processIcons,
    this.showIcon = false,
    this.showAppName = false,
    this.hideProcess = false,
    this.compact = false,
  });

  final ConnectionRow row;
  final VoidCallback onTap;
  final VoidCallback onClose;

  /// Non-null only on a local backend.
  final ProcessIconCache? processIcons;
  final bool showIcon;
  final bool showAppName;

  /// Drop the leading `process →` from the title — used for group members,
  /// where the process already labels the group header.
  final bool hideProcess;

  /// Tighter vertical padding for dense lists (e.g. group members).
  final bool compact;

  // Android keys by package name (mihomo's `process`), desktop by exec path.
  String _iconKey() {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    return isAndroid ? row.process : row.processPath;
  }

  String _rawProcessName() => row.process.replaceAll(RegExp(r'\.exe$'), '');

  String _titleFor(String? appName) {
    if (hideProcess) {
      return row.host.isEmpty ? row.sourceIp : row.host;
    }
    final p = (appName != null && appName.isNotEmpty)
        ? appName
        : _rawProcessName();
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
    final cache = processIcons;
    final iconKey = _iconKey();
    final wantIcon = showIcon && cache != null;
    final wantName =
        !hideProcess && showAppName && cache != null && iconKey.isNotEmpty;
    if (wantName) cache.requestName(iconKey);

    // Tile chrome rebuilds only on identity change. Bytes line repaints
    // independently when this row's counters tick.
    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            wantIcon ? 10 : 14,
            compact ? 6 : 8,
            8,
            compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (wantIcon) ...[
                ProcessIcon(
                  cache: cache,
                  process: row.process,
                  processPath: row.processPath,
                  size: 38,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: wantName
                              ? ListenableBuilder(
                                  listenable: cache,
                                  builder: (context, _) => Text(
                                    _titleFor(cache.nameFor(iconKey)),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : Text(
                                  _titleFor(null),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        if (timeText.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            timeText,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        IconButton(
                          tooltip: '关闭',
                          onPressed: onClose,
                          icon: const Icon(Icons.close, size: 20),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
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
            ],
          ),
        ),
      ),
    );
  }
}
