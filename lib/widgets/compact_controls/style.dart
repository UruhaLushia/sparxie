import 'package:flutter/material.dart';

import '../../app_prefs.dart';

BorderRadius _indicatorRadius(
  double outerRadius,
  double inset,
  double? configuredRadius,
) {
  final radius =
      configuredRadius ??
      (outerRadius - inset).clamp(0.0, outerRadius).toDouble();
  return BorderRadius.all(Radius.circular(radius));
}

Color _contrastingForeground(Color background) =>
    background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

double _contrastRatio(Color foreground, Color background) {
  final visibleForeground = Color.alphaBlend(foreground, background);
  final foregroundLuminance = visibleForeground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _readableForeground(Color preferred, Color background) =>
    _contrastRatio(preferred, background) >= 4.5
    ? preferred
    : _contrastingForeground(background);

@immutable
class CompactControlStyle {
  const CompactControlStyle({
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.foregroundColor,
    this.selectedForegroundColor,
    this.hoverColor,
    this.pressedColor,
    this.focusColor,
    this.switchActiveTrackColor,
    this.switchInactiveTrackColor,
    this.switchActiveThumbColor,
    this.switchInactiveThumbColor,
    this.switchOutlineColor,
    this.textStyle,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.indicatorBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.fieldHeight = 40,
    this.buttonHeight = 40,
    this.indicatorHeight = 32,
    this.switchWidth = 44,
    this.switchHeight = 24,
    this.switchThumbSize = 18,
    this.switchBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.segmentInset = 3,
    this.widthScale = 1,
    this.indicatorWidthScale = 1,
    this.floatingHeightOffset = 0,
  });

  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final Color? foregroundColor;
  final Color? selectedForegroundColor;
  final Color? hoverColor;
  final Color? pressedColor;
  final Color? focusColor;
  final Color? switchActiveTrackColor;
  final Color? switchInactiveTrackColor;
  final Color? switchActiveThumbColor;
  final Color? switchInactiveThumbColor;
  final Color? switchOutlineColor;
  final TextStyle? textStyle;
  final BorderRadius borderRadius;
  final BorderRadius indicatorBorderRadius;
  final double fieldHeight;
  final double buttonHeight;
  final double indicatorHeight;
  final double switchWidth;
  final double switchHeight;
  final double switchThumbSize;
  final BorderRadius switchBorderRadius;
  final double segmentInset;
  final double widthScale;
  final double indicatorWidthScale;
  final double floatingHeightOffset;

  factory CompactControlStyle.fromSeed({
    required Color seedColor,
    required Brightness brightness,
    required double borderRadius,
    required double controlHeight,
    required double widthScale,
    Color? selectedSeedColor,
    double? indicatorBorderRadius,
    double? indicatorHeight,
    double? indicatorWidthScale,
    double floatingHeightOffset = 0,
  }) {
    final dark = brightness == Brightness.dark;
    final effectiveSelectedSeed = selectedSeedColor ?? seedColor;
    final neutral = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    final onSeed = _contrastingForeground(effectiveSelectedSeed);
    final background = dark
        ? Color.alphaBlend(
            seedColor.withValues(alpha: 0.1),
            neutral.surfaceContainerHigh,
          )
        : Color.alphaBlend(
            seedColor.withValues(alpha: 0.07),
            const Color(0xfff7fafc),
          );
    final radius = BorderRadius.all(Radius.circular(borderRadius));
    final switchHeight = (controlHeight * 0.6).clamp(20.0, 28.0);
    final segmentInset = (controlHeight * 0.075).clamp(2.0, 4.0);
    return CompactControlStyle(
      backgroundColor: background,
      selectedBackgroundColor: effectiveSelectedSeed,
      foregroundColor: neutral.onSurface,
      selectedForegroundColor: onSeed,
      hoverColor: seedColor.withValues(alpha: dark ? 0.12 : 0.08),
      pressedColor: seedColor.withValues(alpha: dark ? 0.18 : 0.12),
      // `primary` preserves the seed's hue while selecting a tone that stays
      // legible on this brightness's surfaces.
      focusColor: neutral.primary,
      switchActiveTrackColor: effectiveSelectedSeed,
      switchActiveThumbColor: onSeed,
      switchInactiveTrackColor: background,
      switchInactiveThumbColor: neutral.surface,
      switchOutlineColor: seedColor.withValues(alpha: 0.55),
      borderRadius: radius,
      indicatorBorderRadius: _indicatorRadius(
        borderRadius,
        segmentInset,
        indicatorBorderRadius,
      ),
      fieldHeight: controlHeight,
      buttonHeight: controlHeight,
      indicatorHeight: indicatorHeight ?? controlHeight,
      switchWidth: switchHeight * 1.84 * widthScale,
      switchHeight: switchHeight,
      switchThumbSize: switchHeight - 6,
      switchBorderRadius: radius,
      segmentInset: segmentInset,
      widthScale: widthScale,
      indicatorWidthScale: indicatorWidthScale ?? widthScale,
      floatingHeightOffset: floatingHeightOffset,
    );
  }

  factory CompactControlStyle.fromColorScheme({
    required ColorScheme colorScheme,
    required double borderRadius,
    required double controlHeight,
    required double widthScale,
    double? indicatorBorderRadius,
    double? indicatorHeight,
    double? indicatorWidthScale,
    double floatingHeightOffset = 0,
  }) {
    final radius = BorderRadius.all(Radius.circular(borderRadius));
    final switchHeight = (controlHeight * 0.6).clamp(20.0, 28.0);
    final segmentInset = (controlHeight * 0.075).clamp(2.0, 4.0);
    return CompactControlStyle(
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedBackgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onSurface,
      selectedForegroundColor: colorScheme.onPrimaryContainer,
      focusColor: colorScheme.primary,
      switchActiveTrackColor: colorScheme.primary,
      switchActiveThumbColor: colorScheme.onPrimary,
      switchInactiveTrackColor: colorScheme.surfaceContainerHighest,
      switchInactiveThumbColor: colorScheme.surface,
      switchOutlineColor: colorScheme.outlineVariant,
      borderRadius: radius,
      indicatorBorderRadius: _indicatorRadius(
        borderRadius,
        segmentInset,
        indicatorBorderRadius,
      ),
      fieldHeight: controlHeight,
      buttonHeight: controlHeight,
      indicatorHeight: indicatorHeight ?? controlHeight,
      switchWidth: switchHeight * 1.84 * widthScale,
      switchHeight: switchHeight,
      switchThumbSize: switchHeight - 6,
      switchBorderRadius: radius,
      segmentInset: segmentInset,
      widthScale: widthScale,
      indicatorWidthScale: indicatorWidthScale ?? widthScale,
      floatingHeightOffset: floatingHeightOffset,
    );
  }

  Color background(BuildContext context) =>
      backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHigh;

  Color selectedBackground(BuildContext context) =>
      selectedBackgroundColor ?? Theme.of(context).colorScheme.primaryContainer;

  Color foreground(BuildContext context) =>
      foregroundColor ?? Theme.of(context).colorScheme.onSurface;

  Color selectedForeground(BuildContext context) {
    final theme = Theme.of(context);
    final preferred =
        selectedForegroundColor ?? theme.colorScheme.onPrimaryContainer;
    final controlBackground = Color.alphaBlend(
      background(context),
      theme.colorScheme.surface.withValues(alpha: 1),
    );
    final effectiveSelectedBackground = Color.alphaBlend(
      selectedBackground(context),
      controlBackground,
    );
    return _readableForeground(preferred, effectiveSelectedBackground);
  }

  Color hover(BuildContext context) =>
      hoverColor ??
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04);

  Color pressed(BuildContext context) =>
      pressedColor ??
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06);

  Color focus(BuildContext context) =>
      focusColor ?? Theme.of(context).colorScheme.primary;

  Color activeSwitchTrack(BuildContext context) =>
      switchActiveTrackColor ?? Theme.of(context).colorScheme.primary;

  Color inactiveSwitchTrack(BuildContext context) =>
      switchInactiveTrackColor ??
      Theme.of(context).colorScheme.surfaceContainerHighest;

  Color activeSwitchThumb(BuildContext context) =>
      switchActiveThumbColor ?? Theme.of(context).colorScheme.onPrimary;

  Color inactiveSwitchThumb(BuildContext context) =>
      switchInactiveThumbColor ?? Theme.of(context).colorScheme.surface;

  Color switchOutline(BuildContext context) =>
      switchOutlineColor ?? Theme.of(context).colorScheme.outlineVariant;

  TextStyle? labelStyle(BuildContext context) =>
      textStyle ?? Theme.of(context).textTheme.labelMedium;

  CompactControlStyle withSurfaceOpacity(double opacity) {
    Color? fade(Color? color, [double lift = 0]) =>
        color?.withValues(alpha: (opacity + lift).clamp(0.05, 1.0).toDouble());

    return copyWith(
      backgroundColor: fade(backgroundColor),
      selectedBackgroundColor: fade(selectedBackgroundColor, 0.08),
      switchActiveTrackColor: fade(switchActiveTrackColor, 0.08),
      switchInactiveTrackColor: fade(switchInactiveTrackColor),
    );
  }

  CompactControlStyle copyWith({
    Color? backgroundColor,
    Color? selectedBackgroundColor,
    Color? foregroundColor,
    Color? selectedForegroundColor,
    Color? hoverColor,
    Color? pressedColor,
    Color? focusColor,
    Color? switchActiveTrackColor,
    Color? switchInactiveTrackColor,
    Color? switchActiveThumbColor,
    Color? switchInactiveThumbColor,
    Color? switchOutlineColor,
    TextStyle? textStyle,
    BorderRadius? borderRadius,
    BorderRadius? indicatorBorderRadius,
    double? fieldHeight,
    double? buttonHeight,
    double? indicatorHeight,
    double? switchWidth,
    double? switchHeight,
    double? switchThumbSize,
    BorderRadius? switchBorderRadius,
    double? segmentInset,
    double? widthScale,
    double? indicatorWidthScale,
    double? floatingHeightOffset,
  }) => CompactControlStyle(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    selectedBackgroundColor:
        selectedBackgroundColor ?? this.selectedBackgroundColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    selectedForegroundColor:
        selectedForegroundColor ?? this.selectedForegroundColor,
    hoverColor: hoverColor ?? this.hoverColor,
    pressedColor: pressedColor ?? this.pressedColor,
    focusColor: focusColor ?? this.focusColor,
    switchActiveTrackColor:
        switchActiveTrackColor ?? this.switchActiveTrackColor,
    switchInactiveTrackColor:
        switchInactiveTrackColor ?? this.switchInactiveTrackColor,
    switchActiveThumbColor:
        switchActiveThumbColor ?? this.switchActiveThumbColor,
    switchInactiveThumbColor:
        switchInactiveThumbColor ?? this.switchInactiveThumbColor,
    switchOutlineColor: switchOutlineColor ?? this.switchOutlineColor,
    textStyle: textStyle ?? this.textStyle,
    borderRadius: borderRadius ?? this.borderRadius,
    indicatorBorderRadius: indicatorBorderRadius ?? this.indicatorBorderRadius,
    fieldHeight: fieldHeight ?? this.fieldHeight,
    buttonHeight: buttonHeight ?? this.buttonHeight,
    indicatorHeight: indicatorHeight ?? this.indicatorHeight,
    switchWidth: switchWidth ?? this.switchWidth,
    switchHeight: switchHeight ?? this.switchHeight,
    switchThumbSize: switchThumbSize ?? this.switchThumbSize,
    switchBorderRadius: switchBorderRadius ?? this.switchBorderRadius,
    segmentInset: segmentInset ?? this.segmentInset,
    widthScale: widthScale ?? this.widthScale,
    indicatorWidthScale: indicatorWidthScale ?? this.indicatorWidthScale,
    floatingHeightOffset: floatingHeightOffset ?? this.floatingHeightOffset,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompactControlStyle &&
          backgroundColor == other.backgroundColor &&
          selectedBackgroundColor == other.selectedBackgroundColor &&
          foregroundColor == other.foregroundColor &&
          selectedForegroundColor == other.selectedForegroundColor &&
          hoverColor == other.hoverColor &&
          pressedColor == other.pressedColor &&
          focusColor == other.focusColor &&
          switchActiveTrackColor == other.switchActiveTrackColor &&
          switchInactiveTrackColor == other.switchInactiveTrackColor &&
          switchActiveThumbColor == other.switchActiveThumbColor &&
          switchInactiveThumbColor == other.switchInactiveThumbColor &&
          switchOutlineColor == other.switchOutlineColor &&
          textStyle == other.textStyle &&
          borderRadius == other.borderRadius &&
          indicatorBorderRadius == other.indicatorBorderRadius &&
          fieldHeight == other.fieldHeight &&
          buttonHeight == other.buttonHeight &&
          indicatorHeight == other.indicatorHeight &&
          switchWidth == other.switchWidth &&
          switchHeight == other.switchHeight &&
          switchThumbSize == other.switchThumbSize &&
          switchBorderRadius == other.switchBorderRadius &&
          segmentInset == other.segmentInset &&
          widthScale == other.widthScale &&
          indicatorWidthScale == other.indicatorWidthScale &&
          floatingHeightOffset == other.floatingHeightOffset;

  @override
  int get hashCode => Object.hashAll([
    backgroundColor,
    selectedBackgroundColor,
    foregroundColor,
    selectedForegroundColor,
    hoverColor,
    pressedColor,
    focusColor,
    switchActiveTrackColor,
    switchInactiveTrackColor,
    switchActiveThumbColor,
    switchInactiveThumbColor,
    switchOutlineColor,
    textStyle,
    borderRadius,
    indicatorBorderRadius,
    fieldHeight,
    buttonHeight,
    indicatorHeight,
    switchWidth,
    switchHeight,
    switchThumbSize,
    switchBorderRadius,
    segmentInset,
    widthScale,
    indicatorWidthScale,
    floatingHeightOffset,
  ]);
}

class CompactControlTheme extends InheritedTheme {
  const CompactControlTheme({
    super.key,
    required this.styles,
    required super.child,
  });

  final Map<CompactControlKind, CompactControlStyle> styles;

  static CompactControlTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompactControlTheme>();

  static CompactControlStyle _styleOf(
    BuildContext context,
    CompactControlKind kind, [
    CompactControlStyle fallback = const CompactControlStyle(),
  ]) => maybeOf(context)?.styles[kind] ?? fallback;

  static CompactControlStyle buttonOf(BuildContext context) =>
      _styleOf(context, CompactControlKind.button);

  static CompactControlStyle searchOf(BuildContext context) =>
      _styleOf(context, CompactControlKind.search);

  static CompactControlStyle textFieldOf(BuildContext context) =>
      _styleOf(context, CompactControlKind.textField);

  static CompactControlStyle segmentedOf(BuildContext context) =>
      _styleOf(context, CompactControlKind.segmented);

  static CompactControlStyle switchOf(BuildContext context) =>
      _styleOf(context, CompactControlKind.toggle);

  static CompactControlStyle sliderOf(BuildContext context) =>
      _styleOf(context, CompactControlKind.slider);

  static CompactControlStyle navigationBarOf(BuildContext context) => _styleOf(
    context,
    CompactControlKind.navigationBar,
    const CompactControlStyle(
      buttonHeight: 56,
      indicatorHeight: 42,
      borderRadius: BorderRadius.all(Radius.circular(28)),
      indicatorBorderRadius: BorderRadius.all(Radius.circular(21)),
    ),
  );

  @override
  bool updateShouldNotify(CompactControlTheme oldWidget) =>
      !identical(styles, oldWidget.styles);

  @override
  Widget wrap(BuildContext context, Widget child) =>
      CompactControlTheme(styles: styles, child: child);
}
