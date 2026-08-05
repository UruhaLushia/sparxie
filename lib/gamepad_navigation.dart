import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

class DirectionalFocusNavigatorObserver extends NavigatorObserver {
  void _focusRoute(Route<dynamic>? route) {
    if (route is! ModalRoute<dynamic>) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = route.subtreeContext;
      if (!route.isCurrent ||
          context == null ||
          !context.mounted ||
          FocusManager.instance.highlightMode !=
              FocusHighlightMode.traditional) {
        return;
      }
      final scope = FocusScope.of(context);
      if (!scope.hasFocus || scope.hasPrimaryFocus) scope.nextFocus();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _focusRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _focusRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _focusRoute(newRoute);
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
final _gamepadScrollUpDirection =
    defaultTargetPlatform == TargetPlatform.android
    ? AxisDirection.down
    : AxisDirection.up;
final _gamepadScrollDownDirection =
    defaultTargetPlatform == TargetPlatform.android
    ? AxisDirection.up
    : AxisDirection.down;

final _focusUpIntent = GamepadDirectionalFocusIntent(_gamepadUpDirection);
final _focusDownIntent = GamepadDirectionalFocusIntent(_gamepadDownDirection);
const _focusLeftIntent = GamepadDirectionalFocusIntent(TraversalDirection.left);
const _focusRightIntent = GamepadDirectionalFocusIntent(
  TraversalDirection.right,
);
final _scrollUpIntent = ScrollIntent(direction: _gamepadScrollUpDirection);
final _scrollDownIntent = ScrollIntent(direction: _gamepadScrollDownDirection);
const _scrollLeftIntent = ScrollIntent(direction: AxisDirection.left);
const _scrollRightIntent = ScrollIntent(direction: AxisDirection.right);

final gamepadShortcuts = <GamepadActivator, Intent>{
  GamepadActivatorButton.a(): ActivateIntent(),
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
  GamepadActivatorAxis.rightStickUp(): _scrollUpIntent,
  GamepadActivatorAxis.rightStickLeft(): _scrollLeftIntent,
  GamepadActivatorAxis.rightStickDown(): _scrollDownIntent,
  GamepadActivatorAxis.rightStickRight(): _scrollRightIntent,
};

final gamepadRepeatIntents = <Intent>{
  _focusUpIntent,
  _focusDownIntent,
  _focusLeftIntent,
  _focusRightIntent,
  _scrollUpIntent,
  _scrollDownIntent,
  _scrollLeftIntent,
  _scrollRightIntent,
};

const gamepadKeyboardShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.gameButtonA, includeRepeats: false):
      ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButton1, includeRepeats: false):
      ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.select, includeRepeats: false):
      ActivateIntent(),
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
