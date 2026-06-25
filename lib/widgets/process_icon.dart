import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../session.dart';

/// Leading icon for a connection row. Requests resolution lazily and
/// repaints when the cache fills; falls back to the bundled default icons
/// (Sparkle's artwork) — a generic app icon, or a device icon when there's
/// no owning process.
class ProcessIcon extends StatelessWidget {
  const ProcessIcon({
    super.key,
    required this.cache,
    required this.process,
    required this.processPath,
    this.size = 44,
  });

  final ProcessIconCache cache;
  final String process;
  final String processPath;
  final double size;

  static const _desktopIconSize = 256;

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // Android keys by package name (mihomo's `process`), desktop by exec path.
  String get _key => _isAndroid ? process : processPath;

  static String get _defaultAppAsset {
    if (_isAndroid) return 'assets/process_icons/app.png';
    if (kIsWeb) return 'assets/process_icons/app.png';
    return Platform.isWindows
        ? 'assets/process_icons/windows.png'
        : 'assets/process_icons/app.png';
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final targetSize = _isAndroid ? null : _desktopIconSize;
    final decodeSize = _isAndroid
        ? null
        : (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    cache.request(key, size: targetSize, decodeSize: decodeSize);
    final fallback = key.isEmpty
        ? 'assets/process_icons/device.png'
        : _defaultAppAsset;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final image = cache.iconFor(
          key,
          size: targetSize,
          decodeSize: decodeSize,
        );
        return SizedBox.square(
          dimension: size,
          child: image != null
              ? RawImage(
                  image: image,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                )
              : _DefaultIcon(asset: fallback),
        );
      },
    );
  }
}

class _DefaultIcon extends StatelessWidget {
  const _DefaultIcon({required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
  }
}
