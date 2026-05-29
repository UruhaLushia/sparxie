import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop-only persistence of the OS window's geometry. Mobile/web
/// targets are no-ops.
class WindowState with WindowListener {
  WindowState._(this._prefs);

  static const _kWidth = 'window.width';
  static const _kHeight = 'window.height';
  static const _kX = 'window.x';
  static const _kY = 'window.y';
  static const _kMaximized = 'window.maximized';
  static const _kFullScreen = 'window.fullscreen';

  static const Size _defaultSize = Size(1100, 720);
  static const Size _minimumSize = Size(380, 600);
  static const double _maxDim = 8192;

  static const Duration _saveDebounce = Duration(milliseconds: 300);

  final SharedPreferences _prefs;
  Timer? _saveTimer;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  static Future<WindowState?> bind() async {
    if (!_isDesktop) return null;
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(_minimumSize);
    // setPreventClose lets us flush a pending save before the process exits.
    await windowManager.setPreventClose(true);
    final prefs = await SharedPreferences.getInstance();
    final state = WindowState._(prefs);
    await state._restore();
    windowManager.addListener(state);
    return state;
  }

  Future<void> _restore() async {
    final width = _prefs.getDouble(_kWidth) ?? _defaultSize.width;
    final height = _prefs.getDouble(_kHeight) ?? _defaultSize.height;
    final x = _prefs.getDouble(_kX);
    final y = _prefs.getDouble(_kY);
    final maximized = _prefs.getBool(_kMaximized) ?? false;
    final fullscreen = _prefs.getBool(_kFullScreen) ?? false;

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
      await Future.wait([
        // Bounds under maximized/fullscreen are the screen's, not the
        // user's floating layout — don't overwrite the saved one.
        if (!maximized && !fullscreen) ...[
          _prefs.setDouble(_kWidth, bounds.width),
          _prefs.setDouble(_kHeight, bounds.height),
          _prefs.setDouble(_kX, bounds.left),
          _prefs.setDouble(_kY, bounds.top),
        ],
        _prefs.setBool(_kMaximized, maximized),
        _prefs.setBool(_kFullScreen, fullscreen),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('window state save failed: $e');
    }
  }
}
