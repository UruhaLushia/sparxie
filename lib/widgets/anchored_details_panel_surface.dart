import 'package:flutter/material.dart';

import 'app_background.dart';

class AnchoredDetailsPanelSurface extends StatelessWidget {
  const AnchoredDetailsPanelSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 13, 14, 15),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Material(
        color: surfaceTheme.modalSurfaceColor(scheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          clipBehavior: Clip.none,
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
