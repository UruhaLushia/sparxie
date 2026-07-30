import 'package:flutter/material.dart';

import 'app_background.dart';

const kAppPanelRadius = BorderRadius.all(Radius.circular(16));

class AppPanelSurface extends StatelessWidget {
  const AppPanelSurface({
    super.key,
    required this.child,
    this.outlined = true,
    this.selected = false,
  });

  final Widget child;
  final bool outlined;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return AppSurfaceBackdrop(
      borderRadius: kAppPanelRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceTheme.surfaceColor(
            selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
            selected ? 0.08 : 0.05,
          ),
          borderRadius: kAppPanelRadius,
          // Translucent panels need a hairline over image backgrounds.
          border: outlined
              ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6))
              : null,
        ),
        child: ClipRRect(
          borderRadius: kAppPanelRadius,
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}

class MaxWidthContent extends StatelessWidget {
  const MaxWidthContent({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class PanelIconChip extends StatelessWidget {
  const PanelIconChip({super.key, required this.icon, this.active = false});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? scheme.primary : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: 20,
        color: active ? scheme.onPrimary : scheme.onPrimaryContainer,
      ),
    );
  }
}

/// Shared "section panel" used across settings, basic config, etc.
/// Outlined surface with title row + body.
class SectionPanel extends StatelessWidget {
  const SectionPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanelSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
