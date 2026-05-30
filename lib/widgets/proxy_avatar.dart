import 'package:flutter/material.dart';

import 'rust_icon_image.dart';

/// Circular proxy avatar — image when [icon] is non-empty, otherwise a
/// color-tinted letter chip derived from [name].
class ProxyAvatar extends StatelessWidget {
  const ProxyAvatar({super.key, required this.name, this.icon = ''});

  final String name;
  final String icon;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _colorFor(name, scheme);
    final hasIcon = icon.isNotEmpty;
    // Decode with 2x headroom over the display size (capped at the ~256px
    // source) so the downscale has mip levels to resample from. Decoding
    // straight to display res aliases edges in one harsh step (jagged); the
    // cap keeps a huge source from wasting memory.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (_size * dpr * 2).round().clamp(1, 256);
    return SizedBox.square(
      dimension: _size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: hasIcon
            ? Image(
                image: ResizeImage(
                  RustIconImage(icon),
                  width: cachePx,
                  height: cachePx,
                ),
                fit: BoxFit.cover,
                width: _size,
                height: _size,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => _LetterChip(name: name, color: color),
                frameBuilder: (_, child, frame, wasSync) {
                  if (wasSync || frame != null) return child;
                  return _LetterChip(name: name, color: color);
                },
              )
            : _LetterChip(name: name, color: color),
      ),
    );
  }

  static Color _colorFor(String name, ColorScheme scheme) {
    final palette = <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      const Color(0xff10b981),
      const Color(0xfff97316),
      const Color(0xff8b5cf6),
      const Color(0xff0ea5e9),
    ];
    final hash = name.codeUnits.fold<int>(
      0,
      (h, c) => (h * 31 + c) & 0x7fffffff,
    );
    return palette[hash % palette.length];
  }
}

class _LetterChip extends StatelessWidget {
  const _LetterChip({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _letterOf(name),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 15,
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
