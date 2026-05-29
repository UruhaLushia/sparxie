import 'package:flutter/material.dart';

import '../session.dart';
import '../utils.dart';
import 'process_icon.dart';

/// Expandable header for one process group in the grouped connections view.
/// Mirrors [ProxyGroupHeader]'s look: leading icon, label, member-count
/// badge, and live byte/speed chips fed by the summary's notifiers.
class ConnectionGroupHeader extends StatelessWidget {
  const ConnectionGroupHeader({
    super.key,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.onCloseAll,
    this.processIcons,
    this.showIcon = true,
    this.showAppName = false,
  });

  final ConnectionGroupSummary summary;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCloseAll;
  final ProcessIconCache? processIcons;
  final bool showIcon;
  final bool showAppName;

  String _title(String? appName) {
    if (appName != null && appName.isNotEmpty) return appName;
    final label = summary.label.replaceAll(RegExp(r'\.exe$'), '');
    return label.isEmpty ? '未知进程' : label;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = processIcons;
    final wantIcon = showIcon && cache != null;
    final wantName = showAppName && cache != null && summary.process.isNotEmpty;
    if (wantName) cache.requestName(summary.process);

    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              child: Row(
                children: [
                  if (wantIcon) ...[
                    ProcessIcon(
                      cache: cache,
                      process: summary.process,
                      processPath: summary.processPath,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        wantName
                            ? ListenableBuilder(
                                listenable: cache,
                                builder: (_, _) => _titleText(
                                  context,
                                  _title(cache.nameFor(summary.process)),
                                ),
                              )
                            : _titleText(context, _title(null)),
                        const SizedBox(height: 2),
                        _StatsLine(summary: summary, scheme: scheme),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: summary.count,
                    builder: (_, count, _) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭该进程全部连接',
                    visualDensity: VisualDensity.compact,
                    onPressed: onCloseAll,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleText(BuildContext context, String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    overflow: TextOverflow.ellipsis,
  );
}

class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.summary, required this.scheme});

  final ConnectionGroupSummary summary;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Row(
      children: [
        ValueListenableBuilder<RowBytes>(
          valueListenable: summary.bytes,
          builder: (_, b, _) => Text(
            '↑${formatBytes(b.upload)} ↓${formatBytes(b.download)}',
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ValueListenableBuilder<RowSpeeds>(
          valueListenable: summary.speeds,
          builder: (_, s, _) {
            if (s.upload == BigInt.zero && s.download == BigInt.zero) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '↑${formatBytes(s.upload)}/s ↓${formatBytes(s.download)}/s',
                style: style?.copyWith(color: scheme.primary),
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ],
    );
  }
}
