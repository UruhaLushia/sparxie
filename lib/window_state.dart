import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'config_store.dart';

/// Desktop-only persistence of the OS window's geometry. Mobile/web
/// targets are no-ops.
class WindowState with WindowListener {
  WindowState._(this._store);

  static const _kWidth = 'width';
  static const _kHeight = 'height';
  static const _kX = 'x';
  static const _kY = 'y';
  static const _kMaximized = 'maximized';
  static const _kFullScreen = 'fullscreen';

  static const Size _defaultSize = Size(1100, 720);
  static const Size _minimumSize = Size(380, 600);
  static const double _maxDim = 8192;

  static const Duration _saveDebounce = Duration(milliseconds: 300);

  final JsonStore _store;
  Timer? _saveTimer;

  Map<String, dynamic> get _s => _store.section('window');

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  static Future<WindowState?> bind(JsonStore store) async {
    if (!_isDesktop) return null;
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(_minimumSize);
    // setPreventClose lets us flush a pending save before the process exits.
    await windowManager.setPreventClose(true);
    final state = WindowState._(store);
    await state._restore();
    windowManager.addListener(state);
    return state;
  }

  double? _double(String key) {
    final v = _s[key];
    return v is num ? v.toDouble() : null;
  }

  bool _bool(String key) => _s[key] == true;

  Future<void> _restore() async {
    final width = _double(_kWidth) ?? _defaultSize.width;
    final height = _double(_kHeight) ?? _defaultSize.height;
    final x = _double(_kX);
    final y = _double(_kY);
    final maximized = _bool(_kMaximized);
    final fullscreen = _bool(_kFullScreen);

    final size = Size(
      width.clamp(_minimumSize.width, _maxDim),
      height.clamp(_minimumSize.height, _maxDim),
    );

    await windowManager.waitUntilReadyToShow(
      WindowOptions(size: size),
      () async {
        // setSize + setPosition rather than setBounds — the latter's
        // position hint is dropped pre-realize on GTK.
        await windowManager.setSize(size);
        if (x != null && y != null) {
          await windowManager.setPosition(Offset(x, y));
        } else {
          await windowManager.center();
        }
        if (fullscreen) {
          await windowManager.setFullScreen(true);
        } else if (maximized) {
          await windowManager.maximize();
        }
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  @override
  void onWindowResized() => _scheduleSave();
  @override
  void onWindowMoved() => _scheduleSave();
  @override
  void onWindowMaximize() => _scheduleSave();
  @override
  void onWindowUnmaximize() => _scheduleSave();
  @override
  void onWindowEnterFullScreen() => _scheduleSave();
  @override
  void onWindowLeaveFullScreen() => _scheduleSave();

  @override
  void onWindowClose() => unawaited(_flushAndDestroy());

  Future<void> _flushAndDestroy() async {
    final timer = _saveTimer;
    if (timer != null && timer.isActive) {
      timer.cancel();
      await _save();
    }
    await windowManager.destroy();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _save);
  }

  Future<void> _save() async {
    try {
      final (fullscreen, rawMaximized, bounds) = await (
        windowManager.isFullScreen(),
        windowManager.isMaximized(),
        windowManager.getBounds(),
      ).wait;
      final maximized = !fullscreen && rawMaximized;
      final s = _s;
      // Bounds under maximized/fullscreen are the screen's, not the user's
      // floating layout — don't overwrite the saved one.
      if (!maximized && !fullscreen) {
        s[_kWidth] = bounds.width;
        s[_kHeight] = bounds.height;
        s[_kX] = bounds.left;
        s[_kY] = bounds.top;
      }
      s[_kMaximized] = maximized;
      s[_kFullScreen] = fullscreen;
      await _store.flush();
    } catch (e) {
      if (kDebugMode) debugPrint('window state save failed: $e');
    }
  }
}
