import 'package:flutter/material.dart';

import 'rust_icon_image.dart';

class NamedAvatar extends StatelessWidget {
  const NamedAvatar({
    super.key,
    required this.name,
    this.icon = '',
    this.size = 44,
    this.fallback,
    this.decodeScale = 1.25,
  });

  final String name;
  final String icon;
  final double size;
  final Widget? fallback;
  final double decodeScale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _colorFor(name, scheme);
    final radius = BorderRadius.circular(10);
    final fallbackWidget = fallback ?? _LetterChip(name: name, color: color);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr * decodeScale).ceil().clamp(1, 160);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: radius,
        child: icon.isEmpty
            ? fallbackWidget
            : Image(
                image: ResizeImage(
                  RustIconImage(icon),
                  width: cachePx,
                  height: cachePx,
                ),
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => fallbackWidget,
                frameBuilder: (_, child, frame, wasSync) {
                  if (wasSync || frame != null) return child;
                  return fallbackWidget;
                },
              ),
      ),
    );
  }

  static Color _colorFor(String name, ColorScheme scheme) {
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.codeUnitAt(i)) & 0x7fffffff;
    }
    return switch (hash % 8) {
      0 => scheme.primary,
      1 => scheme.tertiary,
      2 => scheme.secondary,
      3 => scheme.error,
      4 => const Color(0xff10b981),
      5 => const Color(0xfff97316),
      6 => const Color(0xff8b5cf6),
      _ => const Color(0xff0ea5e9),
    };
  }
}

class _LetterChip extends StatelessWidget {
  const _LetterChip({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Center(
        child: Text(
          _letterOf(name),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  static String _letterOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }
}
