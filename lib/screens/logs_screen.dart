import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../rust_api.dart' as rust;
import '../session.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/app_background.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/logs_settings_menu.dart';
import '../widgets/page_body_transition.dart';
import '../widgets/route_app_bar.dart';

/// Renders a small window into the Rust-owned log cache. The backend keeps
/// collecting while this page is inactive; row payloads are fetched only for
/// the visible range and its overscan.
class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
  });

  final ctl.ControllerStore store;
  final AppPrefs prefs;
  final MihomoSession session;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _baseLevels = ['info', 'debug', 'warning', 'error', 'silent'];
  static const _fallbackLogExtent = 72.0;
  static const _maxIncrementalExtentChanges = 512;

  late final ScrollController _scroll;
  final ListController _listController = ListController();
  final Set<BigInt> _enteringIds = <BigInt>{};
  Timer? _flushTimer;

  late int _logsAppendRevision;
  String _filter = '';
  bool _follow = true;
  bool _active = false;
  bool _autoScrolling = false;
  bool _autoScrollPending = false;
  bool _anchorCaptureScheduled = false;
  bool _anchorCorrectionScheduled = false;
  bool _bottomRestorePending = false;
  bool _bottomRestoreScheduled = false;
  bool _pageTransitionEnabled = true;
  bool _userScrolling = false;
  bool _fastScrolling = false;
  int _autoScrollGeneration = 0;
  int _renderedLogCount = 0;
  int? _bottomRestoreWindowRevision;
  _LogViewportAnchor? _viewportAnchor;

  @override
  void initState() {
    super.initState();
    final logs = widget.session.logs;
    _logsAppendRevision = logs.appendRevision;
    _renderedLogCount = logs.length;
    _bottomRestorePending = _follow;
    _scroll = ScrollController(
      initialScrollOffset: logs.length * _fallbackLogExtent,
    );
    _listController.addListener(_onListLayout);
    widget.session.logs.addListener(_onLogs);
  }

  @override
  void dispose() {
    widget.session.logs.removeListener(_onLogs);
    widget.session.logs.setActive(false);
    _cancelAutoScroll();
    _listController.removeListener(_onListLayout);
    _listController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = isUiActive(context);
    final fastScrolling = active && isUiFastScrolling(context);
    final keepInactiveTailWarm = !active && _bottomRestorePending;
    if (_active == active) {
      if (_fastScrolling != fastScrolling) {
        _fastScrolling = fastScrolling;
        widget.session.logs.setActive(
          (active && !fastScrolling) || keepInactiveTailWarm,
        );
        if (active && !fastScrolling) {
          _ensureWindow();
          if (_follow) {
            _scheduleAutoScroll();
          } else {
            _scheduleAnchorCapture();
          }
        }
      } else {
        widget.session.logs.setActive(
          (active && !fastScrolling) || keepInactiveTailWarm,
        );
      }
      return;
    }
    if (!active) {
      _captureViewportAnchor();
      _bottomRestorePending = _follow;
      _bottomRestoreWindowRevision = null;
      _active = false;
      _fastScrolling = false;
      _userScrolling = false;
      _cancelAutoScroll();
      _enteringIds.clear();
      // Keep only the small tail window warm offstage so returning can paint
      // the current tail immediately.
      widget.session.logs.setActive(_bottomRestorePending);
      return;
    }
    _active = true;
    _fastScrolling = fastScrolling;
    _pageTransitionEnabled = !_follow;
    final logs = widget.session.logs;
    logs.setActive(!fastScrolling);
    if (fastScrolling) return;
    if (_bottomRestorePending) {
      _bottomRestoreWindowRevision = logs.refreshWindow();
      _syncListItems();
      _scheduleBottomRestore();
    } else {
      _scheduleAutoScroll();
    }
  }

  void _onLogs() {
    if (!mounted) return;
    final logs = widget.session.logs;
    final appendChanged = logs.appendRevision != _logsAppendRevision;
    _logsAppendRevision = logs.appendRevision;
    if (!_active) {
      if (_follow) _syncListItems();
      _enteringIds.clear();
      return;
    }
    final hadRows = _renderedLogCount > 0;
    _syncListItems();
    if (_follow && !hadRows && logs.length > 0) {
      _bottomRestorePending = true;
      _bottomRestoreWindowRevision = null;
    }
    final latestAppendId = logs.latestAppendId;
    if (appendChanged &&
        _follow &&
        !_bottomRestorePending &&
        latestAppendId != null) {
      _enteringIds.add(latestAppendId);
      final revision = _logsAppendRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && revision == _logsAppendRevision) {
          _enteringIds.clear();
        }
      });
    } else {
      _enteringIds.clear();
    }
    if (_follow && _bottomRestorePending) {
      _scheduleBottomRestore();
    } else if (!_follow) {
      _scheduleAnchorCorrection();
    }
    _scheduleAutoScroll();
  }

  void _setFilter(String value) {
    final next = value.trim();
    if (next == _filter) return;
    _filter = next;
    _clearViewportAnchor();
    _enteringIds.clear();
    widget.session.logs.setQuery(next);
  }

  void _onListLayout() {
    _renderedLogCount = _listController.numberOfItems;
    if (_follow) {
      if (_bottomRestorePending) {
        _scheduleBottomRestore();
      } else {
        _scheduleAutoScroll();
      }
    } else {
      _ensureWindow();
    }
  }

  bool _onUserScroll(UserScrollNotification notification) {
    if (!_active) return false;
    final scrolling = notification.direction != ScrollDirection.idle;
    if (scrolling) {
      if (!_userScrolling) {
        _userScrolling = true;
      }
      widget.session.logs.setAnchor(null);
      if (!_autoScrolling &&
          notification.direction == ScrollDirection.forward) {
        _setFollowing(false);
      }
      return false;
    }
    _userScrolling = false;
    if (!_autoScrolling) {
      final metrics = _scroll.position;
      _setFollowing(metrics.pixels >= metrics.maxScrollExtent - 80);
      if (!_follow) _scheduleAnchorCapture();
    }
    return false;
  }

  void _setFollowing(bool value) {
    if (value == _follow) return;
    if (!value) {
      _bottomRestorePending = false;
      _bottomRestoreWindowRevision = null;
      _cancelAutoScroll(stopPosition: false);
    } else {
      _clearViewportAnchor();
    }
    setState(() => _follow = value);
    widget.session.logs.setFollowing(value);
    if (value) {
      _scheduleAutoScroll();
    } else {
      _scheduleAnchorCapture();
    }
  }

  void _ensureWindow() {
    if (!_active || !_listController.isAttached) return;
    final range = _listController.visibleRange;
    if (range == null) return;
    final total = widget.session.logs.length;
    if (total == 0) return;
    widget.session.logs.ensureWindow(range.$1, range.$2);
  }

  void _syncListItems() {
    final logs = widget.session.logs;
    final previousCount = _renderedLogCount;
    final nextCount = logs.length;
    final anchor = _viewportAnchor;
    final nextAnchorIndex = anchor == null ? null : logs.indexOfId(anchor.id);

    final leadingDelta = nextAnchorIndex == null
        ? 0
        : nextAnchorIndex - anchor!.listIndex;
    final trailingDelta = nextCount - previousCount - leadingDelta;
    final canSync =
        _listController.isAttached &&
        !_listController.isLocked &&
        _listController.numberOfItems == previousCount;
    var leadingExtentDelta = 0.0;
    if (leadingDelta != 0 &&
        canSync &&
        _canApplyListMutation(previousCount, leadingDelta, trailingDelta)) {
      final mutationCount = leadingDelta.abs() + trailingDelta.abs();
      if (mutationCount <= _maxIncrementalExtentChanges) {
        leadingExtentDelta = _applyListMutation(leadingDelta, trailingDelta);
      } else {
        _listController.invalidateAllExtents();
        leadingExtentDelta = leadingDelta * _fallbackLogExtent;
      }
    }
    _renderedLogCount = nextCount;

    if (nextAnchorIndex != null && anchor != null) {
      _viewportAnchor = anchor.copyWith(listIndex: nextAnchorIndex);
    }
    if (_follow) return;
    if (leadingExtentDelta.abs() < 0.5) return;
    if (_scroll.hasClients) {
      if (_userScrolling) {
        // Keep the active drag; jumpTo would replace its ScrollActivity.
        _scroll.position.correctBy(leadingExtentDelta);
      } else {
        _autoScrolling = true;
        _scroll.jumpTo(_scroll.position.pixels + leadingExtentDelta);
        _autoScrolling = false;
      }
    }
  }

  bool _canApplyListMutation(int count, int leadingDelta, int trailingDelta) {
    final afterLeading = count + leadingDelta;
    return afterLeading >= 0 && afterLeading + trailingDelta >= 0;
  }

  double _applyListMutation(int leadingDelta, int trailingDelta) {
    var leadingExtentDelta = 0.0;
    if (leadingDelta > 0) {
      for (var i = 0; i < leadingDelta; i++) {
        _listController.addItem(0);
        leadingExtentDelta += _listController.extentForIndex(0).$1;
      }
    } else {
      for (var i = 0; i > leadingDelta; i--) {
        leadingExtentDelta -= _listController.extentForIndex(0).$1;
        _listController.removeItem(0);
      }
    }

    if (trailingDelta > 0) {
      for (var i = 0; i < trailingDelta; i++) {
        _listController.addItem(_listController.numberOfItems);
      }
    } else {
      for (var i = 0; i > trailingDelta; i--) {
        _listController.removeItem(_listController.numberOfItems - 1);
      }
    }
    return leadingExtentDelta;
  }

  void _scheduleAnchorCapture() {
    if (!_active || _userScrolling || _anchorCaptureScheduled) {
      return;
    }
    _anchorCaptureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorCaptureScheduled = false;
      if (!mounted || !_active || _userScrolling) {
        return;
      }
      _captureViewportAnchor();
    });
  }

  void _captureViewportAnchor() {
    if (!_scroll.hasClients || !_listController.isAttached) return;
    final range = _listController.visibleRange;
    if (range == null) return;
    final logs = widget.session.logs;
    final midpoint = (range.$1 + range.$2) / 2;
    rust.LogEntry? candidate;
    var candidateIndex = -1;
    var candidateDistance = double.infinity;
    for (var index = range.$1; index <= range.$2; index++) {
      final entry = logs.rowAt(index);
      if (entry == null) continue;
      final distance = (index - midpoint).abs();
      if (distance < candidateDistance) {
        candidate = entry;
        candidateIndex = index;
        candidateDistance = distance;
      }
    }
    if (candidate == null) return;
    final revealOffset = _offsetForItem(candidateIndex);
    if (!revealOffset.isFinite) return;
    _viewportAnchor = _LogViewportAnchor(
      id: candidate.id,
      listIndex: candidateIndex,
      scrollDelta: _scroll.position.pixels - revealOffset,
    );
    logs.setAnchor(candidate.id);
  }

  void _scheduleAnchorCorrection() {
    if (!_active || _follow || _userScrolling || _anchorCorrectionScheduled) {
      return;
    }
    _anchorCorrectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorCorrectionScheduled = false;
      if (!mounted || !_active || _follow || _userScrolling) return;
      _restoreViewportAnchorPosition();
      _scheduleAnchorCapture();
    });
  }

  bool _restoreViewportAnchorPosition() {
    final anchor = _viewportAnchor;
    if (anchor == null || !_scroll.hasClients || !_listController.isAttached) {
      return false;
    }
    final logicalIndex = widget.session.logs.indexOfId(anchor.id);
    if (logicalIndex == null) return false;
    final revealOffset = _offsetForItem(logicalIndex);
    if (!revealOffset.isFinite) return false;
    final position = _scroll.position;
    final target = (revealOffset + anchor.scrollDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _viewportAnchor = anchor.copyWith(listIndex: logicalIndex);
    if ((target - position.pixels).abs() < 0.5) return true;
    _autoScrolling = true;
    _scroll.jumpTo(target);
    _autoScrolling = false;
    return true;
  }

  double _offsetForItem(int index) {
    // ignore: invalid_use_of_visible_for_testing_member
    return _listController.getOffsetToReveal(index, 0.5);
  }

  double _estimateLogExtent(int? _, double _) => _fallbackLogExtent;

  double _placeholderExtent(int index) {
    if (!_listController.isAttached || index >= _listController.numberOfItems) {
      return _fallbackLogExtent;
    }
    final extent = _listController.extentForIndex(index).$1;
    return extent.isFinite && extent > 0 ? extent : _fallbackLogExtent;
  }

  void _clearViewportAnchor() {
    _viewportAnchor = null;
    widget.session.logs.setAnchor(null);
  }

  void _scheduleBottomRestore() {
    if (!_active ||
        !_follow ||
        !_bottomRestorePending ||
        _bottomRestoreScheduled) {
      return;
    }
    _bottomRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomRestoreScheduled = false;
      if (!mounted || !_active || !_follow || !_bottomRestorePending) return;
      final logs = widget.session.logs;
      final refreshRevision = _bottomRestoreWindowRevision;
      if (refreshRevision != null && logs.windowRevision <= refreshRevision) {
        return;
      }
      if (logs.length > 0 && _scroll.hasClients) {
        _autoScrolling = true;
        final position = _scroll.position;
        if ((position.pixels - position.maxScrollExtent).abs() >= 0.5) {
          _scroll.jumpTo(position.maxScrollExtent);
        }
        _autoScrolling = false;
        _ensureWindow();
      }
      _bottomRestorePending = false;
      _bottomRestoreWindowRevision = null;
    });
  }

  // Defer follow-scroll until the rebuild from setState has materialized.
  void _scheduleAutoScroll() {
    if (!_active || !_follow || _bottomRestorePending) return;
    if (_autoScrolling) {
      _autoScrollPending = true;
      return;
    }
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(milliseconds: 80), () {
      _flushTimer = null;
      if (!mounted || !_active) return;
      if (!_follow) return;
      final logs = widget.session.logs;
      if (logs.filterLoading) return;
      if (logs.length == 0 || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (!pos.hasContentDimensions) return;
      final target = pos.maxScrollExtent;
      final distance = target - pos.pixels;
      final visibleRange = _listController.isAttached
          ? _listController.visibleRange
          : null;
      final needsTailRecovery =
          distance.abs() < 1 &&
          visibleRange != null &&
          visibleRange.$2 < logs.length - 1;
      if (distance.abs() < 1 && !needsTailRecovery) return;
      if (needsTailRecovery || distance > pos.viewportDimension * 2) {
        final generation = ++_autoScrollGeneration;
        _autoScrolling = true;
        _listController.jumpToItem(
          index: logs.length - 1,
          scrollController: _scroll,
          alignment: 1,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _autoScrollGeneration) return;
          _autoScrolling = false;
          _ensureWindow();
          if (_follow) _scheduleAutoScroll();
        });
        return;
      }
      final generation = ++_autoScrollGeneration;
      _autoScrollPending = false;
      _autoScrolling = true;
      unawaited(
        _scroll
            .animateTo(
              target,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (!mounted || generation != _autoScrollGeneration) return;
              _autoScrolling = false;
              if (_autoScrollPending && _follow) {
                _autoScrollPending = false;
                _scheduleAutoScroll();
                return;
              }
              _ensureWindow();
            }),
      );
    });
  }

  void _cancelAutoScroll({bool stopPosition = true}) {
    _flushTimer?.cancel();
    _flushTimer = null;
    _autoScrollPending = false;
    _autoScrollGeneration++;
    if (stopPosition && _autoScrolling && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.pixels);
    }
    _autoScrolling = false;
  }

  void _setLevel(String level) {
    if (level == widget.session.logsLevel) return;
    _clearViewportAnchor();
    _enteringIds.clear();
    widget.session.setLogsLevel(level);
    setState(() {});
  }

  void _togglePause() {
    final paused = widget.session.logs.paused;
    paused.value = !paused.value;
  }

  void _clear() {
    _clearViewportAnchor();
    _enteringIds.clear();
    _cancelAutoScroll();
    if (_listController.isAttached && !_listController.isLocked) {
      _listController.invalidateAllExtents();
    }
    unawaited(widget.session.clearLogs());
  }

  Widget _buildLogsList(BuildContext context) {
    final logs = widget.session.logs;
    if (logs.filterLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final count = logs.length;
    if (count == 0) {
      return Center(
        child: Text(
          logs.isEmpty ? '暂无日志' : '没有匹配的日志',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final bottomPadding = 24 + MediaQuery.paddingOf(context).bottom;
    return NotificationListener<UserScrollNotification>(
      onNotification: _onUserScroll,
      child: AppBackdropGroup(
        child: SelectionArea(
          child: SuperListView.builder(
            controller: _scroll,
            listController: _listController,
            physics: _KeepBottomScrollPhysics(
              shouldKeepBottom: () => _bottomRestorePending,
              parent: const SuperRangeMaintainingScrollPhysics(),
            ),
            extentEstimation: _estimateLogExtent,
            // During a fast fling, build only the visible range this frame and
            // fill the cache area after scrolling slows down.
            delayPopulatingCacheArea: true,
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
            addRepaintBoundaries: false,
            addAutomaticKeepAlives: false,
            itemCount: count,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<BigInt>) return null;
              return logs.indexOfId(key.value);
            },
            itemBuilder: (context, index) {
              final entry = logs.rowAt(index);
              final placeholder = _LogPlaceholder(
                extent: _placeholderExtent(index),
              );
              if (entry == null) {
                return placeholder;
              }
              return ScrollDeferredContent(
                key: ValueKey(entry.id),
                placeholder: placeholder,
                child: _AnimatedLogTile(
                  entry: entry,
                  animate: _enteringIds.contains(entry.id),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _levelLabel(String level) => switch (level) {
    'warning' => 'warn',
    'silent' => 'off',
    _ => level,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logs = widget.session.logs;
    final levels = widget.store.active?.type == ctl.BackendType.singBox
        ? const ['info', 'debug', 'trace', 'warning', 'error', 'silent']
        : _baseLevels;
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('日志'),
          flexibleSpace: const DesktopAppBarDragArea(),
          actionsPadding: const EdgeInsets.only(right: 4),
          actions: [
            ActiveValueListenableBuilder<bool>(
              valueListenable: logs.paused,
              builder: (_, paused, _) => IconButton(
                tooltip: paused ? '继续' : '暂停',
                visualDensity: VisualDensity.compact,
                onPressed: _togglePause,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              ),
            ),
            ActiveListenableBuilder(
              listenable: logs,
              builder: (_, _) => IconButton(
                tooltip: '清空',
                visualDensity: VisualDensity.compact,
                onPressed: logs.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
            LogsSettingsMenu(prefs: widget.prefs),
          ],
        ),
      ),
      body: AppPageBodyTransition(
        enabled: _pageTransitionEnabled,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CompactSearchField(
                            hintText: '过滤消息内容',
                            onChanged: _setFilter,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CompactMenuButton<String>(
                          width: 80,
                          value: widget.session.logsLevel,
                          label: _levelLabel(widget.session.logsLevel),
                          semanticLabel: '日志等级',
                          onSelected: _setLevel,
                          itemBuilder: (_) => [
                            for (final level in levels)
                              PopupMenuItem(
                                value: level,
                                child: Text(_levelLabel(level)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ActiveValueListenableBuilder<String?>(
                valueListenable: widget.session.error,
                builder: (_, err, _) {
                  if (err == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_rounded,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            err,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: ActiveListenableBuilder(
                  listenable: logs,
                  builder: (context, _) => _buildLogsList(context),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _follow
          ? null
          : FloatingActionButton.small(
              tooltip: '回到底部',
              onPressed: () => _setFollowing(true),
              child: const Icon(Icons.arrow_downward),
            ),
    );
  }
}

class _KeepBottomScrollPhysics extends ScrollPhysics {
  const _KeepBottomScrollPhysics({
    required this.shouldKeepBottom,
    super.parent,
  });

  final bool Function() shouldKeepBottom;

  @override
  _KeepBottomScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _KeepBottomScrollPhysics(
        shouldKeepBottom: shouldKeepBottom,
        parent: buildParent(ancestor),
      );

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (shouldKeepBottom()) {
      return newPosition.maxScrollExtent;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

class _LogViewportAnchor {
  const _LogViewportAnchor({
    required this.id,
    required this.listIndex,
    required this.scrollDelta,
  });

  final BigInt id;
  final int listIndex;
  final double scrollDelta;

  _LogViewportAnchor copyWith({int? listIndex}) => _LogViewportAnchor(
    id: id,
    listIndex: listIndex ?? this.listIndex,
    scrollDelta: scrollDelta,
  );
}

class _LogPlaceholder extends StatelessWidget {
  const _LogPlaceholder({required this.extent});

  final double extent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final base = surfaceTheme.surfaceColor(
      scheme.surfaceContainerLow.withValues(alpha: 0.72),
    );
    final badge = scheme.primaryContainer.withValues(alpha: 0.42);
    final mark = scheme.onSurfaceVariant.withValues(alpha: 0.15);
    return SizedBox(
      height: extent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 9, 11, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 68,
                  height: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: badge,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.28,
                        child: _LogPlaceholderMark(height: 6, color: mark),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.82,
                        child: _LogPlaceholderMark(height: 8, color: mark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogPlaceholderMark extends StatelessWidget {
  const _LogPlaceholderMark({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    ),
  );
}

class _AnimatedLogTile extends StatefulWidget {
  const _AnimatedLogTile({required this.entry, required this.animate});

  final rust.LogEntry entry;
  final bool animate;

  @override
  State<_AnimatedLogTile> createState() => _AnimatedLogTileState();
}

class _AnimatedLogTileState extends State<_AnimatedLogTile>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _controller = controller;
    _animation = controller.drive(CurveTween(curve: Curves.easeOutCubic));
    final generation = ++_generation;
    controller.forward().whenCompleteOrCancel(() {
      if (!mounted ||
          generation != _generation ||
          !identical(_controller, controller) ||
          !controller.isCompleted) {
        return;
      }
      setState(() {
        _controller = null;
        _animation = null;
      });
      controller.dispose();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled && _controller != null) {
      _generation++;
      final controller = _controller;
      _controller = null;
      _animation = null;
      controller?.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _LogTile(entry: widget.entry);
    final animation = _animation;
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = animation.value;
        return Opacity(
          opacity: 0.35 + 0.65 * progress,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - progress)),
            transformHitTests: false,
            child: child,
          ),
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final rust.LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final (badgeFg, badgeBg) = _levelColors(entry.level, scheme);
    final ts = entry.time.isEmpty ? '' : entry.time;
    final level = entry.level.isEmpty ? 'log' : entry.level;
    final surfaceColor = Color.alphaBlend(
      badgeBg.withValues(alpha: 0.045),
      scheme.surfaceContainerLow,
    );
    const radius = BorderRadius.all(Radius.circular(10));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RepaintBoundary(
        child: AppSurfaceBackdrop(
          borderRadius: radius,
          grouped: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surfaceTheme.surfaceColor(surfaceColor, -0.02),
              borderRadius: radius,
              border: surfaceTheme.outlineBorder(
                scheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 11, 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 68,
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      level,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                      style: textTheme.labelSmall?.copyWith(
                        color: badgeFg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ts.isNotEmpty)
                          Text(
                            ts,
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          entry.message,
                          style: textTheme.bodyMedium?.copyWith(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color) _levelColors(String level, ColorScheme scheme) {
    switch (level.toLowerCase()) {
      case 'error':
      case 'fatal':
      case 'panic':
        return (scheme.onErrorContainer, scheme.errorContainer);
      case 'warning':
      case 'warn':
        return (scheme.onTertiaryContainer, scheme.tertiaryContainer);
      case 'debug':
      case 'trace':
        return (scheme.onSecondaryContainer, scheme.secondaryContainer);
      case 'info':
      default:
        return (scheme.onPrimaryContainer, scheme.primaryContainer);
    }
  }
}
