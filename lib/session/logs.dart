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
      BigInt? anchorId,
    );

/// Rust owns the full log cache. Dart retains only the visible window plus a
/// small overscan requested by the screen.
class LogWindowNotifier extends ChangeNotifier {
  LogWindowNotifier({this.windowFetcher}) {
    paused.addListener(_onPausedChanged);
  }

  static const int _initialWindowSize = 30;
  static const int _windowOverscan = 20;
  static const int _windowRefetchMargin = 10;
  static const Duration _refetchDebounce = Duration(milliseconds: 50);

  LogWindowFetcher? windowFetcher;
  final ValueNotifier<bool> paused = ValueNotifier(false);

  List<rust.LogEntry> _rows = const [];
  int _rawTotal = 0;
  int _total = 0;
  int _offset = 0;
  int _requestedOffset = 0;
  int _requestedLimit = _initialWindowSize;
  String _level = 'info';
  String _query = '';
  bool _filterLoading = false;
  bool _following = true;
  bool _active = false;
  bool _notifyOnNextWindow = false;
  int _filterRevision = 0;
  BigInt _latestId = BigInt.zero;
  BigInt? _anchorId;
  int _appendRevision = 0;
  BigInt? _latestAppendId;
  int _frameRevision = 0;
  int _windowFrameRevision = -1;
  int _windowRevision = 0;

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
  int get windowRevision => _windowRevision;

  /// Returns the current window revision when a refresh is queued; otherwise
  /// returns null.
  int? refreshWindow() {
    if (!_active || paused.value || _rawTotal == 0 || windowFetcher == null) {
      return null;
    }
    final pending = _refetchTimer != null || _refetching || _refetchAgain;
    if (!pending && _windowFrameRevision == _frameRevision) return null;
    final revision = _windowRevision;
    _notifyOnNextWindow = true;
    _scheduleRefetch(force: true, fromEnd: _following);
    return revision;
  }

  rust.LogEntry? rowAt(int index) {
    final local = index - _offset;
    if (local < 0 || local >= _rows.length) return null;
    return _rows[local];
  }

  int? indexOfId(BigInt id) {
    final local = _rows.indexWhere((entry) => entry.id == id);
    return local < 0 ? null : _offset + local;
  }

  void applyFrame(rust.LogsFrame frame) {
    _frameRevision++;
    if (frame.isInitial) _filterRevision++;
    final appended =
        !frame.isInitial && frame.total > 0 && frame.latestId != _latestId;
    _latestId = frame.latestId;
    _rawTotal = frame.total;

    if (_rawTotal == 0) {
      _cancelScheduledRefetch();
      _filterRevision++;
      _clearWindow();
      _completeWindowRefresh(_frameRevision);
      notifyListeners();
      return;
    }

    if (!_active || paused.value) return;
    if (appended) {
      _appendRevision++;
      _latestAppendId = _following ? frame.latestId : null;
    }
    _scheduleRefetch(force: frame.isInitial, fromEnd: _following);
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) {
      _cancelScheduledRefetch();
      _filterRevision++;
      _notifyOnNextWindow = false;
      _latestAppendId = null;
      return;
    }
    if (_rawTotal == 0 || paused.value) return;
    _notifyOnNextWindow = true;
    _filterLoading = _rows.isEmpty;
    _scheduleRefetch(force: true, fromEnd: _following);
    if (_filterLoading) notifyListeners();
  }

  void setFollowing(bool value) {
    if (_following == value) return;
    _following = value;
    if (!value) {
      _pendingFromEnd = false;
      _latestAppendId = null;
      return;
    }
    _anchorId = null;
    if (value && _active && !paused.value && _rawTotal > 0) {
      _scheduleRefetch(force: true, fromEnd: true);
    }
  }

  void setAnchor(BigInt? value) {
    if (_anchorId == value) return;
    _anchorId = value;
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
        (_offset == 0 || safeFirst >= _offset + _windowRefetchMargin) &&
        (cachedEnd >= _total || safeLast < cachedEnd - _windowRefetchMargin);
    if (covered ||
        (desiredOffset == _offset &&
            desiredLimit == _rows.length &&
            _rows.isNotEmpty)) {
      return;
    }
    _requestedOffset = desiredOffset;
    _requestedLimit = math.max(desiredLimit, 1);
    _scheduleRefetch();
  }

  void clearLocal() {
    _cancelScheduledRefetch();
    _filterRevision++;
    _rawTotal = 0;
    _latestId = BigInt.zero;
    _clearWindow();
    _frameRevision++;
    _completeWindowRefresh(_frameRevision);
    notifyListeners();
  }

  void reset() {
    _cancelScheduledRefetch();
    _filterRevision++;
    _rawTotal = 0;
    _latestId = BigInt.zero;
    _appendRevision = 0;
    _clearWindow(resetRequestLimit: true);
    _frameRevision++;
    _completeWindowRefresh(_frameRevision);
    paused.value = false;
    notifyListeners();
  }

  void _filterChanged() {
    _filterRevision++;
    _clearWindow(resetRequestLimit: true);
    _windowFrameRevision = -1;
    _filterLoading = _rawTotal > 0;
    if (_active && !paused.value && _rawTotal > 0) {
      _scheduleRefetch(fromEnd: _following);
    }
    notifyListeners();
  }

  void _clearWindow({bool resetRequestLimit = false}) {
    _total = 0;
    _offset = 0;
    _requestedOffset = 0;
    if (resetRequestLimit) _requestedLimit = _initialWindowSize;
    _rows = const [];
    _filterLoading = false;
    _notifyOnNextWindow = false;
    _anchorId = null;
    _latestAppendId = null;
  }

  void _completeWindowRefresh(int frameRevision) {
    _windowFrameRevision = frameRevision;
    _windowRevision++;
  }

  void _onPausedChanged() {
    _latestAppendId = null;
    if (paused.value) {
      _cancelScheduledRefetch();
      _filterRevision++;
      _notifyOnNextWindow = false;
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
    final frameRevision = _frameRevision;
    final anchorId = fromEnd ? null : _anchorId;
    final offset = _requestedOffset;
    final limit = math.max(_requestedLimit, 1);
    bool requestIsCurrent() =>
        _active &&
        !paused.value &&
        filterRevision == _filterRevision &&
        level == _level &&
        query == _query &&
        (!fromEnd || _following) &&
        (fromEnd || (offset == _requestedOffset && limit == _requestedLimit));
    final rust.LogWindow window;
    try {
      window = await fetcher(offset, limit, level, query, fromEnd, anchorId);
    } catch (_) {
      if (!requestIsCurrent()) return;
      _windowRevision++;
      final shouldNotify = _notifyOnNextWindow;
      _notifyOnNextWindow = false;
      if (shouldNotify) notifyListeners();
      return;
    }
    if (!requestIsCurrent()) return;
    final changed =
        _filterLoading ||
        _total != window.total ||
        _offset != window.offset ||
        !listEquals(_rows, window.rows);
    _total = window.total;
    _offset = window.offset;
    if (offset == _requestedOffset && limit == _requestedLimit) {
      _requestedOffset = window.offset;
    }
    _rows = window.rows;
    _filterLoading = false;
    _completeWindowRefresh(frameRevision);
    final shouldNotify = changed || _notifyOnNextWindow;
    _notifyOnNextWindow = false;
    if (shouldNotify) notifyListeners();
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
    _notifyOnNextWindow = false;
    _filterRevision++;
    paused.removeListener(_onPausedChanged);
    paused.dispose();
    _rows = const [];
    super.dispose();
  }
}
