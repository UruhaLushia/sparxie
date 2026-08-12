import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app_prefs.dart';

class BackgroundRotationController with WidgetsBindingObserver, WindowListener {
  BackgroundRotationController(this._prefs);

  final AppPrefs _prefs;
  final _random = math.Random();
  bool _started = false;
  bool _hasEnteredForeground = false;
  bool _leftForeground = false;
  bool _advancing = false;

  void start() {
    if (_started) return;
    _started = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _hasEnteredForeground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (_isDesktop) windowManager.addListener(this);
    unawaited(_advance(BackgroundRotationTrigger.appLaunch));
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    if (_isDesktop) windowManager.removeListener(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDesktop) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _enterForeground();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _leaveForeground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void onWindowMinimize() => _leaveForeground();

  @override
  void onWindowRestore() => _enterForeground();

  bool get _isDesktop =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      };

  void _leaveForeground() {
    if (_hasEnteredForeground) _leftForeground = true;
  }

  void _enterForeground() {
    final shouldAdvance = _hasEnteredForeground && _leftForeground;
    _hasEnteredForeground = true;
    _leftForeground = false;
    if (shouldAdvance) {
      unawaited(_advance(BackgroundRotationTrigger.appResume));
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
