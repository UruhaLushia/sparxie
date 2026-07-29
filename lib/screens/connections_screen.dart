import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../session.dart';
import '../utils.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/app_background.dart';
import '../widgets/connection_detail_sheet.dart';
import '../widgets/connection_group_header.dart';
import '../widgets/connection_tile.dart';
import '../widgets/compact_controls.dart';
import '../widgets/connections_settings_menu.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/page_body_transition.dart';
import '../widgets/route_app_bar.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({
    super.key,
    required this.store,
    required this.prefs,
    required this.session,
  });

  final ctl.ControllerStore store;
  final AppPrefs prefs;
  final MihomoSession session;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _TabListTransitionScope extends InheritedWidget {
  const _TabListTransitionScope({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  static _TabListTransitionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TabListTransitionScope>();

  @override
  bool updateShouldNotify(_TabListTransitionScope oldWidget) =>
      animation != oldWidget.animation;
}

class _TabSwitchDirectionScope extends InheritedWidget {
  const _TabSwitchDirectionScope({
    required this.direction,
    required super.child,
  });

  final int direction;

  static _TabSwitchDirectionScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TabSwitchDirectionScope>()!;

  @override
  bool updateShouldNotify(_TabSwitchDirectionScope oldWidget) =>
      direction != oldWidget.direction;
}

class _StaggeredTabItem extends StatelessWidget {
  const _StaggeredTabItem({
    required this.index,
    required this.child,
    this.delayedEntry = false,
  });

  final int index;
  final Widget child;
  final bool delayedEntry;

  @override
  Widget build(BuildContext context) {
    final scope = _TabListTransitionScope.maybeOf(context);
    if (scope == null) return child;
    final direction = _TabSwitchDirectionScope.of(context).direction;
    final slot = math.min(index, 7);
    return AnimatedBuilder(
      animation: scope.animation,
      child: child,
      builder: (context, child) {
        final incoming = scope.animation.status != AnimationStatus.reverse;
        final start = incoming
            ? delayedEntry
                  ? 0.6
                  : 0.28 + slot * 0.02
            : 0.68 - slot * 0.02;
        final end = incoming ? start + 0.3 : math.min(start + 0.3, 0.99);
        final raw = Interval(start, end).transform(scope.animation.value);
        final progress = Curves.easeInOutCubic.transform(raw);
        final offset = (incoming ? 0.1 : -0.07) * direction * (1 - progress);
        return Opacity(
          opacity: progress,
          child: FractionalTranslation(
            translation: Offset(offset, 0),
            child: child,
          ),
        );
      },
    );
  }
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  String _filter = '';
  ConnectionsTab _tab = ConnectionsTab.active;
  int _tabDirection = 1;
  ({
    int refreshMs,
    ConnectionsSort sort,
    bool sortAsc,
    bool grouped,
    GroupSort groupSort,
    bool groupSortAsc,
  })?
  _prefsSnapshot;
  final TextEditingController _filterController = TextEditingController();

  rust.BackendTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.backendTargetForController(c);
  }

  @override
  void initState() {
    super.initState();
    widget.prefs.addListener(_onPrefsChanged);
    _syncRelevantPrefs();
    widget.session.connections.setFilter(_filter);
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_onPrefsChanged);
    _filterController.dispose();
    super.dispose();
  }

  void _onPrefsChanged() {
    _syncRelevantPrefs();
  }

  void _syncRelevantPrefs() {
    final next = (
      refreshMs: widget.prefs.connectionsRefreshMs,
      sort: widget.prefs.connectionsSort,
      sortAsc: widget.prefs.connectionsSortAsc,
      grouped: widget.prefs.connectionsGroupByProcess,
      groupSort: widget.prefs.connectionsGroupSort,
      groupSortAsc: widget.prefs.connectionsGroupSortAsc,
    );
    final previous = _prefsSnapshot;
    if (previous == next) return;
    _prefsSnapshot = next;
    if (previous == null ||
        previous.refreshMs != next.refreshMs ||
        previous.sort != next.sort ||
        previous.sortAsc != next.sortAsc) {
      _pushSortToBackend();
    }
    if (previous == null ||
        previous.grouped != next.grouped ||
        previous.groupSort != next.groupSort ||
        previous.groupSortAsc != next.groupSortAsc) {
      _syncGrouping();
    }
  }

  void _syncGrouping() {
    final cn = widget.session.connections;
    cn.setVisibleTab(_tab);
    cn.grouped = widget.prefs.connectionsGroupByProcess;
    cn.setGroupSort(
      _toRustGroupSort(widget.prefs.connectionsGroupSort),
      widget.prefs.connectionsGroupSortAsc,
    );
  }

  static rust.ConnectionGroupSort _toRustGroupSort(GroupSort s) => switch (s) {
    GroupSort.name => rust.ConnectionGroupSort.name,
    GroupSort.count => rust.ConnectionGroupSort.count,
    GroupSort.upload => rust.ConnectionGroupSort.upload,
    GroupSort.download => rust.ConnectionGroupSort.download,
    GroupSort.uploadSpeed => rust.ConnectionGroupSort.uploadSpeed,
    GroupSort.downloadSpeed => rust.ConnectionGroupSort.downloadSpeed,
  };

  void _pushSortToBackend() {
    final target = _target();
    if (target == null) return;
    rust.setConnectionsSort(
      target: target,
      intervalMs: widget.prefs.connectionsRefreshMs,
      sort: _toRustSort(widget.prefs.connectionsSort),
      asc: widget.prefs.connectionsSortAsc,
    );
  }

  static rust.ConnectionsSort _toRustSort(ConnectionsSort s) => switch (s) {
    ConnectionsSort.time => rust.ConnectionsSort.time,
    ConnectionsSort.upload => rust.ConnectionsSort.upload,
    ConnectionsSort.download => rust.ConnectionsSort.download,
    ConnectionsSort.uploadSpeed => rust.ConnectionsSort.uploadSpeed,
    ConnectionsSort.downloadSpeed => rust.ConnectionsSort.downloadSpeed,
    ConnectionsSort.process => rust.ConnectionsSort.process,
  };

  static String _sortLabel(ConnectionsSort s) => switch (s) {
    ConnectionsSort.time => '时间',
    ConnectionsSort.upload => '上传量',
    ConnectionsSort.download => '下载量',
    ConnectionsSort.uploadSpeed => '上传速度',
    ConnectionsSort.downloadSpeed => '下载速度',
    ConnectionsSort.process => '进程名',
  };

  void _setTab(ConnectionsTab tab) {
    if (tab == _tab) return;
    _tabDirection = tab.index > _tab.index ? 1 : -1;
    widget.session.connections.setVisibleTab(tab);
    setState(() => _tab = tab);
  }

  Widget _tabTransition(Widget child, Animation<double> animation) {
    return _TabListTransitionScope(animation: animation, child: child);
  }

  void _setFilter(String value) {
    final next = value.trim();
    widget.session.connections.setFilter(next);
    setState(() => _filter = next);
  }

  Future<void> _close(String id) async {
    final target = _target();
    if (target == null) return;
    widget.session.connections.optimisticRemove(id);
    try {
      await rust.closeConnection(target: target, id: id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('关闭失败:${_formatError(e)}')));
      }
    }
  }

  Future<void> _closeAll(int currentCount) async {
    final target = _target();
    if (target == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关闭所有连接'),
        content: Text('当前 $currentCount 条连接将被关闭'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('关闭所有'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await rust.closeAllConnections(target: target);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('关闭失败:${_formatError(e)}')));
      }
    }
  }

  Future<void> _clearClosed() async {
    final target = _target();
    if (target == null) return;
    // Optimistic: zero the local buffer immediately so the count chip and
    // the list both update without waiting on a round-trip.
    widget.session.connections.clearClosedOptimistic();
    try {
      await rust.clearClosedConnections(
        target: target,
        intervalMs: widget.prefs.connectionsRefreshMs,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清空失败:${_formatError(e)}')));
      }
    }
  }

  String _formatError(Object error) =>
      formatError(error, backendName: widget.store.active?.name);

  void _showDetail(ConnectionRow row) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ConnectionDetailSheet(
        row: row,
        showConnectionLog: widget.session.isStash.value,
        onClose: () => _close(row.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          flexibleSpace: const DesktopAppBarDragArea(),
          title: Row(
            children: [
              const Text('连接'),
              const SizedBox(width: 8),
              ActiveValueListenableBuilder<bool>(
                valueListenable: widget.session.isStreaming,
                builder: (_, live, _) => AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: live ? 1 : 0.3,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: ActiveValueListenableBuilder<ConnectionsTotals>(
                  valueListenable: widget.session.connectionsTotals,
                  builder: (_, totals, _) => Text(
                    '↑${formatBytes(totals.upload)}/↓${formatBytes(totals.download)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.only(right: 4),
          actions: [
            ActiveValueListenableBuilder<bool>(
              valueListenable: widget.session.connectionsPaused,
              builder: (_, paused, _) => IconButton(
                tooltip: paused ? '继续' : '暂停',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    widget.session.connectionsPaused.value = !paused,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              ),
            ),
            ActiveValueListenableBuilder<ConnectionsTotals>(
              valueListenable: widget.session.connectionsTotals,
              builder: (_, totals, _) {
                if (_tab == ConnectionsTab.closed) {
                  return ActiveListenableBuilder(
                    listenable: widget.session.connections,
                    builder: (_, _) {
                      final n = widget.session.connections.closedCount;
                      return IconButton(
                        tooltip: '清空已关闭',
                        visualDensity: VisualDensity.compact,
                        onPressed: n == 0 ? null : _clearClosed,
                        icon: const Icon(Icons.delete_outline),
                      );
                    },
                  );
                }
                return IconButton(
                  tooltip: '关闭所有',
                  visualDensity: VisualDensity.compact,
                  onPressed: totals.count == 0
                      ? null
                      : () => _closeAll(totals.count),
                  icon: const Icon(Icons.close),
                );
              },
            ),
            ConnectionsSettingsMenu(prefs: widget.prefs),
          ],
        ),
      ),
      body: AppPageBodyTransition(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // sticky toolbar: tabs + filter + sort field + direction toggle.
              // On phones the row would overflow, so split into two lines:
              //   row 1 = filter
              //   row 2 = tabs + sort + direction
              RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 480;
                      final tabs = ActiveListenableBuilder(
                        listenable: widget.session.connections,
                        builder: (context, _) {
                          final cn = widget.session.connections;
                          return CompactSegmentedButton<ConnectionsTab>(
                            segments: [
                              ButtonSegment(
                                value: ConnectionsTab.active,
                                label: Text('活动 ${cn.activeCount}'),
                              ),
                              ButtonSegment(
                                value: ConnectionsTab.closed,
                                label: Text('已关闭 ${cn.closedCount}'),
                              ),
                            ],
                            selected: {_tab},
                            onSelectionChanged: (s) => _setTab(s.first),
                          );
                        },
                      );
                      final filter = CompactSearchField(
                        controller: _filterController,
                        hintText: '筛选',
                        onChanged: _setFilter,
                        onClear: () {
                          _filterController.clear();
                          _setFilter('');
                        },
                      );
                      final sortField = ActiveListenableBuilder(
                        listenable: widget.prefs,
                        builder: (context, _) => CompactMenuButton(
                          value: widget.prefs.connectionsSort,
                          label: _sortLabel(widget.prefs.connectionsSort),
                          semanticLabel: '排序字段',
                          onSelected: widget.prefs.setConnectionsSort,
                          itemBuilder: (_) => [
                            for (final s in ConnectionsSort.values)
                              CheckedPopupMenuItem<ConnectionsSort>(
                                value: s,
                                checked: widget.prefs.connectionsSort == s,
                                child: Text(_sortLabel(s)),
                              ),
                          ],
                        ),
                      );
                      final direction = ActiveListenableBuilder(
                        listenable: widget.prefs,
                        builder: (context, _) => CompactIconButton(
                          semanticLabel: widget.prefs.connectionsSortAsc
                              ? '升序'
                              : '降序',
                          onPressed: () => widget.prefs.setConnectionsSortAsc(
                            !widget.prefs.connectionsSortAsc,
                          ),
                          icon: Icon(
                            widget.prefs.connectionsSortAsc
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 18,
                          ),
                        ),
                      );

                      if (!compact) {
                        return Row(
                          children: [
                            tabs,
                            const SizedBox(width: 8),
                            Expanded(child: filter),
                            const SizedBox(width: 8),
                            sortField,
                            const SizedBox(width: 4),
                            direction,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          filter,
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              tabs,
                              const Spacer(),
                              sortField,
                              const SizedBox(width: 4),
                              direction,
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              ActiveValueListenableBuilder<String?>(
                valueListenable: widget.session.error,
                builder: (_, err, _) {
                  if (err == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_rounded,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            err,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: ActiveListenableBuilder(
                  listenable: widget.prefs,
                  builder: (context, _) {
                    final grouped = widget.prefs.connectionsGroupByProcess;
                    final content = grouped
                        ? _GroupedConnectionsList(
                            session: widget.session,
                            prefs: widget.prefs,
                            tab: _tab,
                            filter: _filter,
                            onTap: _showDetail,
                            onClose: _close,
                          )
                        : _ConnectionsList(
                            session: widget.session,
                            prefs: widget.prefs,
                            tab: _tab,
                            filter: _filter,
                            onTap: _showDetail,
                            onClose: _close,
                          );
                    return ClipRect(
                      child: _TabSwitchDirectionScope(
                        direction: _tabDirection,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          reverseDuration: const Duration(milliseconds: 420),
                          switchInCurve: Curves.linear,
                          switchOutCurve: Curves.linear,
                          transitionBuilder: _tabTransition,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                fit: StackFit.expand,
                                children: [...previousChildren, ?currentChild],
                              ),
                          child: KeyedSubtree(
                            key: ValueKey(_tab),
                            child: content,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pages id-driven rows by index. Cache misses render a placeholder; the
/// notifier triggers a rebuild when the row payloads land.
class _ConnectionsList extends StatefulWidget {
  const _ConnectionsList({
    required this.session,
    required this.prefs,
    required this.tab,
    required this.filter,
    required this.onTap,
    required this.onClose,
  });

  final MihomoSession session;
  final AppPrefs prefs;
  final ConnectionsTab tab;
  final String filter;
  final ValueChanged<ConnectionRow> onTap;
  final ValueChanged<String> onClose;

  @override
  State<_ConnectionsList> createState() => _ConnectionsListState();
}

class _ConnectionsListState extends State<_ConnectionsList> {
  static const Duration _animDuration = Duration(milliseconds: 200);
  // Base row height at text-scale 1.0. The card sizes to its content (~70px
  // from the tile's padding); this slot adds the inter-card gap on top, so
  // the spacing is `_baseRowHeight - cardHeight` ≈ 12px. The tile clamps its
  // text line heights so CJK metrics stay within the slot. Scaled by the
  // system font factor below.
  static const double _baseRowHeight = 72;

  // Effective row height for the current text scale; kept in sync with the
  // value handed to ListView.itemExtent so the scroll-window math agrees.
  double _rowHeight = _baseRowHeight;

  final ScrollController _scrollController = ScrollController();
  // Coalesce ensureWindow calls to one per frame.
  bool _scheduled = false;
  var _active = true;

  @override
  void initState() {
    super.initState();
    widget.session.connections.addListener(_onChange);
    _scrollController.addListener(_onScroll);
    // Kick off the initial window fetch on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureWindow();
    });
  }

  @override
  void didUpdateWidget(covariant _ConnectionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.connections.removeListener(_onChange);
      widget.session.connections.addListener(_onChange);
    }
    if (oldWidget.tab != widget.tab || oldWidget.filter != widget.filter) {
      // Tab switch — jump scroll to top so the user starts at index 0
      // of the new list, and prefetch its head window.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        _ensureWindow();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (_active == active) return;
    _active = active;
    if (active) _scheduleEnsureWindow();
  }

  @override
  void dispose() {
    widget.session.connections.removeListener(_onChange);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted ||
        !_active ||
        widget.session.connections.visibleTab != widget.tab) {
      return;
    }
    setState(() {});
    _scheduleEnsureWindow();
  }

  void _onScroll() {
    _scheduleEnsureWindow();
  }

  void _scheduleEnsureWindow() {
    if (!_active || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _ensureWindow();
    });
  }

  /// Ask the notifier to cache only the visible range plus a small overscan.
  void _ensureWindow() {
    if (!_active ||
        !_scrollController.hasClients ||
        widget.session.connections.visibleTab != widget.tab) {
      return;
    }
    final pos = _scrollController.position;
    final firstIndex = (pos.pixels / _rowHeight).floor();
    final lastIndex =
        ((pos.pixels + pos.viewportDimension) / _rowHeight).ceil() - 1;
    widget.session.connections.ensureWindow(widget.tab, firstIndex, lastIndex);
  }

  int _totalCount() {
    final cn = widget.session.connections;
    return cn.visibleCount(widget.tab);
  }

  @override
  Widget build(BuildContext context) {
    // Scale the row slot by the system font factor. Only the tile's two text
    // lines grow with it; the icon and fixed paddings don't, so scale just
    // that portion to avoid both overflow (too short) and sparse rows.
    const fixedPart = 36.0; // icon vertical slack + paddings that don't scale
    const textPart = _baseRowHeight - fixedPart;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    _rowHeight = fixedPart + textPart * math.max(1.0, textScale);

    final total = _totalCount();
    if (widget.session.connections.filterLoading) {
      return const SizedBox.expand();
    }
    if (total == 0) {
      return _StaggeredTabItem(
        index: 0,
        delayedEntry: true,
        child: Center(
          child: Text(
            widget.filter.isNotEmpty
                ? '没有匹配的连接'
                : widget.tab == ConnectionsTab.active
                ? '暂无连接'
                : '暂无已关闭连接',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    // Local backend only: the process paths in /connections refer to the
    // backend host, so resolving icons for a remote controller is wrong.
    final processIcons = widget.session.isLocalBackend
        ? widget.session.processIcons
        : null;
    return RepaintBoundary(
      child: ActiveListenableBuilder(
        listenable: widget.prefs,
        builder: (context, _) {
          final showIcon = widget.prefs.connectionsShowProcessIcon;
          final showAppName = widget.prefs.connectionsShowAppName;
          return ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            // Fixed-height items let ListView do exact scroll math without
            // measuring offscreen widgets.
            itemExtent: _rowHeight,
            itemCount: total,
            itemBuilder: (context, index) {
              final cn = widget.session.connections;
              final row = cn.rowAt(widget.tab, index);
              return _StaggeredTabItem(
                index: index,
                child: _RowSlot(
                  // Same key for the same row id keeps state across frames so
                  // the AnimatedSwitcher inside doesn't re-trigger transitions.
                  key: ValueKey(row?.id ?? 'idx::$index'),
                  row: row,
                  duration: _animDuration,
                  processIcons: processIcons,
                  showIcon: showIcon,
                  showAppName: showAppName,
                  onTap: row == null ? null : () => widget.onTap(row),
                  onClose: row == null ? null : () => widget.onClose(row.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One slot in the virtualized list. AnimatedSwitcher handles the
/// placeholder ↔ tile transition with size + fade so rows entering
/// the window from off-screen visibly slide in.
class _RowSlot extends StatelessWidget {
  const _RowSlot({
    super.key,
    required this.row,
    required this.duration,
    this.processIcons,
    this.showIcon = false,
    this.showAppName = false,
    this.onTap,
    this.onClose,
  });

  final ConnectionRow? row;
  final Duration duration;
  final ProcessIconCache? processIcons;
  final bool showIcon;
  final bool showAppName;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final child = row != null
        ? Padding(
            key: ValueKey('tile::${row!.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: ConnectionTile(
              row: row!,
              processIcons: processIcons,
              showIcon: showIcon,
              showAppName: showAppName,
              onTap: onTap ?? () {},
              onClose: onClose ?? () {},
            ),
          )
        : const Padding(
            key: ValueKey('placeholder'),
            padding: EdgeInsets.only(bottom: 8),
            child: _RowPlaceholder(),
          );
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: child,
    );
  }
}

class _RowPlaceholder extends StatelessWidget {
  const _RowPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: surfaceTheme.surfaceColor(
          scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

/// Grouped (by-process) connections. Each process is a pinned header
/// (icon + label + count + aggregated bytes/speed); expanding one lists its
/// member connections. Group summaries and member rows are kept fresh by the
/// notifier, which patches volatile counters in place.
class _GroupedConnectionsList extends StatefulWidget {
  const _GroupedConnectionsList({
    required this.session,
    required this.prefs,
    required this.tab,
    required this.filter,
    required this.onTap,
    required this.onClose,
  });

  final MihomoSession session;
  final AppPrefs prefs;
  final ConnectionsTab tab;
  final String filter;
  final ValueChanged<ConnectionRow> onTap;
  final ValueChanged<String> onClose;

  @override
  State<_GroupedConnectionsList> createState() =>
      _GroupedConnectionsListState();
}

class _GroupedConnectionsListState extends State<_GroupedConnectionsList> {
  var _active = true;

  @override
  void initState() {
    super.initState();
    widget.session.connections.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant _GroupedConnectionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.connections.removeListener(_onChange);
      widget.session.connections.addListener(_onChange);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    widget.session.connections.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted &&
        _active &&
        widget.session.connections.visibleTab == widget.tab) {
      setState(() {});
    }
  }

  Future<void> _closeGroup(ConnectionGroupSummary g) async {
    if (widget.tab != ConnectionsTab.active) return;
    final target = widget.session.target;
    if (target == null) return;
    final count = g.count.value;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关闭来源连接'),
        content: Text('将关闭「${g.label}」的 $count 条连接'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await rust.closeConnectionsByGroup(target: target, group: g.key);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('关闭失败:${_formatError(e)}')));
      }
    }
  }

  Future<void> _clearClosedGroup(ConnectionGroupSummary g) async {
    final target = widget.session.target;
    if (target == null) return;
    widget.session.connections.clearClosedGroupOptimistic(g.key);
    try {
      await rust.clearClosedConnectionsByGroup(
        target: target,
        intervalMs: widget.prefs.connectionsRefreshMs,
        group: g.key,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清空失败:${_formatError(e)}')));
      }
    }
  }

  String _formatError(Object error) =>
      formatError(error, backendName: widget.session.activeController?.name);

  @override
  Widget build(BuildContext context) {
    final cn = widget.session.connections;
    final groups = cn.groups;
    if (cn.filterLoading) {
      return const SizedBox.expand();
    }
    if (groups.isEmpty) {
      return _StaggeredTabItem(
        index: 0,
        delayedEntry: true,
        child: Center(
          child: Text(
            widget.filter.isEmpty
                ? widget.tab == ConnectionsTab.active
                      ? '暂无连接'
                      : '暂无已关闭连接'
                : '没有匹配的连接',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    final processIcons = widget.session.isLocalBackend
        ? widget.session.processIcons
        : null;
    final showIcon = widget.prefs.connectionsShowProcessIcon;
    final showAppName = widget.prefs.connectionsShowAppName;

    return RepaintBoundary(
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          for (final (groupIndex, group) in groups.indexed)
            MultiSliver(
              pushPinnedChildren: true,
              children: [
                SliverPinnedHeader(
                  child: _StaggeredTabItem(
                    index: groupIndex,
                    child: RepaintBoundary(
                      child: ConnectionGroupHeader(
                        summary: group,
                        expanded: cn.isExpanded(group.key),
                        onToggle: () => cn.toggleGroup(group.key),
                        onCloseAll: widget.tab == ConnectionsTab.active
                            ? () => _closeGroup(group)
                            : null,
                        onClearAll: widget.tab == ConnectionsTab.closed
                            ? () => _clearClosedGroup(group)
                            : null,
                        processIcons: processIcons,
                        showIcon: showIcon,
                        showAppName: showAppName,
                      ),
                    ),
                  ),
                ),
                if (cn.isExpanded(group.key))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                    sliver: Builder(
                      builder: (_) {
                        final ids = cn.groupMemberIds(group.key);
                        return SliverList.builder(
                          itemCount: ids.length,
                          itemBuilder: (context, index) {
                            final row = cn.groupMemberAt(group.key, index);
                            if (row == null) {
                              return const SizedBox(height: 60);
                            }
                            return _StaggeredTabItem(
                              index: groupIndex + index + 1,
                              child: Padding(
                                key: ValueKey('grp::${group.key}::${row.id}'),
                                padding: const EdgeInsets.only(bottom: 6),
                                child: ConnectionTile(
                                  row: row,
                                  // Members sit under the group's process
                                  // header, so the per-row icon and process
                                  // prefix are redundant.
                                  showIcon: false,
                                  hideProcess: true,
                                  compact: true,
                                  onTap: () => widget.onTap(row),
                                  onClose: () => widget.onClose(row.id),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}
