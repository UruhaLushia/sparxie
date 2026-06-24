import 'dart:io';

import 'package:flutter/services.dart';

import 'app_paths.dart';
import 'app_prefs.dart';

class ImportedFonts {
  ImportedFonts._();

  static const _supportedExtensions = {'ttf', 'otf', 'ttc', 'otc'};
  static final _loadedFamilies = <String>{};

  static Future<void> loadAll(Iterable<ImportedFont> fonts) async {
    for (final font in fonts) {
      try {
        await load(font);
      } catch (_) {
        // Ignore stale or corrupt imported fonts during startup.
      }
    }
  }

  static Future<void> cleanup(Iterable<ImportedFont> fonts) async {
    final keep = {
      for (final font in fonts)
        if (font.path.trim().isNotEmpty) File(font.path).absolute.path,
    };
    final dir = await _fontDir();
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (keep.contains(entity.absolute.path)) continue;
      await entity.delete().catchError((_) => entity);
    }
  }

  static Future<void> load(ImportedFont font) async {
    if (_loadedFamilies.contains(font.family)) return;
    final file = File(font.path);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final loader = FontLoader(font.family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(font.family);
  }

  static Future<void> delete(ImportedFont font) async {
    final file = File(font.path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> deletePickerCache(String path) async {
    if (!Platform.isAndroid || path.trim().isEmpty) return;
    final file = File(path);
    try {
      if (!await file.exists()) return;
      final cache = (await AppPaths.cacheDir()).absolute.path;
      final absolute = file.absolute.path;
      final parent = file.parent;
      final parentName = _fileName(parent.path);
      final isPluginCopy =
          parent.parent.absolute.path == cache && _isUuid(parentName);
      if (absolute == cache || !isPluginCopy) {
        return;
      }
      await file.delete();
      if (await parent.exists()) {
        final empty = await parent.list().isEmpty;
        if (empty) await parent.delete();
      }
    } catch (_) {}
  }

  static Future<ImportedFont> importFile(
    String sourcePath, {
    required Set<String> reservedFamilies,
  }) async {
    final source = File(sourcePath);
    try {
      if (!await source.exists()) {
        throw const FileSystemException('字体文件不存在');
      }

      final name = _fileName(sourcePath);
      final extension = _extension(name);
      if (!_supportedExtensions.contains(extension)) {
        throw FileSystemException('不支持的字体格式', sourcePath);
      }

      final bytes = await source.readAsBytes();
      return importBytes(
        name,
        bytes,
        reservedFamilies: reservedFamilies,
        sourcePath: sourcePath,
      );
    } finally {
      await deletePickerCache(sourcePath);
    }
  }

  static Future<ImportedFont> importBytes(
    String sourceName,
    List<int> bytes, {
    required Set<String> reservedFamilies,
    String? sourcePath,
  }) async {
    final name = _fileName(sourceName);
    final extension = _extension(name);
    if (!_supportedExtensions.contains(extension)) {
      throw FileSystemException('不支持的字体格式', sourcePath ?? sourceName);
    }

    final dir = await _fontDir();
    final target = File(
      '${dir.path}${Platform.pathSeparator}${_targetName(name)}',
    );
    final font = ImportedFont(
      family: _uniqueFamily(_familyName(name), reservedFamilies),
      path: target.path,
    );
    try {
      await target.writeAsBytes(bytes, flush: true);
      await load(font);
    } catch (_) {
      await target.delete().catchError((_) => target);
      rethrow;
    }
    return font;
  }

  static Future<Directory> _fontDir() async {
    final config = await AppPaths.configDir();
    final dir = Directory('${config.path}${Platform.pathSeparator}fonts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

  static String _extension(String name) {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }

  static String _targetName(String name) {
    final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return '${DateTime.now().microsecondsSinceEpoch}_$clean';
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static String _familyName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot < 0 ? name : name.substring(0, dot);
    final clean = base.trim().isEmpty ? 'Imported Font' : base.trim();
    return '导入：$clean';
  }

  static String _uniqueFamily(String base, Set<String> reserved) {
    if (!reserved.contains(base)) return base;
    var index = 2;
    while (reserved.contains('$base $index')) {
      index++;
    }
    return '$base $index';
  }
}
