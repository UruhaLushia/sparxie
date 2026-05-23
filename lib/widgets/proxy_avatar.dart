import 'package:flutter/material.dart';

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
    // Decode at display size — most upstream icons are 256+ px, decoding at
    // native res on every cache miss is a measurable hit.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (_size * dpr).round();
    return SizedBox.square(
      dimension: _size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: hasIcon
            ? Image.network(
                icon,
                fit: BoxFit.cover,
                width: _size,
                height: _size,
                cacheWidth: cachePx,
                cacheHeight: cachePx,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => _LetterChip(name: name, color: color),
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : _LetterChip(name: name, color: color),
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
