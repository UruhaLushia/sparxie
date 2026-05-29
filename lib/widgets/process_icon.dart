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
    cache.request(key);
    final fallback = key.isEmpty
        ? 'assets/process_icons/device.png'
        : _defaultAppAsset;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final bytes = cache.iconFor(key);
        return SizedBox.square(
          dimension: size,
          child: bytes != null
              ? Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => _DefaultIcon(asset: fallback),
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
    return Image.asset(asset, fit: BoxFit.contain, gaplessPlayback: true);
  }
}
