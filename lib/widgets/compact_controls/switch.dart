import 'package:flutter/material.dart';

import 'style.dart';

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
    return Semantics(
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.all(horizontalInset),
                decoration: BoxDecoration(
                  color: value
                      ? controlStyle.activeSwitchTrack(context)
                      : controlStyle.inactiveSwitchTrack(context),
                  borderRadius: controlStyle.switchBorderRadius,
                  border: Border.all(
                    color: value
                        ? Colors.transparent
                        : controlStyle.switchOutline(context),
                  ),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: controlStyle.switchThumbSize,
                    height: controlStyle.switchThumbSize,
                    decoration: BoxDecoration(
                      color: value
                          ? controlStyle.activeSwitchThumb(context)
                          : controlStyle.inactiveSwitchThumb(context),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 16),
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
              CompactSwitch(
                value: value,
                onChanged: onChanged,
                semanticLabel: semanticLabel,
                style: style,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
