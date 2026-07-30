import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

/// Verbose mirror of Rust's per-target log cache. Capacity is measured by
/// entries visible at Info level, so Debug/Trace entries do not consume it.
class LogBuffer extends ChangeNotifier {
  LogBuffer({int infoCapacity = defaultInfoCapacity})
    : _infoCapacity = infoCapacity > 0 ? infoCapacity : 1;

  static const int defaultInfoCapacity = 500;

  final List<rust.LogEntry> _entries = <rust.LogEntry>[];
  late final UnmodifiableListView<rust.LogEntry> entries = UnmodifiableListView(
    _entries,
  );

  final ValueNotifier<bool> paused = ValueNotifier(false);
  int _infoCapacity;
  int _infoEntries = 0;

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  void setInfoCapacity(int value) {
    final next = value > 0 ? value : 1;
    if (next == _infoCapacity) return;
    _infoCapacity = next;
    if (_trimToCapacity()) notifyListeners();
  }

  void addAll(List<rust.LogEntry> entries) {
    if (paused.value) return;
    if (entries.isEmpty) return;
    _entries.addAll(entries);
    _infoEntries += entries.where(_countsTowardInfoCapacity).length;
    _trimToCapacity();
    notifyListeners();
  }

  void replaceAll(List<rust.LogEntry> entries) {
    _entries
      ..clear()
      ..addAll(entries);
    _infoEntries = entries.where(_countsTowardInfoCapacity).length;
    _trimToCapacity();
    notifyListeners();
  }

  bool _trimToCapacity() {
    var overflow = _infoEntries - _infoCapacity;
    if (overflow <= 0) return false;
    var removeCount = 0;
    while (removeCount < _entries.length && overflow > 0) {
      if (_countsTowardInfoCapacity(_entries[removeCount])) {
        overflow--;
        _infoEntries--;
      }
      removeCount++;
    }
    _entries.removeRange(0, removeCount);
    return true;
  }

  /// Drop the rendered list. The Rust ring buffer is untouched — call
  /// `rust.clearLogs(...)` to wipe both.
  void clearLocal() {
    if (_entries.isEmpty) return;
    _entries.clear();
    _infoEntries = 0;
    notifyListeners();
  }

  void reset() {
    if (_entries.isEmpty && !paused.value) return;
    _entries.clear();
    _infoEntries = 0;
    paused.value = false;
    notifyListeners();
  }

  @override
  void dispose() {
    paused.dispose();
    _entries.clear();
    _infoEntries = 0;
    super.dispose();
  }
}

bool _countsTowardInfoCapacity(rust.LogEntry entry) =>
    switch (entry.level.toLowerCase()) {
      'trace' || 'debug' || 'silent' => false,
      _ => true,
    };
