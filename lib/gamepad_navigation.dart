import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gamepads/flutter_gamepads.dart';

enum GamepadNavigationAction {
  back,
  up,
  down,
  left,
  right,
  previousPage,
  nextPage,
}

class GamepadDirectionalFocusIntent extends NextFocusIntent {
  const GamepadDirectionalFocusIntent(this.direction);

  final TraversalDirection direction;
}

class SwitchPageIntent extends NextFocusIntent {
  const SwitchPageIntent(this.delta);

  final int delta;
}

class LongPressActivateIntent extends Intent {
  const LongPressActivateIntent();
}

class ActivationPressStartIntent extends Intent {
  const ActivationPressStartIntent();
}

class ActivationPressEndIntent extends Intent {
  const ActivationPressEndIntent();
}

const gamepadLongPressDuration = Duration(milliseconds: 750);

class NavigationInputController {
  static const _scrollDeadzone = 0.16;
  static const _scrollSpeed = 900.0;

  final _timers = <Object, Timer>{};
  final _focusNodes = <Object, FocusNode>{};
  final _longPressed = <Object>{};
  double _scrollX = 0;
  double _scrollY = 0;
  ScrollPositionWithSingleContext? _activeScrollPosition;
  _GamepadScrollActivity? _activeScrollActivity;
  Duration? _lastScrollFrame;
  bool _scrollFrameScheduled = false;
  bool _disposed = false;

  void press(Object source) {
    if (_timers.containsKey(source)) return;
    final focusNode = FocusManager.instance.primaryFocus;
    final context = focusNode?.context;
    if (focusNode == null || context == null || !context.mounted) return;

    _focusNodes[source] = focusNode;
    Actions.maybeInvoke(context, const ActivationPressStartIntent());
    _timers[source] = Timer(gamepadLongPressDuration, () {
      if (FocusManager.instance.primaryFocus != focusNode) return;
      final context = focusNode.context;
      if (context != null && context.mounted) {
        _longPressed.add(source);
        Actions.maybeInvoke(context, const LongPressActivateIntent());
      }
    });
  }

  void release(Object source) {
    _timers.remove(source)?.cancel();
    final focusNode = _focusNodes.remove(source);
    final context = focusNode?.context;
    if (context != null && context.mounted) {
      Actions.maybeInvoke(context, const ActivationPressEndIntent());
      if (!_longPressed.remove(source) &&
          FocusManager.instance.primaryFocus == focusNode) {
        Actions.maybeInvoke(context, const ActivateIntent());
      }
    } else {
      _longPressed.remove(source);
    }
  }

  void updateScrollAxis({double? horizontal, double? vertical}) {
    if (horizontal != null) _scrollX = _applyDeadzone(horizontal);
    if (vertical != null) _scrollY = _applyDeadzone(vertical);
    if (_scrollX == 0 && _scrollY == 0) {
      _lastScrollFrame = null;
      _stopScrollActivity();
      return;
    }
    _scheduleScrollFrame();
  }

  double _applyDeadzone(double value) {
    final magnitude = value.abs();
    if (magnitude <= _scrollDeadzone) return 0;
    final normalized = (magnitude - _scrollDeadzone) / (1 - _scrollDeadzone);
    return value.sign * normalized * normalized;
  }

  void _scheduleScrollFrame() {
    if (_disposed || _scrollFrameScheduled) return;
    _scrollFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_handleScrollFrame);
  }

  void _handleScrollFrame(Duration timestamp) {
    _scrollFrameScheduled = false;
    if (_disposed || (_scrollX == 0 && _scrollY == 0)) {
      _lastScrollFrame = null;
      _stopScrollActivity();
      return;
    }
    final previous = _lastScrollFrame;
    _lastScrollFrame = timestamp;
    if (previous != null) {
      final elapsed = (timestamp - previous).inMicroseconds / 1000000;
      _scrollFocusedContent(elapsed.clamp(0, 0.05));
    }
    _scheduleScrollFrame();
  }

  void _scrollFocusedContent(double elapsed) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return;
    final preferVertical = _scrollY.abs() >= _scrollX.abs();
    final preferredAxis = preferVertical ? Axis.vertical : Axis.horizontal;
    final fallbackAxis = preferVertical ? Axis.horizontal : Axis.vertical;
    final scrollable =
        Scrollable.maybeOf(context, axis: preferredAxis) ??
        Scrollable.maybeOf(context, axis: fallbackAxis);
    if (scrollable == null || !scrollable.position.hasPixels) {
      _stopScrollActivity();
      return;
    }

    final input = axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical
        ? _scrollY
        : _scrollX;
    if (input == 0) {
      _stopScrollActivity();
      return;
    }
    final direction = switch (scrollable.axisDirection) {
      AxisDirection.down => -1.0,
      AxisDirection.up => 1.0,
      AxisDirection.right => 1.0,
      AxisDirection.left => -1.0,
    };
    final position = scrollable.position;
    if (position is! ScrollPositionWithSingleContext) {
      position.pointerScroll(input * direction * _scrollSpeed * elapsed);
      return;
    }
    final activity = _activityFor(position);
    activity.scrollBy(input * direction * _scrollSpeed * elapsed);
  }

  _GamepadScrollActivity _activityFor(
    ScrollPositionWithSingleContext position,
  ) {
    final current = _activeScrollActivity;
    if (identical(_activeScrollPosition, position) && current != null) {
      return current;
    }
    _stopScrollActivity();
    late final _GamepadScrollActivity activity;
    activity = _GamepadScrollActivity(
      position,
      onDisposed: () {
        if (identical(_activeScrollActivity, activity)) {
          _activeScrollActivity = null;
          _activeScrollPosition = null;
          _scrollX = 0;
          _scrollY = 0;
          _lastScrollFrame = null;
        }
      },
    );
    _activeScrollPosition = position;
    _activeScrollActivity = activity;
    position.beginActivity(activity);
    return activity;
  }

  void _stopScrollActivity() {
    final position = _activeScrollPosition;
    if (position == null || _activeScrollActivity == null) return;
    _activeScrollPosition = null;
    _activeScrollActivity = null;
    position.beginActivity(IdleScrollActivity(position));
  }

  void dispose() {
    _disposed = true;
    _stopScrollActivity();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _focusNodes.clear();
    _longPressed.clear();
    _scrollX = 0;
    _scrollY = 0;
  }
}

class _GamepadScrollActivity extends ScrollActivity {
  _GamepadScrollActivity(this.position, {required this.onDisposed})
    : super(position);

  final ScrollPositionWithSingleContext position;
  final VoidCallback onDisposed;
  bool _disposed = false;

  void scrollBy(double delta) {
    if (!_disposed && delta != 0) {
      delegate.setPixels(position.pixels + delta);
    }
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => 0;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onDisposed();
    super.dispose();
  }
}

abstract interface class FocusRestorationRoute {
  FocusNode? get sourceFocusNode;
}

class DirectionalFocusNavigatorObserver extends NavigatorObserver {
  static const _focusRestoreAttempts = 4;
  final _routeFocusNodes = <Route<dynamic>, FocusNode>{};

  void _focusRoute(
    Route<dynamic>? route, {
    FocusNode? preferredFocus,
    int remainingAttempts = _focusRestoreAttempts,
  }) {
    if (route is! ModalRoute<dynamic>) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = route.subtreeContext;
      if (FocusManager.instance.highlightMode !=
          FocusHighlightMode.traditional) {
        return;
      }
      if (!route.isCurrent || context == null || !context.mounted) {
        if (preferredFocus != null && remainingAttempts > 0) {
          _focusRoute(
            route,
            preferredFocus: preferredFocus,
            remainingAttempts: remainingAttempts - 1,
          );
        }
        return;
      }
      final preferredContext = preferredFocus?.context;
      if (preferredFocus != null) {
        if (preferredContext != null &&
            preferredContext.mounted &&
            preferredFocus.canRequestFocus) {
          preferredFocus.requestFocus();
          FocusManager.instance.applyFocusChangesIfNeeded();
        } else if (remainingAttempts > 0) {
          _focusRoute(
            route,
            preferredFocus: preferredFocus,
            remainingAttempts: remainingAttempts - 1,
          );
        }
        return;
      }
      final scope = FocusScope.of(context);
      if (!scope.hasFocus || scope.hasPrimaryFocus) scope.nextFocus();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final focusNode = route is FocusRestorationRoute
        ? (route as FocusRestorationRoute).sourceFocusNode
        : FocusManager.instance.primaryFocus;
    if (previousRoute != null && focusNode != null) {
      _routeFocusNodes[previousRoute] = focusNode;
    }
    _focusRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeFocusNodes.remove(route);
    final preferredFocus = previousRoute == null
        ? null
        : _routeFocusNodes[previousRoute];
    _focusRoute(previousRoute, preferredFocus: preferredFocus);
    if (preferredFocus != null && route is TransitionRoute<dynamic>) {
      unawaited(
        route.completed.then(
          (_) => _focusRoute(previousRoute, preferredFocus: preferredFocus),
        ),
      );
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _routeFocusNodes.remove(oldRoute);
    _focusRoute(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeFocusNodes.remove(route);
    _focusRoute(
      previousRoute,
      preferredFocus: previousRoute == null
          ? null
          : _routeFocusNodes[previousRoute],
    );
  }
}

// The Android plugin flips vertical Hat/stick axes before the Dart normalizer
// flips them again. Compensate only for gamepad events; keyboard and remote
// logical-key directions remain unchanged.
final _gamepadUpDirection = defaultTargetPlatform == TargetPlatform.android
    ? TraversalDirection.down
    : TraversalDirection.up;
final _gamepadDownDirection = defaultTargetPlatform == TargetPlatform.android
    ? TraversalDirection.up
    : TraversalDirection.down;
final _focusUpIntent = GamepadDirectionalFocusIntent(_gamepadUpDirection);
final _focusDownIntent = GamepadDirectionalFocusIntent(_gamepadDownDirection);
const _focusLeftIntent = GamepadDirectionalFocusIntent(TraversalDirection.left);
const _focusRightIntent = GamepadDirectionalFocusIntent(
  TraversalDirection.right,
);
final gamepadShortcuts = <GamepadActivator, Intent>{
  GamepadActivatorButton.b(): DismissIntent(),
  GamepadActivatorButton.back(): DismissIntent(),
  GamepadActivatorButton.leftBumper(): SwitchPageIntent(-1),
  GamepadActivatorButton.rightBumper(): SwitchPageIntent(1),
  GamepadActivatorButton.dpadUp(): _focusUpIntent,
  GamepadActivatorButton.dpadLeft(): _focusLeftIntent,
  GamepadActivatorButton.dpadDown(): _focusDownIntent,
  GamepadActivatorButton.dpadRight(): _focusRightIntent,
  GamepadActivatorAxis.leftStickUp(): _focusUpIntent,
  GamepadActivatorAxis.leftStickLeft(): _focusLeftIntent,
  GamepadActivatorAxis.leftStickDown(): _focusDownIntent,
  GamepadActivatorAxis.leftStickRight(): _focusRightIntent,
};

final gamepadRepeatIntents = <Intent>{
  _focusUpIntent,
  _focusDownIntent,
  _focusLeftIntent,
  _focusRightIntent,
};

class AppFocusHighlight extends StatelessWidget {
  const AppFocusHighlight({
    super.key,
    required this.child,
    required this.borderRadius,
    this.focused,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool? focused;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget highlight(bool hasFocus) {
      final showHighlight =
          hasFocus &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: showHighlight ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: borderRadius,
          boxShadow: showHighlight
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 0,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: child,
      );
    }

    final forcedFocus = focused;
    if (forcedFocus != null) return highlight(forcedFocus);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      child: Builder(
        builder: (context) => highlight(Focus.of(context).hasFocus),
      ),
    );
  }
}

class GamepadSliderControl extends StatefulWidget {
  const GamepadSliderControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.child,
    required this.onChanged,
    this.divisions,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Widget child;

  @override
  State<GamepadSliderControl> createState() => _GamepadSliderControlState();
}

class _GamepadSliderControlState extends State<GamepadSliderControl> {
  static const _changeEndDelay = Duration(milliseconds: 260);
  Timer? _changeEndTimer;

  @override
  void dispose() {
    _changeEndTimer?.cancel();
    super.dispose();
  }

  void _scheduleChangeEnd(double value) {
    if (widget.onChangeEnd == null) return;
    _changeEndTimer?.cancel();
    _changeEndTimer = Timer(_changeEndDelay, () {
      _changeEndTimer = null;
      widget.onChangeEnd?.call(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GamepadInterceptor(
      onBeforeIntent: (_, intent) {
        if (intent is! GamepadDirectionalFocusIntent ||
            (intent.direction != TraversalDirection.left &&
                intent.direction != TraversalDirection.right)) {
          return true;
        }
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final increase = intent.direction == TraversalDirection.right
            ? !rtl
            : rtl;
        final step = widget.divisions == null
            ? (widget.max - widget.min) / 20
            : (widget.max - widget.min) / widget.divisions!;
        final next = (widget.value + (increase ? step : -step))
            .clamp(widget.min, widget.max)
            .toDouble();
        if (next != widget.value) {
          widget.onChanged(next);
          _scheduleChangeEnd(next);
        }
        return false;
      },
      child: widget.child,
    );
  }
}

GamepadNavigationAction? gamepadNavigationActionFor(LogicalKeyboardKey key) =>
    switch (key) {
      LogicalKeyboardKey.escape ||
      LogicalKeyboardKey.browserBack ||
      LogicalKeyboardKey.goBack ||
      LogicalKeyboardKey.gameButtonB ||
      LogicalKeyboardKey.gameButton2 ||
      LogicalKeyboardKey.gameButtonSelect => GamepadNavigationAction.back,
      LogicalKeyboardKey.arrowUp => GamepadNavigationAction.up,
      LogicalKeyboardKey.arrowDown => GamepadNavigationAction.down,
      LogicalKeyboardKey.arrowLeft => GamepadNavigationAction.left,
      LogicalKeyboardKey.arrowRight => GamepadNavigationAction.right,
      LogicalKeyboardKey.gameButtonLeft1 =>
        GamepadNavigationAction.previousPage,
      LogicalKeyboardKey.gameButtonRight1 => GamepadNavigationAction.nextPage,
      _ => null,
    };
