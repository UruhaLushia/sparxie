import 'package:flutter/material.dart';

import '../../gamepad_navigation.dart';
import 'style.dart';

class CompactSlider extends StatelessWidget {
  const CompactSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.onChangeStart,
    this.onChangeEnd,
    this.style,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final CompactControlStyle? style;

  @override
  Widget build(BuildContext context) {
    final controlStyle = style ?? CompactControlTheme.sliderOf(context);
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final trackHeight = (controlStyle.buttonHeight * 0.08).clamp(2.5, 4.0);
    final thumbRadius = (controlStyle.buttonHeight * 0.18).clamp(6.0, 8.0);
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        activeTrackColor: controlStyle.selectedBackground(context),
        inactiveTrackColor: controlStyle.background(context),
        disabledActiveTrackColor: scheme.onSurface.withValues(alpha: 0.18),
        disabledInactiveTrackColor: scheme.onSurface.withValues(alpha: 0.08),
        thumbColor: controlStyle.selectedBackground(context),
        overlayColor: controlStyle.hover(context),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
        overlayShape: RoundSliderOverlayShape(overlayRadius: thumbRadius + 9),
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
      ),
    );
    final handleChanged = onChanged;
    final control = handleChanged != null
        ? GamepadSliderControl(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: handleChanged,
            onChangeEnd: onChangeEnd,
            child: slider,
          )
        : slider;
    return SizedBox(
      height: controlStyle.buttonHeight,
      child: Opacity(opacity: enabled ? 1 : 0.38, child: control),
    );
  }
}
