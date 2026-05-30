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

  // Decoded, display-ready images. On Windows the source PNGs come from
  // DrawIconEx, which leaves the RGB premultiplied by alpha — encoded as
  // straight alpha that darkens every anti-aliased edge (the "fringe"). We
  // un-premultiply on decode so edges render clean.
  final Map<String, ui.Image> _images = {};
  final Set<String> _missing = {};
  final Set<String> _requested = {};

  final Map<String, String> _names = {};
  final Set<String> _nameMissing = {};
  final Set<String> _nameRequested = {};

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // Windows HICONs come back premultiplied; nothing else does.
  static bool get _needsUnpremultiply => !kIsWeb && Platform.isWindows;

  ui.Image? iconFor(String key) => _images[key];

  bool isMissing(String key) => _missing.contains(key);

  String? nameFor(String key) => _names[key];

  void request(String key) {
    if (key.isEmpty) return;
    if (_images.containsKey(key) ||
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
    if (bytes == null || bytes.isEmpty) {
      _requested.remove(key);
      _missing.add(key);
      notifyListeners();
      return;
    }
    _decode(bytes).then((image) {
      _requested.remove(key);
      if (image != null) {
        _images[key] = image;
      } else {
        _missing.add(key);
      }
      notifyListeners();
    });
  }

  /// Decode PNG bytes to a [ui.Image], un-premultiplying on Windows so
  /// DrawIconEx's premultiplied output doesn't darken anti-aliased edges.
  Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      if (!_needsUnpremultiply) return src;

      final data = await src.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) return src;
      final px = data.buffer.asUint8List();
      var touched = false;
      for (var i = 0; i < px.length; i += 4) {
        final a = px[i + 3];
        if (a == 0 || a == 255) continue;
        touched = true;
        px[i] = ((px[i] * 255 + a ~/ 2) ~/ a).clamp(0, 255);
        px[i + 1] = ((px[i + 1] * 255 + a ~/ 2) ~/ a).clamp(0, 255);
        px[i + 2] = ((px[i + 2] * 255 + a ~/ 2) ~/ a).clamp(0, 255);
      }
      if (!touched) return src;

      final descriptor = ui.ImageDescriptor.raw(
        await ui.ImmutableBuffer.fromUint8List(px),
        width: src.width,
        height: src.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final fixedCodec = await descriptor.instantiateCodec();
      final fixedFrame = await fixedCodec.getNextFrame();
      src.dispose();
      return fixedFrame.image;
    } catch (_) {
      return null;
    }
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
