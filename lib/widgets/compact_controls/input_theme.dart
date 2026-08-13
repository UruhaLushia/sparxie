import 'package:flutter/material.dart';

import 'style.dart';

InputDecorationThemeData compactInputDecorationTheme(
  BuildContext context,
  CompactControlStyle style,
) {
  final border = OutlineInputBorder(
    borderRadius: style.borderRadius,
    borderSide: BorderSide.none,
  );
  return InputDecorationThemeData(
    filled: true,
    fillColor: style.background(context),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: style.borderRadius,
      borderSide: BorderSide(color: style.focus(context), width: 1.5),
    ),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12 * style.widthScale,
      vertical: ((style.fieldHeight - 20) / 2).clamp(6, 16),
    ),
  );
}
