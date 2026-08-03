import 'package:flutter/material.dart';

import 'active_listenable_builder.dart';
import 'app_background.dart';
import 'delay_badge.dart';
import 'pressable_scale.dart';

/// One node card in a group's grid. It rebuilds only when its own selection or
/// pin state changes, rather than whenever either group-wide value changes.
class ProxyNodeTile extends StatelessWidget {
  const ProxyNodeTile({
    super.key,
    required this.name,
    required this.type,
    required this.delay,
    this.selectable = true,
    this.showSelection = true,
    required this.nowListenable,
    required this.fixedListenable,
    required this.onSelect,
    required this.onTestDelay,
  });

  final String name;
  final String type;
  final ValueNotifier<int>? delay;
  final bool selectable;
  final bool showSelection;
  final ValueNotifier<String> nowListenable;
  final ValueNotifier<String> fixedListenable;
  final VoidCallback onSelect;
  final VoidCallback onTestDelay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return ActiveValueListenableSelector<String, bool>(
      valueListenable: nowListenable,
      selector: (now) => showSelection && now == name,
      builder: (_, selected, _) {
        return ActiveValueListenableSelector<String, bool>(
          valueListenable: fixedListenable,
          selector: (fixed) => selectable && fixed == name,
          builder: (_, isPinned, _) {
            // Three visual states stack:
            //   none      → surfaceContainerHigh / outlineVariant
            //   selected  → primaryContainer / primary @ 0.5
            //   pinned    → solid orange / white text — high contrast
            //                hint that tapping again unpins.
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
                onTap: selectable ? onSelect : null,
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
                                    name,
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
                              type,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: fg.withValues(alpha: 0.75)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      NodeDelay(delay: delay, onTest: onTestDelay),
                    ],
                  ),
                ),
              ),
            );
            return PressableScale(
              // Put the stable raster below the scale transform so press
              // feedback composites the cached tile instead of repainting it.
              child: RepaintBoundary(
                child: isPinned
                    ? tile
                    : AppSurfaceBackdrop(borderRadius: radius, child: tile),
              ),
            );
          },
        );
      },
    );
  }
}
