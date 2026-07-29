import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_background.dart';

/// A Material route whose translucent content remains self-contained.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({required super.builder, super.settings})
    : super(allowSnapshotting: false);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (isFirst) return child;
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      AppRouteBackground(child: child),
    );
  }
}

/// A full-width horizontal route transition with Android predictive-back
/// support. The foreground route is the only moving layer, keeping the
/// revealed route stable and avoiding seams between translucent backgrounds.
class AppHorizontalPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppHorizontalPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _AppHorizontalPageTransition(
      route: route,
      animation: animation,
      child: child,
    );
  }
}

class _AppHorizontalPageTransition extends StatefulWidget {
  const _AppHorizontalPageTransition({
    required this.route,
    required this.animation,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_AppHorizontalPageTransition> createState() =>
      _AppHorizontalPageTransitionState();
}

class _AppHorizontalPageTransitionState
    extends State<_AppHorizontalPageTransition>
    with WidgetsBindingObserver {
  static const _maxGesturePreviewDistance = 0.12;

  _BackGesturePhase _gesturePhase = _BackGesturePhase.idle;
  double _settleStartValue = 1;
  double _settleStartDistance = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.animation.addStatusListener(_handleAnimationStatus);
  }

  @override
  void didUpdateWidget(_AppHorizontalPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    oldWidget.animation.removeStatusListener(_handleAnimationStatus);
    widget.animation.addStatusListener(_handleAnimationStatus);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleAnimationStatus);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (_gesturePhase != _BackGesturePhase.cancel ||
        status != AnimationStatus.completed ||
        !mounted) {
      return;
    }
    setState(() => _gesturePhase = _BackGesturePhase.idle);
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final canHandle =
        !backEvent.isButtonEvent &&
        widget.route.isCurrent &&
        widget.route.popGestureEnabled;
    if (!canHandle) return false;

    _gesturePhase = _BackGesturePhase.drag;
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    if (mounted) setState(() {});
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    _beginSettle(_BackGesturePhase.cancel);
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    _beginSettle(_BackGesturePhase.commit);
    widget.route.handleCommitBackGesture();
  }

  void _beginSettle(_BackGesturePhase phase) {
    _settleStartValue = widget.animation.value.clamp(0.0, 1.0);
    _settleStartDistance = _gestureDistance(_settleStartValue);
    if (mounted) setState(() => _gesturePhase = phase);
  }

  double _gestureDistance(double animationValue) =>
      (1 - animationValue) * _maxGesturePreviewDistance;

  double _distanceFor(double value) {
    return switch (_gesturePhase) {
      _BackGesturePhase.drag => _gestureDistance(value),
      _BackGesturePhase.cancel => () {
        final remaining = 1 - _settleStartValue;
        if (remaining <= 0.0001) return 0.0;
        final progress = ((value - _settleStartValue) / remaining).clamp(
          0.0,
          1.0,
        );
        return _settleStartDistance *
            (1 - Curves.easeOutCubic.transform(progress));
      }(),
      _BackGesturePhase.commit => () {
        // A committed predictive back restarts the route controller from 1.0.
        // Keep the drag offset, then use that full-duration animation to leave.
        final progress = (1 - value).clamp(0.0, 1.0);
        return _settleStartDistance +
            (1 - _settleStartDistance) *
                Curves.easeInOutCubic.transform(progress);
      }(),
      _BackGesturePhase.idle => switch (widget.animation.status) {
        AnimationStatus.reverse => Curves.easeOutCubic.transform(1 - value),
        _ => 1 - Curves.easeOutCubic.transform(value),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: widget.animation,
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final value = widget.animation.value.clamp(0.0, 1.0);
          final distance = _distanceFor(value);
          final direction = Directionality.of(context) == TextDirection.ltr
              ? 1.0
              : -1.0;
          if (distance <= 0.0001) return child!;
          return FractionalTranslation(
            translation: Offset(direction * distance, 0),
            child: child,
          );
        },
      ),
    );
  }
}

enum _BackGesturePhase { idle, drag, cancel, commit }
