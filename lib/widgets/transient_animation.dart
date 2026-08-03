import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef TransientValueLerp<T> = T Function(T begin, T end, double progress);
typedef TransientValueBuilder<T> =
    Widget Function(BuildContext context, T value, Widget? child);

/// An implicit animation whose controller exists only while the value changes.
class TransientAnimatedValue<T> extends StatefulWidget {
  const TransientAnimatedValue({
    super.key,
    required this.value,
    required this.duration,
    required this.lerp,
    required this.builder,
    this.curve = Curves.linear,
    this.child,
  });

  final T value;
  final Duration duration;
  final Curve curve;
  final TransientValueLerp<T> lerp;
  final TransientValueBuilder<T> builder;
  final Widget? child;

  @override
  State<TransientAnimatedValue<T>> createState() =>
      _TransientAnimatedValueState<T>();
}

class _TransientAnimatedValueState<T> extends State<TransientAnimatedValue<T>>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  late T _settledValue = widget.value;
  late T _beginValue = widget.value;
  late T _targetValue = widget.value;
  late Curve _activeCurve = widget.curve;
  var _tickerEnabled = true;
  var _generation = 0;

  T get _currentValue {
    final controller = _controller;
    if (controller == null) return _settledValue;
    return widget.lerp(
      _beginValue,
      _targetValue,
      _activeCurve.transform(controller.value),
    );
  }

  @override
  void didUpdateWidget(TransientAnimatedValue<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller?.duration = widget.duration;
    if (oldWidget.value != widget.value ||
        (_controller != null &&
            oldWidget.duration != Duration.zero &&
            widget.duration == Duration.zero)) {
      _animateTo(widget.value);
    } else if (oldWidget.curve != widget.curve) {
      _activeCurve = widget.curve;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (!_tickerEnabled && _controller != null) {
      _settle(_targetValue);
    }
  }

  void _settle(T value) {
    _generation++;
    final controller = _controller;
    _controller = null;
    _settledValue = value;
    _beginValue = value;
    _targetValue = value;
    controller?.dispose();
  }

  void _animateTo(T target) {
    if (!_tickerEnabled) {
      _settle(target);
      return;
    }
    final current = _currentValue;
    _settledValue = current;
    if (current == target || widget.duration == Duration.zero) {
      _settle(target);
      return;
    }

    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    controller.duration = widget.duration;
    _beginValue = current;
    _targetValue = target;
    _activeCurve = widget.curve;
    final generation = ++_generation;
    controller.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted ||
          generation != _generation ||
          !identical(_controller, controller) ||
          !controller.isCompleted) {
        return;
      }
      setState(() {
        _settledValue = _targetValue;
        _beginValue = _targetValue;
        _controller = null;
      });
      controller.dispose();
    });
  }

  @override
  void dispose() {
    _generation++;
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnimatedBuilder(
      animation: controller ?? const AlwaysStoppedAnimation<double>(1),
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, _currentValue, child),
    );
  }
}

class TransientAnimatedScale extends StatelessWidget {
  const TransientAnimatedScale({
    super.key,
    required this.scale,
    required this.duration,
    required this.child,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    this.filterQuality,
    this.transformHitTests = true,
  }) : assert(scale >= 0);

  final double scale;
  final Duration duration;
  final Curve curve;
  final Alignment alignment;
  final FilterQuality? filterQuality;
  final bool transformHitTests;
  final Widget child;

  static double _lerp(double begin, double end, double progress) =>
      begin + (end - begin) * progress;

  @override
  Widget build(BuildContext context) {
    return TransientAnimatedValue<double>(
      value: scale,
      duration: duration,
      curve: curve,
      lerp: _lerp,
      child: child,
      builder: (_, value, child) => Transform.scale(
        scale: value,
        alignment: alignment,
        filterQuality: filterQuality,
        transformHitTests: transformHitTests,
        child: child,
      ),
    );
  }
}

class TransientAnimatedSlide extends StatelessWidget {
  const TransientAnimatedSlide({
    super.key,
    required this.offset,
    required this.duration,
    required this.child,
    this.curve = Curves.linear,
    this.transformHitTests = true,
  });

  final Offset offset;
  final Duration duration;
  final Curve curve;
  final bool transformHitTests;
  final Widget child;

  static Offset _lerp(Offset begin, Offset end, double progress) =>
      Offset.lerp(begin, end, progress)!;

  @override
  Widget build(BuildContext context) {
    return TransientAnimatedValue<Offset>(
      value: offset,
      duration: duration,
      curve: curve,
      lerp: _lerp,
      child: child,
      builder: (_, value, child) => FractionalTranslation(
        translation: value,
        transformHitTests: transformHitTests,
        child: child,
      ),
    );
  }
}

class TransientAnimatedRotation extends StatelessWidget {
  const TransientAnimatedRotation({
    super.key,
    required this.turns,
    required this.duration,
    required this.child,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
  });

  final double turns;
  final Duration duration;
  final Curve curve;
  final Alignment alignment;
  final Widget child;

  static double _lerp(double begin, double end, double progress) =>
      begin + (end - begin) * progress;

  @override
  Widget build(BuildContext context) {
    return TransientAnimatedValue<double>(
      value: turns,
      duration: duration,
      curve: curve,
      lerp: _lerp,
      child: child,
      builder: (_, value, child) => Transform.rotate(
        angle: value * math.pi * 2,
        alignment: alignment,
        child: child,
      ),
    );
  }
}
