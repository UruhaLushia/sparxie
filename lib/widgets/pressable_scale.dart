import 'package:flutter/material.dart';

import 'transient_animation.dart';

/// Scale-down on press for a "physical button" feel. Independent of
/// `InkWell.onTap`, which still fires for the actual tap and ripple.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.holdPressed = false,
  });

  static const double pressedScale = 0.97;

  final Widget child;

  /// Keeps the visual press after pointer-up until another animation takes over.
  final bool holdPressed;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (!_down) setState(() => _down = true);
      },
      onPointerUp: (_) {
        if (_down) setState(() => _down = false);
      },
      onPointerCancel: (_) {
        if (_down) setState(() => _down = false);
      },
      child: TransientAnimatedScale(
        scale: _down || widget.holdPressed ? PressableScale.pressedScale : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
