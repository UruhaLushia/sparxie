import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop-only persistence of the OS window's size/position/maximized
/// state. Mobile and web targets are no-ops — `bind` returns immediately
/// without subscribing to anything.
///
/// Save calls are coalesced through a short debounce so a window drag
/// emits one write at the end instead of one per pixel.
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
  // Defensive upper bound for restored dimensions. Anything larger almost
  // certainly came from a corrupted prefs file or a since-removed monitor.
  static const double _maxDim = 8192;

  static const Duration _saveDebounce = Duration(milliseconds: 500);

  final SharedPreferences _prefs;
  Timer? _saveTimer;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  /// Restore the saved window geometry before the window is shown, then
  /// register listeners so subsequent moves/resizes are persisted.
  ///
  /// Safe to call on any platform — non-desktop targets short-circuit.
  static Future<WindowState?> bind() async {
    if (!_isDesktop) return null;
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(_minimumSize);
    // Intercept close so we can flush a pending debounced save before the
    // process exits — without this, a quick resize-then-close can race
    // the SharedPreferences write and lose the new geometry.
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
        // Set size + position separately rather than via setBounds — GTK
        // applies setBounds' position hint inconsistently when the window
        // isn't yet realized, so explicit setSize/setPosition is more
        // portable across Linux/macOS/Windows.
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

  // Every geometry-changing event flushes through the same debounced save.
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
  void onWindowClose() {
    // setPreventClose keeps the window alive until we call destroy(),
    // so this is our chance to flush the latest geometry before exit.
    unawaited(_flushAndDestroy());
  }

  Future<void> _flushAndDestroy() async {
    _saveTimer?.cancel();
    try {
      await _save();
    } finally {
      await windowManager.destroy();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _save);
  }

  Future<void> _save() async {
    try {
      final fullscreen = await windowManager.isFullScreen();
      final maximized = !fullscreen && await windowManager.isMaximized();
      // Skip persisting bounds while maximized / full-screen — measured
      // bounds reflect the current screen, not the user's preferred
      // floating layout, which we want to restore on next launch.
      if (!maximized && !fullscreen) {
        final bounds = await windowManager.getBounds();
        await _prefs.setDouble(_kWidth, bounds.width);
        await _prefs.setDouble(_kHeight, bounds.height);
        await _prefs.setDouble(_kX, bounds.left);
        await _prefs.setDouble(_kY, bounds.top);
      }
      await _prefs.setBool(_kMaximized, maximized);
      await _prefs.setBool(_kFullScreen, fullscreen);
    } catch (e) {
      if (kDebugMode) debugPrint('window state save failed: $e');
    }
  }
}
