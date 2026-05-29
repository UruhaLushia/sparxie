import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../rust_api.dart' as rust;

/// In-memory cache of resolved process icons + app names, keyed by the
/// platform's process id (exec path on desktop, package name on Android).
/// Rust owns the on-disk cache; this dedups requests and notifies listeners
/// so a tile repaints once its icon lands. Android resolves via a Kotlin
/// MethodChannel (PackageManager), then persists through Rust's disk cache.
class ProcessIconCache extends ChangeNotifier {
  static const _channel = MethodChannel('zip.atri.sparxie/process_icons');

  final Map<String, Uint8List> _icons = {};
  final Set<String> _missing = {};
  final Set<String> _requested = {};

  final Map<String, String> _names = {};
  final Set<String> _nameMissing = {};
  final Set<String> _nameRequested = {};

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Uint8List? iconFor(String key) => _icons[key];

  bool isMissing(String key) => _missing.contains(key);

  String? nameFor(String key) => _names[key];

  void request(String key) {
    if (key.isEmpty) return;
    if (_icons.containsKey(key) ||
        _missing.contains(key) ||
        _requested.contains(key)) {
      return;
    }
    _requested.add(key);
    (_isAndroid ? _resolveAndroid(key) : rust.fetchProcessIcon(path: key))
        .then((bytes) => _complete(key, bytes))
        .catchError((_) {
          _requested.remove(key);
        });
  }

  void requestName(String key) {
    if (key.isEmpty) return;
    if (_names.containsKey(key) ||
        _nameMissing.contains(key) ||
        _nameRequested.contains(key)) {
      return;
    }
    _nameRequested.add(key);
    (_isAndroid ? _resolveNameAndroid(key) : rust.fetchProcessName(path: key))
        .then((name) => _completeName(key, name))
        .catchError((_) {
          _nameRequested.remove(key);
        });
  }

  // Android: disk cache (persisted across launches) first, then PackageManager.
  Future<String?> _resolveNameAndroid(String key) async {
    final cached = await rust.cachedProcessName(key: key);
    if (cached != null && cached.isNotEmpty) return cached;
    final resolved = await _channel.invokeMethod<String>('getName', {
      'package': key,
    });
    if (resolved != null && resolved.isNotEmpty) {
      await rust.storeProcessName(key: key, name: resolved);
    }
    return resolved;
  }

  Future<Uint8List?> _resolveAndroid(String key) async {
    final cached = await rust.cachedProcessIcon(key: key);
    if (cached != null && cached.isNotEmpty) return cached;
    final resolved = await _channel.invokeMethod<Uint8List>('getIcon', {
      'package': key,
    });
    if (resolved != null && resolved.isNotEmpty) {
      await rust.storeProcessIcon(key: key, bytes: resolved);
    }
    return resolved;
  }

  void _complete(String key, Uint8List? bytes) {
    _requested.remove(key);
    if (bytes != null && bytes.isNotEmpty) {
      _icons[key] = bytes;
    } else {
      _missing.add(key);
    }
    notifyListeners();
  }

  void _completeName(String key, String? name) {
    _nameRequested.remove(key);
    if (name != null && name.isNotEmpty) {
      _names[key] = name;
    } else {
      _nameMissing.add(key);
    }
    notifyListeners();
  }

  void reset() {
    if (_missing.isEmpty &&
        _requested.isEmpty &&
        _nameMissing.isEmpty &&
        _nameRequested.isEmpty) {
      return;
    }
    _missing.clear();
    _requested.clear();
    _nameMissing.clear();
    _nameRequested.clear();
    rust.resetProcessIconMisses();
    notifyListeners();
  }

  @override
  void dispose() {
    _icons.clear();
    _missing.clear();
    _requested.clear();
    _names.clear();
    _nameMissing.clear();
    _nameRequested.clear();
    super.dispose();
  }
}
