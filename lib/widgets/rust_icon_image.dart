import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../rust_api.dart' as rust;

/// An [ImageProvider] that resolves a proxy-group icon URL through the Rust
/// disk cache (`fetchIcon`) instead of the network. Flutter's [ImageCache]
/// sits on top, so a repeat build is an in-memory hit, the first build per
/// launch a disk hit, and only a true cold miss touches the network.
@immutable
class RustIconImage extends ImageProvider<RustIconImage> {
  const RustIconImage(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  @override
  Future<RustIconImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<RustIconImage>(this);

  @override
  ImageStreamCompleter loadImage(
    RustIconImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      _load(key, decode),
      informationCollector: () => [DiagnosticsProperty('URL', url)],
    );
  }

  Future<ImageInfo> _load(
    RustIconImage key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await rust.fetchIcon(url: key.url);
    if (bytes.isEmpty) {
      throw StateError('icon fetch returned no bytes for $url');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    try {
      final frame = await codec.getNextFrame();
      return ImageInfo(image: frame.image, scale: key.scale);
    } finally {
      codec.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RustIconImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'RustIconImage("$url", scale: $scale)';
}
