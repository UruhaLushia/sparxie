import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_background.dart';
import 'transition_snapshot.dart';

/// A Material route whose translucent content remains self-contained.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({required super.builder, super.settings})
    : super(allowSnapshotting: false);

  @override
  void handleCommitBackGesture() {
    // TransitionRoute restarts at 1.0 on commit. This route already maps the
    // gesture into its preview range, so pop from the current value instead.
    final navigation = navigator;
    if (isCurrent) navigation?.pop();

    final routeController = controller;
    if (routeController?.isAnimating ?? false) {
      late final AnimationStatusListener stopGesture;
      stopGesture = (_) {
        routeController!.removeStatusListener(stopGesture);
        navigation?.didStopUserGesture();
      };
      routeController!.addStatusListener(stopGesture);
    } else {
      navigation?.didStopUserGesture();
    }
  }

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
  static const _maxGesturePreviewDistance = 0.25;

  _BackGesturePhase _gesturePhase = _BackGesturePhase.idle;
  double _settleStartValue = 1;
  double _settleStartDistance = 0;

  bool get _usesContinuousCommit => widget.route is AppPageRoute<dynamic>;

  double _backAnimationValue(PredictiveBackEvent event) {
    final progress = _usesContinuousCommit
        ? event.progress * _maxGesturePreviewDistance
        : event.progress;
    return 1 - progress;
  }

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
    widget.route.handleStartBackGesture(
      progress: _backAnimationValue(backEvent),
    );
    if (mounted) setState(() {});
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    widget.route.handleUpdateBackGestureProgress(
      progress: _backAnimationValue(backEvent),
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

  double _gestureDistance(double animationValue) {
    final progress = 1 - animationValue;
    return _usesContinuousCommit
        ? progress
        : progress * _maxGesturePreviewDistance;
  }

  double _cancelDistance(double value) {
    final remaining = 1 - _settleStartValue;
    if (remaining <= 0.0001) return 0.0;
    final progress = ((value - _settleStartValue) / remaining).clamp(0.0, 1.0);
    return _settleStartDistance * (1 - Curves.easeOutCubic.transform(progress));
  }

  double _commitDistance(double value) {
    if (_usesContinuousCommit) {
      if (_settleStartValue <= 0.0001) return 1.0;
      final progress = ((_settleStartValue - value) / _settleStartValue).clamp(
        0.0,
        1.0,
      );
      return _settleStartDistance +
          (1 - _settleStartDistance) *
              Curves.linearToEaseOut.transform(progress);
    }

    // Other PageRoute implementations retain Flutter's reset-on-commit
    // behavior, so keep the visual offset continuous for that fallback.
    final progress = (1 - value).clamp(0.0, 1.0);
    final remaining = 1 - _settleStartDistance;
    if (remaining <= 0.0001) return 1.0;
    final settleProgress = (progress / remaining).clamp(0.0, 1.0);
    return _settleStartDistance +
        remaining * Curves.linearToEaseOut.transform(settleProgress);
  }

  double _distanceFor(double value) {
    return switch (_gesturePhase) {
      _BackGesturePhase.drag => _gestureDistance(value),
      _BackGesturePhase.cancel => _cancelDistance(value),
      _BackGesturePhase.commit => _commitDistance(value),
      _BackGesturePhase.idle => switch (widget.animation.status) {
        AnimationStatus.reverse => Curves.easeOutCubic.transform(1 - value),
        _ => 1 - Curves.easeOutCubic.transform(value),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context) == TextDirection.ltr
        ? 1.0
        : -1.0;
    return ClipRect(
      child: AnimatedBuilder(
        animation: widget.animation,
        child: HighRefreshTransitionSnapshot(
          animation: widget.animation,
          forceSnapshot: _gesturePhase != _BackGesturePhase.idle,
          child: RepaintBoundary(child: widget.child),
        ),
        builder: (context, child) {
          final value = widget.animation.value.clamp(0.0, 1.0);
          final distance = _distanceFor(value);
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
