import 'package:flutter/material.dart';

import 'style.dart';
import 'text_field.dart';

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
    final clear = onClear;
    return CompactTextField(
      controller: controller,
      style: style,
      decoration: InputDecoration(
        suffixText: suffixText,
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: controller != null && clear != null
            ? _SearchClearButton(controller: controller, onPressed: clear)
            : null,
      ),
      onChanged: onChanged,
    );
  }
}

class _SearchClearButton extends StatelessWidget {
  const _SearchClearButton({required this.controller, required this.onPressed});

  final TextEditingController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: value.text.isEmpty
            ? const SizedBox(key: ValueKey(false), width: 32, height: 32)
            : Semantics(
                key: const ValueKey(true),
                button: true,
                label: '清除筛选',
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: onPressed,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
      ),
    );
  }
}
