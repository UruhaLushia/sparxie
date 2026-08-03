import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../rust_api.dart' as rust;

/// In-memory cache of resolved process icons + app names, keyed by the
/// platform's process id (exec path on desktop, package name on Android).
/// Rust owns the on-disk cache; this dedups requests and notifies listeners
/// so a tile repaints once its icon lands. Android resolves via a Kotlin
/// MethodChannel (PackageManager), then persists through Rust's disk cache.
class ProcessIconCache extends ChangeNotifier {
  static const _channel = MethodChannel('zip.atri.sparxie/process_icons');
  static const _maxImages = 128;
  static const _maxNames = 512;
  static const _maxMisses = 512;
  static const _maxConcurrentImageRequests = 5;
  static const _maxConcurrentNameRequests = 8;
  static const _imageRetireDelay = Duration(milliseconds: 500);

  // Decoded, display-ready images. Encoded source bytes stay in Rust's disk
  // cache; Flutter only retains pixels at the requested display size.
  final LinkedHashMap<String, ui.Image> _images =
      LinkedHashMap<String, ui.Image>();
  final Set<String> _missing = {};
  final Set<String> _requested = {};
  final Queue<({int generation, Future<void> Function() run})>
  _imageRequestQueue = Queue();
  int _activeImageRequests = 0;
  int _imageGeneration = 0;

  final LinkedHashMap<String, String> _names = LinkedHashMap<String, String>();
  final Set<String> _nameMissing = {};
  final Set<String> _nameRequested = {};
  final Queue<({int generation, Future<void> Function() run})>
  _nameRequestQueue = Queue();
  int _activeNameRequests = 0;
  int _nameGeneration = 0;
  int? _notifyFrameCallback;

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get _isSupported => !kIsWeb && !Platform.isIOS;

  ui.Image? iconFor(String key, {int? size, int? decodeSize}) {
    final imageKey = _imageKey(key, size, decodeSize);
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

  void request(String key, {int? size, int? decodeSize}) {
    if (!_isSupported) return;
    if (key.isEmpty) return;
    final imageKey = _imageKey(key, size, decodeSize);
    if (_images.containsKey(imageKey) ||
        _missing.contains(imageKey) ||
        _requested.contains(imageKey)) {
      return;
    }
    _requested.add(imageKey);
    final generation = _imageGeneration;
    _enqueueImageRequest(generation, () async {
      try {
        final bytes = await (_isAndroid
            ? _resolveAndroid(key)
            : rust.fetchProcessIcon(path: key, size: size));
        await _complete(
          imageKey,
          bytes,
          decodeSize: decodeSize,
          generation: generation,
        );
      } catch (_) {
        if (generation == _imageGeneration) {
          _requested.remove(imageKey);
          _remember(_missing, imageKey, _maxMisses);
          _scheduleNotify();
        }
      }
    });
  }

  void _enqueueImageRequest(int generation, Future<void> Function() run) {
    _imageRequestQueue.add((generation: generation, run: run));
    _drainImageRequests();
  }

  void _drainImageRequests() {
    while (_activeImageRequests < _maxConcurrentImageRequests &&
        _imageRequestQueue.isNotEmpty) {
      final request = _imageRequestQueue.removeFirst();
      if (request.generation != _imageGeneration) continue;
      _activeImageRequests++;
      request.run().whenComplete(() {
        _activeImageRequests--;
        _drainImageRequests();
      });
    }
  }

  String _imageKey(String key, int? size, int? decodeSize) {
    final fetchKey = size == null ? key : '$key@$size';
    return decodeSize == null ? fetchKey : '$fetchKey#$decodeSize';
  }

  void requestName(String key) {
    if (!_isSupported) return;
    if (key.isEmpty) return;
    if (_names.containsKey(key) ||
        _nameMissing.contains(key) ||
        _nameRequested.contains(key)) {
      return;
    }
    _nameRequested.add(key);
    final generation = _nameGeneration;
    _enqueueNameRequest(generation, () async {
      try {
        final name = await (_isAndroid
            ? _resolveNameAndroid(key)
            : rust.fetchProcessName(path: key));
        _completeName(key, name, generation);
      } catch (_) {
        if (generation != _nameGeneration) return;
        _nameRequested.remove(key);
        _remember(_nameMissing, key, _maxMisses);
        _scheduleNotify();
      }
    });
  }

  void _enqueueNameRequest(int generation, Future<void> Function() run) {
    _nameRequestQueue.add((generation: generation, run: run));
    _drainNameRequests();
  }

  void _drainNameRequests() {
    while (_activeNameRequests < _maxConcurrentNameRequests &&
        _nameRequestQueue.isNotEmpty) {
      final request = _nameRequestQueue.removeFirst();
      if (request.generation != _nameGeneration) continue;
      _activeNameRequests++;
      request.run().whenComplete(() {
        _activeNameRequests--;
        _drainNameRequests();
      });
    }
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

  Future<void> _complete(
    String key,
    Uint8List? bytes, {
    required int generation,
    int? decodeSize,
  }) async {
    if (generation != _imageGeneration) return;
    if (bytes == null || bytes.isEmpty) {
      _requested.remove(key);
      _remember(_missing, key, _maxMisses);
      _scheduleNotify();
      return;
    }
    final image = await _decode(bytes, targetSize: decodeSize);
    if (generation != _imageGeneration) {
      image?.dispose();
      return;
    }
    _requested.remove(key);
    if (image != null) {
      final previous = _images.remove(key);
      if (previous != null) _retireImage(previous);
      _images[key] = image;
      _trimImages();
    } else {
      _remember(_missing, key, _maxMisses);
    }
    _scheduleNotify();
  }

  /// Decode cached PNG bytes to a display-ready [ui.Image].
  Future<ui.Image?> _decode(Uint8List bytes, {int? targetSize}) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetSize,
        targetHeight: targetSize,
      );
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  void _completeName(String key, String? name, int generation) {
    if (generation != _nameGeneration) return;
    _nameRequested.remove(key);
    if (name != null && name.isNotEmpty) {
      _names.remove(key);
      _names[key] = name;
      _trimNames();
    } else {
      _remember(_nameMissing, key, _maxMisses);
    }
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (!hasListeners || _notifyFrameCallback != null) return;
    _notifyFrameCallback = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _notifyFrameCallback = null;
      if (hasListeners) notifyListeners();
    });
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
    _imageGeneration++;
    _imageRequestQueue.clear();
    _nameGeneration++;
    _nameRequestQueue.clear();
    _requested.clear();
    _nameMissing.clear();
    _nameRequested.clear();
    rust.resetProcessIconMisses();
    _scheduleNotify();
  }

  /// Release decoded pixels while keeping names, misses and the disk cache.
  void clearImages({bool preserveLive = false}) {
    if (preserveLive && hasListeners) return;
    if (_images.isEmpty && _requested.isEmpty) return;
    _imageGeneration++;
    _imageRequestQueue.clear();
    _requested.clear();
    for (final image in _images.values) {
      _retireImage(image);
    }
    _images.clear();
    _scheduleNotify();
  }

  /// Drop every resolved icon/name as well — used when the backing cache is
  /// wiped, so tiles re-resolve instead of showing now-stale entries.
  void clearAll() {
    _imageGeneration++;
    _nameGeneration++;
    _imageRequestQueue.clear();
    _nameRequestQueue.clear();
    for (final image in _images.values) {
      _retireImage(image);
    }
    _images.clear();
    _names.clear();
    _missing.clear();
    _requested.clear();
    _nameMissing.clear();
    _nameRequested.clear();
    _scheduleNotify();
  }

  @override
  void dispose() {
    _imageGeneration++;
    _nameGeneration++;
    _imageRequestQueue.clear();
    _nameRequestQueue.clear();
    final notifyFrameCallback = _notifyFrameCallback;
    if (notifyFrameCallback != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(notifyFrameCallback);
      _notifyFrameCallback = null;
    }
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
