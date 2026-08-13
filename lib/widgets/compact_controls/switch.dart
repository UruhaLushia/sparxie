import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../gamepad_navigation.dart';
import '../transient_animation.dart';
import 'style.dart';

const _switchAnimationDuration = Duration(milliseconds: 200);
final _switchThumbShadows = [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.14),
    blurRadius: 2,
    offset: const Offset(0, 1),
  ),
];

class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.style,
  }) : title = null,
       subtitle = null,
       contentPadding = null;

  const CompactSwitch.tile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.contentPadding,
    this.semanticLabel,
    this.style,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  final CompactControlStyle? style;
  final Widget? title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (title != null) return _buildTile(context);
    return _buildSwitch(context);
  }

  Widget _buildSwitch(BuildContext context) {
    final controlStyle = style ?? CompactControlTheme.switchOf(context);
    final enabled = onChanged != null;
    final horizontalInset =
        (controlStyle.switchHeight - controlStyle.switchThumbSize) / 2;
    final visual = _SwitchVisual(
      position: value ? 1 : 0,
      trackColor: value
          ? controlStyle.activeSwitchTrack(context)
          : controlStyle.inactiveSwitchTrack(context),
      outlineColor: value
          ? Colors.transparent
          : controlStyle.switchOutline(context),
      thumbColor: value
          ? controlStyle.activeSwitchThumb(context)
          : controlStyle.inactiveSwitchThumb(context),
      padding: EdgeInsets.all(horizontalInset),
      borderRadius: controlStyle.switchBorderRadius,
      thumbSize: controlStyle.switchThumbSize,
    );
    return AppFocusHighlight(
      borderRadius: controlStyle.switchBorderRadius,
      child: Semantics(
        label: semanticLabel,
        toggled: value,
        enabled: enabled,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.38,
          child: SizedBox(
            width: controlStyle.switchWidth,
            height: controlStyle.switchHeight,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? () => onChanged!(!value) : null,
                borderRadius: controlStyle.switchBorderRadius,
                hoverColor: controlStyle.hover(context),
                splashColor: controlStyle.pressed(context),
                highlightColor: controlStyle.pressed(context),
                child: TransientAnimatedValue<_SwitchVisual>(
                  value: visual,
                  duration: _switchAnimationDuration,
                  curve: Curves.easeOutCubic,
                  lerp: _SwitchVisual.lerp,
                  builder: (_, visual, _) {
                    return Container(
                      padding: visual.padding,
                      decoration: BoxDecoration(
                        color: visual.trackColor,
                        borderRadius: visual.borderRadius,
                        border: Border.all(color: visual.outlineColor),
                      ),
                      child: Align(
                        alignment: Alignment(visual.position * 2 - 1, 0),
                        child: _SwitchThumb(visual: visual),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    const radius = BorderRadius.all(Radius.circular(12));
    return AppFocusHighlight(
      borderRadius: radius,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Padding(
            padding:
                contentPadding ?? const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  Expanded(
                    child: Opacity(
                      opacity: enabled ? 1 : 0.38,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DefaultTextStyle.merge(
                            style: theme.textTheme.bodyLarge,
                            child: title!,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            DefaultTextStyle.merge(
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              child: subtitle!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ExcludeFocus(
                    child: CompactSwitch(
                      value: value,
                      onChanged: onChanged,
                      semanticLabel: semanticLabel,
                      style: style,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchThumb extends StatelessWidget {
  const _SwitchThumb({required this.visual});

  final _SwitchVisual visual;

  @override
  Widget build(BuildContext context) {
    // A moving switch thumb stretches along its path, then returns to a circle
    // at either endpoint. This gives motion feedback without a second ticker.
    final travel = math.sin(visual.position * math.pi).clamp(0.0, 1.0);
    return Transform.scale(
      scaleX: 1 + travel * 0.14,
      child: SizedBox.square(
        dimension: visual.thumbSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: visual.thumbColor,
            shape: BoxShape.circle,
            boxShadow: _switchThumbShadows,
          ),
        ),
      ),
    );
  }
}

@immutable
class _SwitchVisual {
  const _SwitchVisual({
    required this.position,
    required this.trackColor,
    required this.outlineColor,
    required this.thumbColor,
    required this.padding,
    required this.borderRadius,
    required this.thumbSize,
  });

  final double position;
  final Color trackColor;
  final Color outlineColor;
  final Color thumbColor;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final double thumbSize;

  static _SwitchVisual lerp(
    _SwitchVisual begin,
    _SwitchVisual end,
    double progress,
  ) => _SwitchVisual(
    position: begin.position + (end.position - begin.position) * progress,
    trackColor: Color.lerp(begin.trackColor, end.trackColor, progress)!,
    outlineColor: Color.lerp(begin.outlineColor, end.outlineColor, progress)!,
    thumbColor: Color.lerp(begin.thumbColor, end.thumbColor, progress)!,
    padding: EdgeInsets.lerp(begin.padding, end.padding, progress)!,
    borderRadius: BorderRadius.lerp(
      begin.borderRadius,
      end.borderRadius,
      progress,
    )!,
    thumbSize: begin.thumbSize + (end.thumbSize - begin.thumbSize) * progress,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SwitchVisual &&
          position == other.position &&
          trackColor == other.trackColor &&
          outlineColor == other.outlineColor &&
          thumbColor == other.thumbColor &&
          padding == other.padding &&
          borderRadius == other.borderRadius &&
          thumbSize == other.thumbSize;

  @override
  int get hashCode => Object.hash(
    position,
    trackColor,
    outlineColor,
    thumbColor,
    padding,
    borderRadius,
    thumbSize,
  );
}
