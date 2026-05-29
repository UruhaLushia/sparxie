import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// Human-readable JSON config store, replacing shared_preferences.
///
/// One pretty-printed `config.json` lives in the app support directory with
/// nested sections (`controllers`, `prefs`, `window`). Each consumer reads
/// and mutates its own section through [section]; [scheduleSave] coalesces
/// bursts of writes into a single debounced flush.
class JsonStore {
  JsonStore._(this._file, this._root);

  /// In-memory store with no backing file — for tests. Saves are no-ops.
  @visibleForTesting
  JsonStore.memory()
      : _file = null,
        _root = {};

  final File? _file;
  final Map<String, dynamic> _root;
  Timer? _saveTimer;

  static const _saveDebounce = Duration(milliseconds: 200);

  static Future<JsonStore> load() async {
    final dir = await AppPaths.configDir();
    final file = File('${dir.path}/config.json');
    Map<String, dynamic> root = {};
    try {
      if (await file.exists()) {
        final text = await file.readAsString();
        if (text.trim().isNotEmpty) {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) root = decoded;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('config load failed: $e');
    }
    return JsonStore._(file, root);
  }

  /// The mutable map for a top-level section, created on first access.
  Map<String, dynamic> section(String name) {
    final existing = _root[name];
    if (existing is Map<String, dynamic>) return existing;
    final created = <String, dynamic>{};
    _root[name] = created;
    return created;
  }

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    final file = _file;
    if (file == null) return;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(encoder.convert(_root), flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      if (kDebugMode) debugPrint('config save failed: $e');
    }
  }
}
