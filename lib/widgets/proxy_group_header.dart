import 'package:flutter/material.dart';

import '../gamepad_navigation.dart';
import '../controller_view_state.dart';
import 'active_listenable_builder.dart';
import 'app_background.dart';
import 'pressable_scale.dart';
import 'proxy_avatar.dart';
import 'transient_animation.dart';

class ProxyGroupHeader extends StatelessWidget {
  const ProxyGroupHeader({
    super.key,
    required this.group,
    required this.showIcon,
    required this.testing,
    required this.expanded,
    required this.searchOpen,
    required this.searchController,
    required this.onToggle,
    required this.onTest,
    required this.onToggleSearch,
    required this.onSearchChanged,
    required this.onLocate,
  });

  static const double cardHeight = 52;
  static const double searchRowExtent = 46;
  static const transitionDuration = Duration(milliseconds: 300);

  static double extentFor({required bool searchOpen}) =>
      cardHeight + 8 + (searchOpen ? searchRowExtent : 0);

  final ProxyGroup group;
  final bool showIcon;
  final bool testing;
  final bool expanded;
  final bool searchOpen;
  final TextEditingController? searchController;
  final VoidCallback onToggle;
  final VoidCallback onTest;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    const radius = BorderRadius.all(Radius.circular(14));
    return ColoredBox(
      color: surfaceTheme.pageColor(scheme.surface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFocusHighlight(
              borderRadius: radius,
              child: PressableScale(
                child: SizedBox(
                  height: cardHeight,
                  child: AppSurfaceBackdrop(
                    borderRadius: radius,
                    grouped: true,
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
                          padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
                          child: Row(
                            children: [
                              if (showIcon) ...[
                                ProxyAvatar(name: group.name, icon: group.icon),
                                const SizedBox(width: 10),
                              ],
                              Expanded(child: _title(context, scheme)),
                              IconButton(
                                tooltip: '搜索节点',
                                visualDensity: VisualDensity.compact,
                                onPressed: onToggleSearch,
                                icon: Icon(
                                  Icons.search_rounded,
                                  size: 20,
                                  color: searchOpen ? scheme.primary : null,
                                ),
                              ),
                              IconButton(
                                tooltip: '定位当前节点',
                                visualDensity: VisualDensity.compact,
                                onPressed: onLocate,
                                icon: const Icon(
                                  Icons.my_location_rounded,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                tooltip: '组内延迟测试',
                                visualDensity: VisualDensity.compact,
                                onPressed: testing ? null : onTest,
                                icon: testing
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.speed_rounded, size: 20),
                              ),
                              TransientAnimatedRotation(
                                turns: expanded ? 0.5 : 0,
                                duration: transitionDuration,
                                curve: Curves.easeInOutCubic,
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
            ),
            if (searchOpen)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  height: searchRowExtent - 6,
                  child: AppSurfaceBackdrop(
                    borderRadius: radius,
                    child: Material(
                      color: surfaceTheme.surfaceColor(
                        scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: radius,
                        side: surfaceTheme.outlineSide(
                          scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: onSearchChanged,
                        textAlignVertical: TextAlignVertical.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          hintText: '搜索组内节点',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          prefixIcon: Icon(Icons.search, size: 18),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context, ColorScheme scheme) {
    return ActiveValueListenableBuilder<String>(
      valueListenable: group.now,
      builder: (_, now, _) {
        final displayNow = group.hidesExactNow
            ? '*'
            : (now.isEmpty ? '-' : now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              group.name,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 0.5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Text(
                    group.type,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    displayNow,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
