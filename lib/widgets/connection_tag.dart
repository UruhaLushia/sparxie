import 'package:flutter/material.dart';

/// Variant of the chip-style label used by the connection list.
/// `dot` adds a leading colored dot for the protocol/status chip.
enum ConnectionTagVariant { solid, bordered, dot }

class ConnectionTag extends StatelessWidget {
  const ConnectionTag({
    super.key,
    required this.label,
    this.variant = ConnectionTagVariant.solid,
    this.color,
  });

  final String label;
  final ConnectionTagVariant variant;

  /// Highlight color for `dot` and `bordered` variants. Falls back to the
  /// theme's secondary container.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.secondary;
    return switch (variant) {
      ConnectionTagVariant.solid => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
          ),
        ),
      ConnectionTagVariant.bordered => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      ConnectionTagVariant.dot => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: accent,
                    ),
              ),
            ],
          ),
        ),
    };
  }
}
