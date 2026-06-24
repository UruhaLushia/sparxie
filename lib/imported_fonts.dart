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

  static Future<ImportedFont> importFile(
    String sourcePath, {
    required Set<String> reservedFamilies,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('字体文件不存在');
    }

    final name = _fileName(sourcePath);
    final extension = _extension(name);
    if (!_supportedExtensions.contains(extension)) {
      throw FileSystemException('不支持的字体格式', sourcePath);
    }

    final dir = await _fontDir();
    final target = File(
      '${dir.path}${Platform.pathSeparator}${_targetName(name)}',
    );
    await source.copy(target.path);

    final font = ImportedFont(
      family: _uniqueFamily(_familyName(name), reservedFamilies),
      path: target.path,
    );
    try {
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

  static String _familyName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot < 0 ? name : name.substring(0, dot);
    final clean = base.trim().isEmpty ? 'Imported Font' : base.trim();
    return '导入: $clean';
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
