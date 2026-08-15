import 'package:flutter/material.dart';

import 'style.dart';

InputDecorationThemeData compactInputDecorationTheme(
  BuildContext context,
  CompactControlStyle style,
) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final iconExtent = style.fieldHeight.clamp(32.0, 44.0);
  OutlineInputBorder border(BorderSide side) => OutlineInputBorder(
    borderRadius: style.borderRadius,
    borderSide: side,
    gapPadding: 3,
  );
  final normalSide = BorderSide(
    color: scheme.outlineVariant.withValues(alpha: 0.52),
  );
  final disabledSide = BorderSide(
    color: scheme.outlineVariant.withValues(alpha: 0.24),
  );
  final focusSide = BorderSide(
    color: style.focus(context).withValues(alpha: 0.72),
  );
  final errorSide = BorderSide(color: scheme.error.withValues(alpha: 0.82));
  final iconColor = WidgetStateColor.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) {
      return scheme.onSurface.withValues(alpha: 0.32);
    }
    if (states.contains(WidgetState.focused)) return style.focus(context);
    return scheme.onSurfaceVariant.withValues(alpha: 0.86);
  });
  return InputDecorationThemeData(
    filled: true,
    fillColor: style.background(context),
    border: border(normalSide),
    enabledBorder: border(normalSide),
    disabledBorder: border(disabledSide),
    focusedBorder: border(focusSide),
    errorBorder: border(errorSide),
    focusedErrorBorder: border(errorSide),
    isDense: true,
    visualDensity: VisualDensity.compact,
    hoverColor: style.hover(context),
    focusColor: style.focus(context).withValues(alpha: 0.08),
    hintFadeDuration: const Duration(milliseconds: 120),
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
    ),
    labelStyle: theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    floatingLabelStyle: theme.textTheme.bodySmall?.copyWith(
      color: style.focus(context),
      fontWeight: FontWeight.w500,
    ),
    prefixIconColor: iconColor,
    suffixIconColor: iconColor,
    prefixIconConstraints: BoxConstraints(
      minWidth: iconExtent,
      minHeight: iconExtent,
    ),
    suffixIconConstraints: BoxConstraints(
      minWidth: iconExtent,
      minHeight: iconExtent,
    ),
    prefixStyle: theme.textTheme.bodyMedium,
    suffixStyle: theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12 * style.widthScale,
      vertical: ((style.fieldHeight - 20) / 2).clamp(6, 16),
    ),
  );
}
