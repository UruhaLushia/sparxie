import 'dart:async';

import 'package:flutter/material.dart';

import '../gamepad_navigation.dart';
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
    return ProxyNodeContextMenu(
      group: group,
      member: member,
      loadDetails: loadDetails,
      onTestDelay: onTestDelay,
      onToggleFixed: onToggleFixed,
      onActivate: group.canSelectOnTap ? onSelect : null,
      child: ActiveValueListenableSelector<String, bool>(
        valueListenable: group.now,
        selector: (now) => !group.hidesExactNow && now == member.name,
        builder: (_, selected, _) {
          return ActiveValueListenableSelector<String, bool>(
            valueListenable: group.fixed,
            selector: (fixed) => group.canFixMembers && fixed == member.name,
            builder: (_, isPinned, _) => _ProxyNodeTileSurface(
              member: member,
              selected: selected,
              pinned: isPinned,
              onActivate: group.canSelectOnTap ? onSelect : null,
              onTestDelay: onTestDelay,
            ),
          );
        },
      ),
    );
  }
}

/// Proxy-node tile for read-only catalogs such as a subscription's node list.
/// It keeps the group tile's material, delay action, and long-press details,
/// while omitting selection and pin state that do not apply in this context.
class StandaloneProxyNodeTile extends StatelessWidget {
  const StandaloneProxyNodeTile({
    super.key,
    required this.member,
    this.loadDetails,
    required this.onTestDelay,
  });

  final ProxyMember member;
  final Future<String> Function()? loadDetails;
  final Future<void> Function() onTestDelay;

  @override
  Widget build(BuildContext context) {
    return ProxyNodeContextMenu(
      member: member,
      loadDetails: loadDetails,
      onTestDelay: onTestDelay,
      child: _ProxyNodeTileSurface(
        member: member,
        selected: false,
        pinned: false,
        onTestDelay: onTestDelay,
      ),
    );
  }
}

class _ProxyNodeTileSurface extends StatelessWidget {
  const _ProxyNodeTileSurface({
    required this.member,
    required this.selected,
    required this.pinned,
    this.onActivate,
    required this.onTestDelay,
  });

  final ProxyMember member;
  final bool selected;
  final bool pinned;
  final VoidCallback? onActivate;
  final Future<void> Function() onTestDelay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    const pinnedColor = Color(0xfff97316);
    final Color bg;
    final Color border;
    final Color fg;
    if (pinned) {
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
      clipBehavior: !pinned && surfaceTheme.effectiveBlur > 0
          ? Clip.none
          : Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        canRequestFocus: false,
        onTap: onActivate,
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
                        if (pinned) ...[
                          Icon(Icons.push_pin, size: 13, color: fg),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            member.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: selected || pinned
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
    final surface = pinned
        ? tile
        : AppSurfaceBackdrop(borderRadius: radius, child: tile);
    return AppFocusHighlight(borderRadius: radius, child: surface);
  }
}
