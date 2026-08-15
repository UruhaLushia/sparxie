import 'package:flutter/material.dart';

import 'input_theme.dart';
import 'style.dart';

class CompactTextField extends StatelessWidget {
  const CompactTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.style,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final CompactControlStyle? style;

  @override
  Widget build(BuildContext context) {
    final controlStyle = style ?? CompactControlTheme.textFieldOf(context);
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: compactInputDecorationTheme(
          context,
          controlStyle,
        ),
      ),
      child: SizedBox(
        height: controlStyle.fieldHeight,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: decoration,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofocus: autofocus,
          enabled: enabled,
          readOnly: readOnly,
          obscureText: obscureText,
          textAlignVertical: TextAlignVertical.center,
          style: controlStyle.textStyle ?? theme.textTheme.bodyMedium,
          cursorColor: controlStyle.focus(context),
          cursorHeight: (controlStyle.fieldHeight * 0.46).clamp(16, 21),
        ),
      ),
    );
  }
}
