import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves where app data (config + cache) lives.
///
/// Portable mode: a `.portable` marker file beside the executable redirects
/// everything to `<exeDir>/userdata`, so a Windows zip can be unzipped anywhere
/// and keep its data self-contained. Otherwise the platform's standard
/// per-user directories are used (the Inno installer relies on this, since
/// Program Files isn't user-writable).
class AppPaths {
  AppPaths._();

  static bool? _portable;
  static Directory? _portableRoot;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// True when a `.portable` marker sits next to the executable.
  static bool get isPortable {
    if (_portable != null) return _portable!;
    var portable = false;
    if (_isDesktop) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent;
        if (File('${exeDir.path}/.portable').existsSync()) {
          portable = true;
          _portableRoot = Directory('${exeDir.path}/userdata');
        }
      } catch (_) {
        // Fall through to non-portable on any probe failure.
      }
    }
    _portable = portable;
    return portable;
  }

  /// Directory for the config file (and, in portable mode, the cache too).
  static Future<Directory> configDir() async {
    if (isPortable) return _ensure(_portableRoot!);
    return getApplicationSupportDirectory();
  }

  /// Directory for the on-disk cache database.
  static Future<Directory> cacheDir() async {
    if (isPortable) return _ensure(_portableRoot!);
    return getApplicationCacheDirectory();
  }

  static Future<Directory> _ensure(Directory dir) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
