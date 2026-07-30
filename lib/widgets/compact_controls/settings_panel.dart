import 'package:flutter/material.dart';

import '../app_background.dart';
import '../section_panel.dart';

class CompactSettingsPanel extends StatelessWidget {
  const CompactSettingsPanel({
    super.key,
    required this.header,
    required this.child,
    this.expandBody = false,
    this.borderRadius = kAppPanelRadius,
    this.surfaceTheme,
    this.backgroundColor,
    this.surfaceLift = 0.05,
  });

  final Widget header;
  final Widget child;
  final bool expandBody;
  final BorderRadiusGeometry borderRadius;
  final AppSurfaceTheme? surfaceTheme;
  final Color? backgroundColor;
  final double surfaceLift;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveSurfaceTheme = surfaceTheme ?? AppSurfaceTheme.of(context);
    final outline = Border.all(
      color: scheme.outlineVariant.withValues(alpha: 0.72),
    );
    final content = Column(
      mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header,
        if (expandBody) Expanded(child: child) else child,
      ],
    );

    return AppSurfaceBackdrop(
      borderRadius: borderRadius,
      surfaceTheme: effectiveSurfaceTheme,
      child: Container(
        decoration: BoxDecoration(
          color: effectiveSurfaceTheme.surfaceColor(
            backgroundColor ?? scheme.surfaceContainerLow,
            surfaceLift,
          ),
          borderRadius: borderRadius,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: borderRadius,
          border: outline,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(borderRadius: borderRadius, child: content),
        ),
      ),
    );
  }
}

class CompactSettingsPanelHeader extends StatelessWidget {
  const CompactSettingsPanelHeader({
    super.key,
    required this.title,
    required this.icon,
    this.height = 62,
    this.enabled = true,
    this.elevation = 0,
    this.backgroundColor,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final double height;
  final bool enabled;
  final double elevation;
  final Color? backgroundColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final color =
        backgroundColor ??
        Color.alphaBlend(
          scheme.primary.withValues(alpha: surfaceTheme.enabled ? 0.14 : 0.08),
          scheme.surfaceContainerHigh.withValues(alpha: 1),
        );
    final progress = elevation.clamp(0.0, 1.0);

    return SizedBox(
      height: height,
      child: ColoredBox(
        color: color,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: surfaceTheme.outlineColor(
                  scheme.outlineVariant.withValues(
                    alpha: 0.38 + 0.32 * progress,
                  ),
                ),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.08 * progress),
                blurRadius: 8 * progress,
                offset: Offset(0, 2 * progress),
              ),
            ],
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
