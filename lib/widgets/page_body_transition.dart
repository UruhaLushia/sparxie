import 'package:flutter/material.dart';

import 'app_background.dart';
import 'transition_snapshot.dart';

class AppPageTransitionScope extends InheritedWidget {
  const AppPageTransitionScope({
    super.key,
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppPageTransitionScope>()
      ?.animation;

  @override
  bool updateShouldNotify(AppPageTransitionScope oldWidget) =>
      animation != oldWidget.animation;
}

/// Animates page content without moving or fading its surrounding AppBar.
class AppPageBodyTransition extends StatelessWidget {
  const AppPageBodyTransition({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  static const _complete = AlwaysStoppedAnimation<double>(1);

  @override
  Widget build(BuildContext context) {
    final pageAnimation = AppPageTransitionScope.maybeOf(context);
    if (pageAnimation == null) return child;
    final animation = enabled ? pageAnimation : _complete;
    final liveChild = RepaintBoundary(child: child);
    final transitionChild = AppSurfaceTheme.of(context).effectiveBlur > 0
        ? liveChild
        : HighRefreshTransitionSnapshot(animation: animation, child: liveChild);
    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        child: transitionChild,
        builder: (context, child) {
          final progress = animation.value.clamp(0.0, 1.0);
          if (progress >= 0.999) return child!;
          return Transform.scale(
            scale: 1 + 0.012 * (1 - progress),
            alignment: Alignment.center,
            child: child,
          );
        },
      ),
    );
  }
}
