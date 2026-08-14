import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef ValueSelector<T, S> = S Function(T value);
typedef ListenableSelector<S> = S Function();

bool isUiActive(BuildContext context) => TickerMode.valuesOf(context).enabled;

bool isUiScrolling(BuildContext context) =>
    _UiScrollActivityScope.isScrollingOf(context);

bool isUiFastScrolling(BuildContext context) =>
    _UiFastScrollActivityScope.isFastScrollingOf(context);

bool isRealtimeUiActive(BuildContext context) =>
    isUiActive(context) && !isUiScrolling(context);

/// Keeps rows that are already painted intact, but lets newly materialized
/// rows use cheap geometry during a high-speed fling. Slow, direct dragging
/// always builds real content; placeholders resolve as soon as velocity drops.
class ScrollDeferredContent extends StatefulWidget {
  const ScrollDeferredContent({
    super.key,
    required this.placeholder,
    required this.child,
  });

  final Widget placeholder;
  final Widget child;

  @override
  State<ScrollDeferredContent> createState() => _ScrollDeferredContentState();
}

class _ScrollDeferredContentState extends State<ScrollDeferredContent> {
  var _contentBuilt = false;

  @override
  Widget build(BuildContext context) {
    if (!_contentBuilt && isUiFastScrolling(context)) {
      return widget.placeholder;
    }
    _contentBuilt = true;
    return widget.child;
  }
}

/// Exposes one app-wide scrolling flag without rebuilding the app shell.
/// Frequently changing leaf values can pause while a viewport is moving and
/// catch up once it settles, leaving list structure and lazy loading untouched.
class UiScrollActivityScope extends StatefulWidget {
  const UiScrollActivityScope({super.key, required this.child});

  final Widget child;

  @override
  State<UiScrollActivityScope> createState() => _UiScrollActivityScopeState();
}

class _UiScrollActivityScopeState extends State<UiScrollActivityScope> {
  static const _wheelIdleGrace = Duration(milliseconds: 80);

  final _scrolling = ValueNotifier(false);
  final _fastScrolling = ValueNotifier(false);
  Timer? _idleTimer;
  var _activeScrolls = 0;
  var _nextScrolling = false;
  var _nextFastScrolling = false;
  var _activityUpdateScheduled = false;
  Duration? _lastScrollUpdate;

  void _setScrolling(bool value) {
    if (_nextScrolling == value) return;
    _nextScrolling = value;
    _publishActivity();
  }

  void _setFastScrolling(bool value) {
    if (_nextFastScrolling == value) return;
    _nextFastScrolling = value;
    _publishActivity();
  }

  void _publishActivity() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (_activityUpdateScheduled) return;
      _activityUpdateScheduled = true;
      scheduler.addPostFrameCallback((_) {
        _activityUpdateScheduled = false;
        if (mounted) _applyActivity();
      });
      return;
    }
    _applyActivity();
  }

  void _applyActivity() {
    _scrolling.value = _nextScrolling;
    _fastScrolling.value = _nextFastScrolling;
  }

  void _updateFastScrolling(ScrollUpdateNotification notification) {
    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final previous = _lastScrollUpdate;
    _lastScrollUpdate = now;
    // Direct finger drags must remain visually exact. Deferral is reserved for
    // ballistic flings, wheel bursts, and programmatic high-speed movement.
    if (notification.dragDetails != null) {
      _setFastScrolling(false);
      return;
    }
    final delta = notification.scrollDelta?.abs();
    if (previous == null || delta == null) return;
    final elapsedMicros = (now - previous).inMicroseconds;
    if (elapsedMicros <= 0 || elapsedMicros > 100000) return;
    final velocity = delta * Duration.microsecondsPerSecond / elapsedMicros;
    final viewportThreshold = notification.metrics.viewportDimension * 2.4;
    final enterThreshold = viewportThreshold < 1400
        ? 1400.0
        : viewportThreshold;
    final threshold = _nextFastScrolling
        ? enterThreshold * 0.65
        : enterThreshold;
    _setFastScrolling(velocity >= threshold);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _idleTimer?.cancel();
      _idleTimer = null;
      if (_activeScrolls == 0) {
        _lastScrollUpdate =
            SchedulerBinding.instance.currentSystemFrameTimeStamp;
        _setFastScrolling(false);
      }
      _activeScrolls++;
      _setScrolling(true);
    } else if (notification is ScrollUpdateNotification) {
      _updateFastScrolling(notification);
    } else if (notification is ScrollEndNotification) {
      if (_activeScrolls > 0) _activeScrolls--;
      if (_activeScrolls == 0) {
        _lastScrollUpdate = null;
        _setFastScrolling(false);
        // Pointer-wheel scrolling can start and end synchronously for every
        // event. Keep the flag through the resulting frame and wheel burst.
        _idleTimer?.cancel();
        _idleTimer = Timer(_wheelIdleGrace, () {
          _setScrolling(false);
        });
      }
    }
    return false;
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _scrolling.dispose();
    _fastScrolling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _UiScrollActivityScope(
      scrolling: _scrolling,
      child: _UiFastScrollActivityScope(
        fastScrolling: _fastScrolling,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      ),
    );
  }
}

class _UiScrollActivityScope extends InheritedNotifier<ValueNotifier<bool>> {
  const _UiScrollActivityScope({
    required ValueNotifier<bool> scrolling,
    required super.child,
  }) : super(notifier: scrolling);

  static bool isScrollingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_UiScrollActivityScope>()
          ?.notifier
          ?.value ??
      false;
}

class _UiFastScrollActivityScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const _UiFastScrollActivityScope({
    required ValueNotifier<bool> fastScrolling,
    required super.child,
  }) : super(notifier: fastScrolling);

  static bool isFastScrollingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_UiFastScrollActivityScope>()
          ?.notifier
          ?.value ??
      false;
}

/// Shared lifecycle for builders that stop listening while their page is
/// hidden, and optionally while a viewport is moving.
abstract class _ActiveBuilderWidget<T> extends StatefulWidget {
  const _ActiveBuilderWidget({super.key});

  Listenable get listenable;
  bool get pauseWhileScrolling;
  bool get distinct;

  T readValue();
  Widget buildValue(BuildContext context, T value);

  @override
  State<_ActiveBuilderWidget<T>> createState() => _ActiveBuilderState<T>();
}

class _ActiveBuilderState<T> extends State<_ActiveBuilderWidget<T>> {
  late T _value = widget.readValue();
  var _listening = false;
  var _dirty = true;
  Widget? _built;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncListening();
    if (_listening) _dirty = true;
  }

  @override
  void didUpdateWidget(covariant _ActiveBuilderWidget<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dirty = true;
    if (_listening && oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onChanged);
      widget.listenable.addListener(_onChanged);
    }
    _value = widget.readValue();
  }

  void _syncListening() {
    final listening =
        isUiActive(context) &&
        (!widget.pauseWhileScrolling || !isUiScrolling(context));
    if (_listening == listening) return;
    _listening = listening;
    if (listening) {
      _value = widget.readValue();
      widget.listenable.addListener(_onChanged);
    } else {
      widget.listenable.removeListener(_onChanged);
    }
  }

  void _onChanged() {
    final value = widget.readValue();
    if (widget.distinct && value == _value) return;
    setState(() {
      _value = value;
      _dirty = true;
    });
  }

  @override
  void dispose() {
    if (_listening) widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncListening();
    if (_built == null || (_listening && _dirty)) {
      _built = widget.buildValue(context, _value);
      _dirty = false;
    }
    return _built!;
  }
}

/// Stops listening to a frequently changing value while its page is hidden.
/// The latest value is read again as soon as the page becomes active.
class ActiveValueListenableBuilder<T> extends _ActiveBuilderWidget<T> {
  const ActiveValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.child,
    this.pauseWhileScrolling = false,
  });

  final ValueListenable<T> valueListenable;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;
  @override
  final bool pauseWhileScrolling;

  @override
  Listenable get listenable => valueListenable;

  @override
  bool get distinct => false;

  @override
  T readValue() => valueListenable.value;

  @override
  Widget buildValue(BuildContext context, T value) =>
      builder(context, value, child);
}

class ActiveListenableBuilder extends _ActiveBuilderWidget<bool> {
  const ActiveListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
    this.pauseWhileScrolling = false,
  });

  @override
  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;
  @override
  final bool pauseWhileScrolling;

  @override
  bool get distinct => false;

  @override
  bool readValue() => false;

  @override
  Widget buildValue(BuildContext context, bool _) => builder(context, child);
}

/// Rebuilds only when a selected value from a plain [Listenable] changes.
class ActiveListenableSelector<S> extends _ActiveBuilderWidget<S> {
  const ActiveListenableSelector({
    super.key,
    required this.listenable,
    required this.selector,
    required this.builder,
    this.child,
    this.pauseWhileScrolling = false,
  });

  @override
  final Listenable listenable;
  final ListenableSelector<S> selector;
  final ValueWidgetBuilder<S> builder;
  final Widget? child;
  @override
  final bool pauseWhileScrolling;

  @override
  bool get distinct => true;

  @override
  S readValue() => selector();

  @override
  Widget buildValue(BuildContext context, S value) =>
      builder(context, value, child);
}

/// Rebuilds only when the selected portion of an active value changes.
class ActiveValueListenableSelector<T, S> extends _ActiveBuilderWidget<S> {
  const ActiveValueListenableSelector({
    super.key,
    required this.valueListenable,
    required this.selector,
    required this.builder,
    this.child,
    this.pauseWhileScrolling = false,
  });

  final ValueListenable<T> valueListenable;
  final ValueSelector<T, S> selector;
  final ValueWidgetBuilder<S> builder;
  final Widget? child;
  @override
  final bool pauseWhileScrolling;

  @override
  Listenable get listenable => valueListenable;

  @override
  bool get distinct => true;

  @override
  S readValue() => selector(valueListenable.value);

  @override
  Widget buildValue(BuildContext context, S value) =>
      builder(context, value, child);
}
