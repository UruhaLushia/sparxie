import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

/// Mirror of Rust's per-(target, level) log cache.
///
/// The authoritative ring buffer lives in Rust (`logs_state`) — Dart only
/// holds the entries currently being rendered. On every (re)subscribe, the
/// Rust stream replays its cache before live deltas, so this buffer
/// reseeds itself automatically without us having to track capacity here.
class LogBuffer extends ChangeNotifier {
  final List<rust.LogEntry> _entries = <rust.LogEntry>[];

  /// True while the user paused appending. The upstream stream keeps
  /// running; resume picks up the next event with no gap.
  final ValueNotifier<bool> paused = ValueNotifier(false);

  List<rust.LogEntry> get entries => _entries;
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  void add(rust.LogEntry entry) {
    if (paused.value) return;
    _entries.add(entry);
    notifyListeners();
  }

  /// Drop locally-rendered entries. The Rust cache is unaffected — call
  /// `rust.clearLogs(...)` separately if you want both wiped.
  void clearLocal() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void reset() {
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
