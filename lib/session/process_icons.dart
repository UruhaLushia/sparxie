import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

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
  static const _maxImages = 160;
  static const _maxNames = 512;
  static const _maxMisses = 512;
  static const _imageRetireDelay = Duration(milliseconds: 500);

  // Decoded, display-ready images. Desktop icons are normalized before they
  // enter Rust's disk cache; Android icons are already suitable as-is.
  final LinkedHashMap<String, ui.Image> _images =
      LinkedHashMap<String, ui.Image>();
  final Set<String> _missing = {};
  final Set<String> _requested = {};

  final LinkedHashMap<String, String> _names = LinkedHashMap<String, String>();
  final Set<String> _nameMissing = {};
  final Set<String> _nameRequested = {};

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  ui.Image? iconFor(String key, {int? size}) {
    final imageKey = _imageKey(key, size);
    final image = _images.remove(imageKey);
    if (image != null) _images[imageKey] = image;
    return image;
  }

  bool isMissing(String key) => _missing.contains(key);

  String? nameFor(String key) {
    final name = _names.remove(key);
    if (name != null) _names[key] = name;
    return name;
  }

  void request(String key, {int? size}) {
    if (key.isEmpty) return;
    final imageKey = _imageKey(key, size);
    if (_images.containsKey(imageKey) ||
        _missing.contains(imageKey) ||
        _requested.contains(imageKey)) {
      return;
    }
    _requested.add(imageKey);
    (_isAndroid
            ? _resolveAndroid(key)
            : rust.fetchProcessIcon(path: key, size: size))
        .then((bytes) => _complete(imageKey, bytes))
        .catchError((_) {
          _requested.remove(imageKey);
        });
  }

  String _imageKey(String key, int? size) => size == null ? key : '$key@$size';

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
    if (bytes == null || bytes.isEmpty) {
      _requested.remove(key);
      _remember(_missing, key, _maxMisses);
      notifyListeners();
      return;
    }
    _decode(bytes).then((image) {
      _requested.remove(key);
      if (image != null) {
        final previous = _images.remove(key);
        if (previous != null) _retireImage(previous);
        _images[key] = image;
        _trimImages();
      } else {
        _remember(_missing, key, _maxMisses);
      }
      notifyListeners();
    });
  }

  /// Decode cached PNG bytes to a display-ready [ui.Image].
  Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void _completeName(String key, String? name) {
    _nameRequested.remove(key);
    if (name != null && name.isNotEmpty) {
      _names.remove(key);
      _names[key] = name;
      _trimNames();
    } else {
      _remember(_nameMissing, key, _maxMisses);
    }
    notifyListeners();
  }

  void _trimImages() {
    while (_images.length > _maxImages) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest);
      if (image != null) _retireImage(image);
    }
  }

  void _trimNames() {
    while (_names.length > _maxNames) {
      _names.remove(_names.keys.first);
    }
  }

  void _remember(Set<String> set, String key, int cap) {
    set.remove(key);
    set.add(key);
    while (set.length > cap) {
      set.remove(set.first);
    }
  }

  void _retireImage(ui.Image image) {
    Timer(_imageRetireDelay, image.dispose);
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

  /// Drop every resolved icon/name as well — used when the backing cache is
  /// wiped, so tiles re-resolve instead of showing now-stale entries.
  void clearAll() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _names.clear();
    _missing.clear();
    _requested.clear();
    _nameMissing.clear();
    _nameRequested.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _missing.clear();
    _requested.clear();
    _names.clear();
    _nameMissing.clear();
    _nameRequested.clear();
    super.dispose();
  }
}
