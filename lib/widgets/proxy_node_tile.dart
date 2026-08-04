import 'dart:async';

import 'package:flutter/material.dart';

import '../session.dart';
import 'active_listenable_builder.dart';
import 'app_background.dart';
import 'delay_badge.dart';
import 'proxy_node_context_menu.dart';

/// One node card in a group's grid. It rebuilds only when its own selection or
/// pin state changes, rather than whenever either group-wide value changes.
class ProxyNodeTile extends StatelessWidget {
  const ProxyNodeTile({
    super.key,
    required this.group,
    required this.member,
    this.loadDetails,
    required this.onSelect,
    required this.onToggleFixed,
    required this.onTestDelay,
  });

  final ProxyGroup group;
  final ProxyMember member;
  final Future<String> Function()? loadDetails;
  final VoidCallback onSelect;
  final VoidCallback onToggleFixed;
  final Future<void> Function() onTestDelay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return ProxyNodeContextMenu(
      group: group,
      member: member,
      loadDetails: loadDetails,
      onTestDelay: onTestDelay,
      onToggleFixed: onToggleFixed,
      child: ActiveValueListenableSelector<String, bool>(
        valueListenable: group.now,
        selector: (now) => !group.hidesExactNow && now == member.name,
        builder: (_, selected, _) {
          return ActiveValueListenableSelector<String, bool>(
            valueListenable: group.fixed,
            selector: (fixed) => group.canFixMembers && fixed == member.name,
            builder: (_, isPinned, _) {
              // Three visual states stack:
              //   none      → surfaceContainerHigh / outlineVariant
              //   selected  → primaryContainer / primary @ 0.5
              //   pinned    → solid orange / white text — high contrast.
              const pinnedColor = Color(0xfff97316);
              final Color bg;
              final Color border;
              final Color fg;
              if (isPinned) {
                bg = pinnedColor;
                border = pinnedColor;
                fg = Colors.white;
              } else if (selected) {
                bg = surfaceTheme.surfaceColor(
                  scheme.primaryContainer.withValues(alpha: 0.7),
                  0.12,
                );
                border = scheme.primary.withValues(alpha: 0.5);
                fg = scheme.onPrimaryContainer;
              } else {
                bg = surfaceTheme.surfaceColor(scheme.surfaceContainerHigh);
                border = surfaceTheme.outlineColor(
                  scheme.outlineVariant.withValues(alpha: 0.5),
                );
                fg = scheme.onSurface;
              }
              const radius = BorderRadius.all(Radius.circular(10));
              final tile = Material(
                color: bg,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(color: border),
                ),
                // The backdrop already clips this subtree when blur is active.
                // Keep one anti-aliased clip for solid and pinned variants.
                clipBehavior: !isPinned && surfaceTheme.effectiveBlur > 0
                    ? Clip.none
                    : Clip.antiAlias,
                child: InkWell(
                  borderRadius: radius,
                  onTap: group.canSelectOnTap ? onSelect : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  if (isPinned) ...[
                                    Icon(Icons.push_pin, size: 13, color: fg),
                                    const SizedBox(width: 4),
                                  ],
                                  Flexible(
                                    child: Text(
                                      member.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: selected || isPinned
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: fg,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                member.type,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: fg.withValues(alpha: 0.75),
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        NodeDelay(
                          delay: member.delay,
                          onTest: () => unawaited(onTestDelay()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              return isPinned
                  ? tile
                  : AppSurfaceBackdrop(borderRadius: radius, child: tile);
            },
          );
        },
      ),
    );
  }
}
