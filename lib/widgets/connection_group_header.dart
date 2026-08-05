import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gamepad_navigation.dart';
import '../session.dart';
import '../utils.dart';
import 'active_listenable_builder.dart';
import 'app_background.dart';
import 'process_icon.dart';
import 'transient_animation.dart';

/// Expandable header for one process group in the grouped connections view.
/// Mirrors [ProxyGroupHeader]'s look: leading icon, label, member-count
/// badge, and live byte/speed chips fed by the summary's notifiers.
class ConnectionGroupHeader extends StatelessWidget {
  const ConnectionGroupHeader({
    super.key,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    this.onCloseAll,
    this.onClearAll,
    this.processIcons,
    this.showIcon = true,
    this.showAppName = false,
    this.groupBackdrop = false,
  });

  final ConnectionGroupSummary summary;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onCloseAll;
  final VoidCallback? onClearAll;
  final ProcessIconCache? processIcons;
  final bool showIcon;
  final bool showAppName;

  /// Shares one blur pass with sibling headers in an [AppBackdropGroup].
  final bool groupBackdrop;

  /// Sentinel key for mihomo's internal connections (see Rust `INNER_KEY`).
  /// These have no source/process, so they get a fixed icon and label.
  static const String innerKey = 'inner';
  bool get _isInner => summary.key == innerKey;

  String get _key {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    return isAndroid ? summary.process : summary.processPath;
  }

  String _title(String? appName) {
    if (appName != null && appName.isNotEmpty) return appName;
    final raw = summary.label;
    final label = raw.endsWith('.exe') ? raw.substring(0, raw.length - 4) : raw;
    return label.isEmpty ? '未知进程' : label;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final cache = processIcons;
    // Inner connections have no process/source, so never resolve an icon/name.
    final wantIcon = showIcon && cache != null && !_isInner;
    final nameKey = _key;
    final wantName =
        showAppName && cache != null && !_isInner && nameKey.isNotEmpty;
    if (wantName) cache.requestName(nameKey);
    const radius = BorderRadius.all(Radius.circular(14));

    return ColoredBox(
      color: surfaceTheme.pageColor(scheme.surface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: AppFocusHighlight(
          borderRadius: radius,
          child: AppSurfaceBackdrop(
            borderRadius: radius,
            grouped: groupBackdrop,
            child: Material(
              color: surfaceTheme.surfaceColor(
                scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                0.04,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: surfaceTheme.outlineSide(
                  scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: radius,
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                  child: Row(
                    children: [
                      // Icons only make sense for a local backend (cache present).
                      if (_isInner && showIcon && cache != null) ...[
                        _InnerIcon(scheme: scheme),
                        const SizedBox(width: 12),
                      ] else if (wantIcon) ...[
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
                                ? ActiveListenableSelector<String?>(
                                    listenable: cache,
                                    selector: () => cache.nameFor(nameKey),
                                    builder: (_, appName, _) =>
                                        _titleText(context, _title(appName)),
                                  )
                                : _titleText(context, _title(null)),
                            const SizedBox(height: 2),
                            _StatsLine(summary: summary, scheme: scheme),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActiveValueListenableBuilder<int>(
                        valueListenable: summary.count,
                        pauseWhileScrolling: true,
                        builder: (_, count, _) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                      ),
                      if (onCloseAll != null)
                        IconButton(
                          tooltip: '关闭该来源全部连接',
                          visualDensity: VisualDensity.compact,
                          onPressed: onCloseAll,
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      if (onClearAll != null)
                        IconButton(
                          tooltip: '清空该组已关闭连接',
                          visualDensity: VisualDensity.compact,
                          onPressed: onClearAll,
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                      TransientAnimatedRotation(
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

/// Fixed badge for the Inner group (mihomo's internal connections), which has
/// no process/source icon to resolve.
class _InnerIcon extends StatelessWidget {
  const _InnerIcon({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.hub_outlined,
        size: 22,
        color: scheme.onSecondaryContainer,
      ),
    );
  }
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
        Flexible(
          child: ActiveValueListenableBuilder<RowBytes>(
            valueListenable: summary.bytes,
            pauseWhileScrolling: true,
            builder: (_, b, _) => Text(
              '↑${formatBytes(b.upload)} ↓${formatBytes(b.download)}',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ActiveValueListenableBuilder<RowSpeeds>(
          valueListenable: summary.speeds,
          pauseWhileScrolling: true,
          builder: (_, s, _) {
            if (s.upload == BigInt.zero && s.download == BigInt.zero) {
              return const SizedBox.shrink();
            }
            return Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '↑${formatBytes(s.upload)}/s ↓${formatBytes(s.download)}/s',
                  style: style?.copyWith(color: scheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
