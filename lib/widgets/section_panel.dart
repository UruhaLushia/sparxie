import 'package:flutter/material.dart';

import 'app_background.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    const radius = BorderRadius.all(Radius.circular(8));
    return AppSurfaceBackdrop(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: surfaceTheme.surfaceColor(
            colorScheme.surfaceContainerHighest,
            0.06,
          ),
          borderRadius: radius,
          border: surfaceTheme.outlineBorder(colorScheme.outlineVariant),
        ),
        // Transparent Material so nested ListTile splashes don't bleed
        // up to the surrounding Scaffold.
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
