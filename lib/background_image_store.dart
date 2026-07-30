import 'dart:io';
import 'dart:ui' as ui;

import 'app_paths.dart';

class BackgroundImageStore {
  BackgroundImageStore._();

  static const _managedPrefix = 'managed:';
  static final _imageSizes = <String, ui.Size>{};
  static final _pendingImageSizes = <String, Future<ui.Size>>{};
  static Directory? _managedDirectory;

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

  static Future<void> initialize() async {
    await _directory();
  }

  static String resolveReference(String reference) {
    final value = reference.trim();
    if (!value.startsWith(_managedPrefix)) return value;
    final name = value.substring(_managedPrefix.length);
    final dir = _managedDirectory;
    if (dir == null || !_isManagedName(name)) return '';
    return File('${dir.path}${Platform.pathSeparator}$name').absolute.path;
  }

  static String referenceForPath(String path) {
    final value = path.trim();
    if (value.isEmpty) return '';
    final dir = _managedDirectory;
    if (dir == null) return value;
    final file = File(value).absolute;
    if (file.parent.path != dir.absolute.path) return value;
    final name = _basename(file.path);
    return _isManagedName(name) ? '$_managedPrefix$name' : value;
  }

  static Future<String> normalizeReference(String storedReference) async {
    final reference = storedReference.trim();
    if (reference.isEmpty) return '';
    await initialize();
    if (reference.startsWith(_managedPrefix)) {
      final name = reference.substring(_managedPrefix.length);
      return _isManagedName(name) ? '$_managedPrefix$name' : '';
    }

    final storedFile = File(reference);
    if (await storedFile.exists()) {
      return referenceForPath(storedFile.absolute.path);
    }

    // Older versions persisted the full iOS container path. App upgrades may
    // replace that root while retaining the managed directory and filename.
    if (_basename(storedFile.parent.path) != 'backgrounds') return reference;
    final name = _basename(storedFile.path);
    if (!_isManagedName(name)) return reference;
    final dir = await _directory();
    final candidate = File('${dir.path}${Platform.pathSeparator}$name');
    return await candidate.exists() ? '$_managedPrefix$name' : reference;
  }

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
    final trimmed = keepPath.trim();
    String? keep;
    if (trimmed.isNotEmpty) {
      final keepFile = File(trimmed);
      // A stale absolute path must not make cleanup delete the recoverable
      // contents of the current managed directory.
      if (!await keepFile.exists()) return;
      keep = keepFile.absolute.path;
    }
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
    final cached = _managedDirectory;
    if (cached != null) return cached;
    final config = await AppPaths.configDir();
    final dir = Directory(
      '${config.path}${Platform.pathSeparator}backgrounds',
    ).absolute;
    if (!await dir.exists()) await dir.create(recursive: true);
    _managedDirectory = dir;
    return dir;
  }

  static String _extension(String name) {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }

  static String _basename(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  static bool _isManagedName(String name) =>
      name.isNotEmpty && name != '.' && name != '..' && _basename(name) == name;
}
