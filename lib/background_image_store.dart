import 'dart:io';
import 'dart:ui' as ui;

import 'app_paths.dart';

class BackgroundImageStore {
  BackgroundImageStore._();

  static final _imageSizes = <String, ui.Size>{};
  static final _pendingImageSizes = <String, Future<ui.Size>>{};

  static const supportedExtensions = {
    'bmp',
    'gif',
    'heic',
    'heif',
    'jpeg',
    'jpg',
    'png',
    'webp',
  };

  static Future<String> importStream(
    String sourceName,
    Stream<List<int>> bytes,
  ) async {
    final extension = _extension(sourceName);
    if (!supportedExtensions.contains(extension)) {
      throw const FileSystemException('不支持的图片格式');
    }
    final dir = await _directory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    final sink = file.openWrite();
    try {
      await sink.addStream(bytes);
      await sink.close();
      return file.path;
    } catch (_) {
      await sink.close().catchError((_) {});
      await file.delete().catchError((_) => file);
      rethrow;
    }
  }

  static ui.Size? cachedImageSize(String path) => _imageSizes[path];

  static Future<ui.Size> imageSize(String path) {
    final cached = _imageSizes[path];
    if (cached != null) return Future.value(cached);
    return _pendingImageSizes.putIfAbsent(path, () => _readImageSize(path));
  }

  static Future<ui.Size> _readImageSize(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final size = ui.Size(
            descriptor.width.toDouble(),
            descriptor.height.toDouble(),
          );
          _imageSizes[path] = size;
          return size;
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } finally {
      _pendingImageSizes.remove(path);
    }
  }

  static Future<void> deleteManaged(String path) async {
    if (path.trim().isEmpty) return;
    final dir = (await _directory()).absolute.path;
    final file = File(path).absolute;
    if (file.parent.path != dir) return;
    _forgetImage(file.path);
    if (!await file.exists()) return;
    await file.delete();
  }

  static Future<void> cleanup(String keepPath) async {
    final dir = await _directory();
    final keep = keepPath.trim().isEmpty ? null : File(keepPath).absolute.path;
    await for (final entity in dir.list()) {
      if (entity is! File || entity.absolute.path == keep) continue;
      await entity.delete().catchError((_) => entity);
      _forgetImage(entity.path);
    }
  }

  static void _forgetImage(String path) {
    _imageSizes.remove(path);
    _imageSizes.remove(File(path).absolute.path);
    _pendingImageSizes.remove(path);
    _pendingImageSizes.remove(File(path).absolute.path);
  }

  static Future<Directory> _directory() async {
    final config = await AppPaths.configDir();
    final dir = Directory('${config.path}${Platform.pathSeparator}backgrounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _extension(String name) {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }
}
