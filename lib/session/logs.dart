import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

/// Mirror of Rust's per-(target, level) log cache. Rust owns the ring
/// buffer; this just renders what each subscribe replays + delta-streams.
class LogBuffer extends ChangeNotifier {
  final List<rust.LogEntry> _entries = <rust.LogEntry>[];
  late final UnmodifiableListView<rust.LogEntry> entries =
      UnmodifiableListView(_entries);

  final ValueNotifier<bool> paused = ValueNotifier(false);

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  void add(rust.LogEntry entry) {
    if (paused.value) return;
    _entries.add(entry);
    notifyListeners();
  }

  /// Drop the rendered list. The Rust ring buffer is untouched — call
  /// `rust.clearLogs(...)` to wipe both.
  void clearLocal() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void reset() {
    if (_entries.isEmpty && !paused.value) return;
    _entries.clear();
    paused.value = false;
    notifyListeners();
  }

  @override
  void dispose() {
    paused.dispose();
    _entries.clear();
    super.dispose();
  }
}
