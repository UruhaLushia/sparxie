import 'package:flutter/material.dart';

import 'input_theme.dart';
import 'style.dart';

class CompactSearchField extends StatelessWidget {
  const CompactSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.onClear,
    this.suffixText,
    this.style,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final VoidCallback? onClear;
  final String? suffixText;
  final CompactControlStyle? style;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return _buildField(context, false);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _buildField(context, value.text.isNotEmpty),
    );
  }

  Widget _buildField(BuildContext context, bool hasText) {
    final controlStyle = style ?? CompactControlTheme.searchOf(context);
    final canClear = hasText && onClear != null;
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: compactInputDecorationTheme(
          context,
          controlStyle,
        ),
      ),
      child: SizedBox(
        height: controlStyle.fieldHeight,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            suffixText: suffixText,
            hintText: hintText,
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            suffixIcon: canClear
                ? Semantics(
                    button: true,
                    label: '清除筛选',
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: onClear,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  )
                : null,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
