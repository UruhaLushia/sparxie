import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reads the host platform's accent color when a stable native API is
/// available. Unsupported systems return null and keep the generated fallback.
class SystemAccentColor extends ChangeNotifier with WidgetsBindingObserver {
  SystemAccentColor._();

  static const _channel = MethodChannel('zip.atri.sparxie/system_colors');

  Color? _color;
  var _enabled = false;

  Color? get color => _color;

  static Future<SystemAccentColor> load({required bool enabled}) async {
    final value = SystemAccentColor._();
    WidgetsBinding.instance.addObserver(value);
    value._enabled = enabled;
    if (enabled) {
      await value.refresh();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(value.refresh());
      });
    }
    return value;
  }

  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!_enabled || kIsWeb) return;
    try {
      final argb = await _channel.invokeMethod<int>('getAccentColor');
      final next = argb == null ? null : Color(argb);
      if (next == _color) return;
      _color = next;
      notifyListeners();
    } on MissingPluginException {
      // The platform does not expose a system accent color.
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('system accent color unavailable: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_enabled && state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
