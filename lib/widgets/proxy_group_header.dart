import 'package:flutter/material.dart';

import '../session.dart';
import 'pressable_scale.dart';
import 'proxy_avatar.dart';

class ProxyGroupHeader extends StatelessWidget {
  const ProxyGroupHeader({
    super.key,
    required this.group,
    required this.showIcon,
    required this.testing,
    required this.expanded,
    required this.onToggle,
    required this.onTest,
  });

  final ProxyGroup group;
  final bool showIcon;
  final bool testing;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // ColoredBox keeps the pinned-header backdrop opaque so scrolling content
    // doesn't bleed through the gap between cards. A single Material below it
    // owns ink rendering — nesting Materials swallows the splash.
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: PressableScale(
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
                    if (showIcon) ...[
                      ProxyAvatar(name: group.name, icon: group.icon),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: group.now,
                        builder: (_, now, _) {
                          final displayNow = group.canSelectMembers
                              ? (now.isEmpty ? '-' : now)
                              : '*';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                group.name,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${group.type}  ·  $displayNow',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${group.memberCount}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '组内延迟测试',
                      visualDensity: VisualDensity.compact,
                      onPressed: testing ? null : onTest,
                      icon: testing
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.speed_rounded, size: 20),
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
      ),
    );
  }
}
