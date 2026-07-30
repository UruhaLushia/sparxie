import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

typedef LogWindowFetcher =
    Future<rust.LogWindow> Function(
      int offset,
      int limit,
      String level,
      String query,
      bool fromEnd,
    );

/// Rust owns the full log cache. Dart retains only the visible window plus a
/// small overscan requested by the screen.
class LogWindowNotifier extends ChangeNotifier {
  LogWindowNotifier({this.windowFetcher}) {
    paused.addListener(_onPausedChanged);
  }

  static const int _initialWindowSize = 30;
  static const int _windowOverscan = 12;
  static const int _windowRefetchMargin = 6;
  static const Duration _refetchDebounce = Duration(milliseconds: 50);

  LogWindowFetcher? windowFetcher;
  final ValueNotifier<bool> paused = ValueNotifier(false);

  List<rust.LogEntry> _rows = const [];
  int _rawTotal = 0;
  int _total = 0;
  int _offset = 0;
  int _limit = _initialWindowSize;
  String _level = 'info';
  String _query = '';
  bool _filterLoading = false;
  bool _following = true;
  bool _active = false;
  int _filterRevision = 0;
  BigInt _latestId = BigInt.zero;
  int _appendRevision = 0;
  BigInt? _latestAppendId;

  Timer? _refetchTimer;
  bool _refetching = false;
  bool _refetchAgain = false;
  bool _pendingImmediate = false;
  bool _pendingFromEnd = false;

  int get length => _total;
  bool get isEmpty => _rawTotal == 0;
  bool get filterLoading => _filterLoading;
  int get appendRevision => _appendRevision;
  BigInt? get latestAppendId => _latestAppendId;

  rust.LogEntry? rowAt(int index) {
    final local = index - _offset;
    if (local < 0 || local >= _rows.length) return null;
    return _rows[local];
  }

  void applyFrame(rust.LogsFrame frame) {
    if (frame.isInitial) _filterRevision++;
    final appended =
        !frame.isInitial && frame.total > 0 && frame.latestId != _latestId;
    _latestId = frame.latestId;
    _rawTotal = frame.total;

    if (_rawTotal == 0) {
      _cancelScheduledRefetch();
      _filterRevision++;
      _total = 0;
      _offset = 0;
      _rows = const [];
      _filterLoading = false;
      _latestAppendId = null;
      notifyListeners();
      return;
    }

    if (!_active || paused.value) return;
    if (appended) {
      _appendRevision++;
      _latestAppendId = frame.latestId;
    }
    _scheduleRefetch(force: frame.isInitial, fromEnd: _following);
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) {
      _cancelScheduledRefetch();
      _filterRevision++;
      _rows = const [];
      _latestAppendId = null;
      return;
    }
    if (_rawTotal == 0 || paused.value) return;
    _filterLoading = _rows.isEmpty;
    _scheduleRefetch(force: true, fromEnd: _following);
    notifyListeners();
  }

  void setFollowing(bool value) {
    if (_following == value) return;
    _following = value;
    if (!value) {
      _pendingFromEnd = false;
      return;
    }
    if (value && _active && !paused.value && _rawTotal > 0) {
      _scheduleRefetch(force: true, fromEnd: true);
    }
  }

  void setLevel(String value) {
    final level = value.isEmpty ? 'info' : value;
    if (level == _level) return;
    _level = level;
    _filterChanged();
  }

  void setQuery(String value) {
    final query = value.trim().toLowerCase();
    if (query == _query) return;
    _query = query;
    _filterChanged();
  }

  void ensureWindow(int firstIndex, int lastIndex) {
    if (!_active || paused.value || _filterLoading || _total == 0) return;
    final safeFirst = firstIndex.clamp(0, _total - 1).toInt();
    final safeLast = lastIndex.clamp(safeFirst, _total - 1).toInt();
    final desiredOffset = (safeFirst - _windowOverscan)
        .clamp(0, _total)
        .toInt();
    final end = (safeLast + 1 + _windowOverscan).clamp(0, _total).toInt();
    final desiredLimit = end - desiredOffset;
    final cachedEnd = _offset + _rows.length;
    final covered =
        _rows.isNotEmpty &&
        safeFirst >= _offset + _windowRefetchMargin &&
        safeLast < cachedEnd - _windowRefetchMargin;
    if (covered ||
        (desiredOffset == _offset &&
            desiredLimit == _limit &&
            _rows.isNotEmpty)) {
      return;
    }
    _offset = desiredOffset;
    _limit = math.max(desiredLimit, 1);
    _scheduleRefetch(force: true);
  }

  void clearLocal() {
    _cancelScheduledRefetch();
    _filterRevision++;
    _rawTotal = 0;
    _total = 0;
    _offset = 0;
    _rows = const [];
    _filterLoading = false;
    _latestId = BigInt.zero;
    _latestAppendId = null;
    notifyListeners();
  }

  void reset() {
    _cancelScheduledRefetch();
    _filterRevision++;
    _rawTotal = 0;
    _total = 0;
    _offset = 0;
    _limit = _initialWindowSize;
    _rows = const [];
    _filterLoading = false;
    _latestId = BigInt.zero;
    _appendRevision = 0;
    _latestAppendId = null;
    paused.value = false;
    notifyListeners();
  }

  void _filterChanged() {
    _filterRevision++;
    _total = 0;
    _offset = 0;
    _limit = _initialWindowSize;
    _rows = const [];
    _latestAppendId = null;
    _filterLoading = _rawTotal > 0;
    if (_active && !paused.value && _rawTotal > 0) {
      _scheduleRefetch(fromEnd: _following);
    }
    notifyListeners();
  }

  void _onPausedChanged() {
    _latestAppendId = null;
    if (paused.value) {
      _cancelScheduledRefetch();
      _filterRevision++;
      return;
    }
    if (!_active || _rawTotal == 0) return;
    _filterLoading = _rows.isEmpty;
    _scheduleRefetch(force: true, fromEnd: _following);
    notifyListeners();
  }

  void _scheduleRefetch({bool force = false, bool fromEnd = false}) {
    if (!_active || paused.value || _rawTotal == 0 || windowFetcher == null) {
      return;
    }
    _pendingImmediate |= force;
    _pendingFromEnd |= fromEnd;
    if (_refetching) {
      _refetchAgain = true;
      return;
    }
    if (force) {
      _refetchTimer?.cancel();
      _refetchTimer = null;
      final tail = _pendingFromEnd;
      _pendingFromEnd = false;
      _pendingImmediate = false;
      unawaited(_runRefetch(fromEnd: tail));
      return;
    }
    if (_refetchTimer != null) return;
    _refetchTimer = Timer(_refetchDebounce, () {
      _refetchTimer = null;
      final tail = _pendingFromEnd;
      _pendingFromEnd = false;
      _pendingImmediate = false;
      unawaited(_runRefetch(fromEnd: tail));
    });
  }

  Future<void> _runRefetch({required bool fromEnd}) async {
    if (_refetching) {
      _pendingFromEnd |= fromEnd;
      _refetchAgain = true;
      return;
    }
    _refetching = true;
    try {
      await _refetch(fromEnd: fromEnd);
    } finally {
      _refetching = false;
      if (_refetchAgain) {
        _refetchAgain = false;
        final immediate = _pendingImmediate;
        final tail = _pendingFromEnd;
        _pendingImmediate = false;
        _pendingFromEnd = false;
        if (immediate) {
          unawaited(_runRefetch(fromEnd: tail));
        } else {
          _scheduleRefetch(fromEnd: tail);
        }
      }
    }
  }

  Future<void> _refetch({required bool fromEnd}) async {
    final fetcher = windowFetcher;
    if (fetcher == null) return;
    final filterRevision = _filterRevision;
    final level = _level;
    final query = _query;
    final offset = _offset;
    final limit = math.max(_limit, 1);
    final rust.LogWindow window;
    try {
      window = await fetcher(offset, limit, level, query, fromEnd);
    } catch (_) {
      return;
    }
    if (!_active ||
        paused.value ||
        filterRevision != _filterRevision ||
        level != _level ||
        query != _query ||
        (fromEnd && !_following) ||
        (!fromEnd && (offset != _offset || limit != _limit))) {
      return;
    }
    _total = window.total;
    _offset = window.offset;
    _rows = window.rows;
    _filterLoading = false;
    notifyListeners();
  }

  void _cancelScheduledRefetch() {
    _refetchTimer?.cancel();
    _refetchTimer = null;
    _refetchAgain = false;
    _pendingImmediate = false;
    _pendingFromEnd = false;
  }

  @override
  void dispose() {
    _cancelScheduledRefetch();
    _active = false;
    _filterRevision++;
    paused.removeListener(_onPausedChanged);
    paused.dispose();
    _rows = const [];
    super.dispose();
  }
}
