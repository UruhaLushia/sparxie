import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'app_prefs.dart';

class BackgroundRotationController with WidgetsBindingObserver {
  BackgroundRotationController(this._prefs);

  final AppPrefs _prefs;
  final _random = math.Random();
  bool _started = false;
  bool _hasEnteredForeground = false;
  bool _wasBackgrounded = false;
  bool _advancing = false;

  void start() {
    if (_started) return;
    _started = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _hasEnteredForeground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_advance(BackgroundRotationTrigger.appLaunch));
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final resumedFromBackground = _hasEnteredForeground && _wasBackgrounded;
        _hasEnteredForeground = true;
        _wasBackgrounded = false;
        if (resumedFromBackground) {
          unawaited(_advance(BackgroundRotationTrigger.appResume));
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_hasEnteredForeground) _wasBackgrounded = true;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _advance(BackgroundRotationTrigger trigger) async {
    final references = _prefs.backgroundImageReferences;
    if (!_started ||
        _advancing ||
        _prefs.backgroundSource != AppBackgroundSource.image ||
        !_prefs.backgroundRotationEnabled ||
        _prefs.backgroundRotationTrigger != trigger ||
        references.length < 2) {
      return;
    }

    _advancing = true;
    try {
      final count = references.length;
      final current = _prefs.backgroundImageIndex.clamp(0, count - 1).toInt();
      final next = switch (_prefs.backgroundRotationOrder) {
        BackgroundRotationOrder.sequential => (current + 1) % count,
        BackgroundRotationOrder.random => () {
          final candidate = _random.nextInt(count - 1);
          return candidate >= current ? candidate + 1 : candidate;
        }(),
      };
      await _prefs.selectBackgroundImage(next);
    } finally {
      _advancing = false;
    }
  }
}
