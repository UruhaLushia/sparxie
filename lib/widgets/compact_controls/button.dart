import 'package:flutter/material.dart';

import '../../gamepad_navigation.dart';
import 'style.dart';

class CompactMenuButton<T> extends StatelessWidget {
  const CompactMenuButton({
    super.key,
    required this.value,
    required this.label,
    required this.semanticLabel,
    required this.itemBuilder,
    required this.onSelected,
    this.enabled = true,
    this.width,
    this.height,
    this.style,
  });

  final T value;
  final String label;
  final String semanticLabel;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final bool enabled;
  final double? width;
  final double? height;
  final CompactControlStyle? style;

  @override
  Widget build(BuildContext context) {
    final controlStyle = style ?? CompactControlTheme.buttonOf(context);
    final resolvedHeight = height ?? controlStyle.buttonHeight;
    final theme = Theme.of(context);
    final content = Semantics(
      button: true,
      label: semanticLabel,
      child: Theme(
        data: theme.copyWith(
          hoverColor: controlStyle.hover(context),
          splashColor: controlStyle.pressed(context),
        ),
        child: PopupMenuButton<T>(
          enabled: enabled,
          initialValue: value,
          tooltip: '',
          position: PopupMenuPosition.under,
          padding: EdgeInsets.zero,
          borderRadius: controlStyle.borderRadius,
          onSelected: onSelected,
          itemBuilder: itemBuilder,
          child: Opacity(
            opacity: enabled ? 1 : 0.38,
            child: Container(
              height: resolvedHeight,
              padding: EdgeInsets.only(
                left: 10 * controlStyle.widthScale,
                right: 8 * controlStyle.widthScale,
              ),
              decoration: BoxDecoration(
                color: controlStyle.background(context),
                borderRadius: controlStyle.borderRadius,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: controlStyle.labelStyle(context),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return AppFocusHighlight(
      borderRadius: controlStyle.borderRadius,
      child: SizedBox(width: width, height: resolvedHeight, child: content),
    );
  }
}

class CompactIconButton extends StatelessWidget {
  const CompactIconButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    this.style,
  });

  final String semanticLabel;
  final Widget icon;
  final VoidCallback? onPressed;
  final CompactControlStyle? style;

  @override
  Widget build(BuildContext context) {
    final controlStyle = style ?? CompactControlTheme.buttonOf(context);
    return AppFocusHighlight(
      borderRadius: controlStyle.borderRadius,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: SizedBox(
          width: controlStyle.buttonHeight * controlStyle.widthScale,
          height: controlStyle.buttonHeight,
          child: IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tightFor(
              width: controlStyle.buttonHeight * controlStyle.widthScale,
              height: controlStyle.buttonHeight,
            ),
            onPressed: onPressed,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: controlStyle.background(context),
              hoverColor: controlStyle.hover(context),
              highlightColor: controlStyle.pressed(context),
              shape: RoundedRectangleBorder(
                borderRadius: controlStyle.borderRadius,
              ),
            ),
            icon: icon,
          ),
        ),
      ),
    );
  }
}
