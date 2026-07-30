import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:material_color_utilities/quantize/quantizer_celebi.dart';

class BackgroundAccentColor extends ChangeNotifier {
  BackgroundAccentColor._();

  static const _sampleSize = 112;

  Color? _color;
  String _path = '';
  bool _enabled = false;
  int _generation = 0;
  String? _cachedPath;
  Color? _cachedColor;
  bool _disposed = false;

  Color? get color => _color;

  static Future<BackgroundAccentColor> load({
    required bool enabled,
    required String imagePath,
  }) async {
    final value = BackgroundAccentColor._();
    await value.update(enabled: enabled, imagePath: imagePath);
    return value;
  }

  Future<void> update({
    required bool enabled,
    required String imagePath,
  }) async {
    final trimmed = imagePath.trim();
    final path = trimmed.isEmpty ? '' : File(trimmed).absolute.path;
    final shouldSample = enabled && path.isNotEmpty;
    if (_enabled == shouldSample && _path == path) return;

    _enabled = shouldSample;
    _path = path;
    final generation = ++_generation;
    if (!shouldSample) {
      _setColor(null);
      return;
    }

    if (_cachedPath == path && _cachedColor != null) {
      _setColor(_cachedColor);
      return;
    }
    _setColor(null);

    try {
      final sampled = await _sample(path);
      if (_disposed || generation != _generation) return;
      _cachedPath = path;
      _cachedColor = sampled;
      _setColor(sampled);
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _setColor(null);
      if (kDebugMode) debugPrint('background accent color unavailable: $error');
    }
  }

  Future<Color> _sample(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final scale = math.min(
          1.0,
          _sampleSize / math.max(descriptor.width, descriptor.height),
        );
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          final frame = await codec.getNextFrame();
          final image = frame.image;
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (data == null) throw StateError('无法读取背景图片像素');
            final bytes = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            final pixels = <int>[];
            for (var i = 0; i + 3 < bytes.length; i += 4) {
              if (bytes[i + 3] < 128) continue;
              pixels.add(
                0xff000000 |
                    (bytes[i] << 16) |
                    (bytes[i + 1] << 8) |
                    bytes[i + 2],
              );
            }
            if (pixels.isEmpty) throw StateError('背景图片没有可采样像素');
            final quantized = await QuantizerCelebi().quantize(pixels, 32);
            return Color(_representativeColor(quantized.colorToCount));
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  int _representativeColor(Map<int, int> colors) {
    int? best;
    var bestScore = -1.0;
    for (final entry in colors.entries) {
      final hct = Hct.fromInt(entry.key);
      if (hct.tone < 8 || hct.tone > 96) continue;
      final score = math.sqrt(entry.value) * math.max(hct.chroma, 8);
      if (score <= bestScore) continue;
      best = entry.key;
      bestScore = score;
    }
    if (best != null) return best;
    return colors.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  void _setColor(Color? value) {
    if (_disposed || value == _color) return;
    _color = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
