import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

/// Mirror of Rust's per-(target, level) log cache. Rust owns the ring
/// buffer; this just renders what each subscribe replays + delta-streams.
class LogBuffer extends ChangeNotifier {
  static const int maxEntries = 500;

  final List<rust.LogEntry> _entries = <rust.LogEntry>[];
  late final UnmodifiableListView<rust.LogEntry> entries = UnmodifiableListView(
    _entries,
  );

  final ValueNotifier<bool> paused = ValueNotifier(false);

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  void addAll(List<rust.LogEntry> entries) {
    if (paused.value) return;
    if (entries.isEmpty) return;
    _entries.addAll(entries);
    final overflow = _entries.length - maxEntries;
    if (overflow > 0) _entries.removeRange(0, overflow);
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
