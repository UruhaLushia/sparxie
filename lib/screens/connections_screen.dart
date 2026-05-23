import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../session.dart';
import '../utils.dart';
import '../widgets/connection_detail_sheet.dart';
import '../widgets/connection_tile.dart';
import '../widgets/connections_settings_menu.dart';

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

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  String _filter = '';
  ConnectionsTab _tab = ConnectionsTab.active;

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.prefs.addListener(_onPrefsChanged);
    _pushSortToBackend();
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    _pushSortToBackend();
  }

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

  Future<void> _close(String id) async {
    final target = _target();
    if (target == null) return;
    widget.session.connections.optimisticRemove(id);
    try {
      await rust.closeConnection(target: target, id: id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关闭失败:${formatError(e)}')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关闭失败:${formatError(e)}')),
        );
      }
    }
  }

  void _showDetail(ConnectionRow row) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ConnectionDetailSheet(
        row: row,
        onClose: () => _close(row.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('连接'),
            const SizedBox(width: 8),
            ValueListenableBuilder<bool>(
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
              child: ValueListenableBuilder<ConnectionsTotals>(
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
          ValueListenableBuilder<bool>(
            valueListenable: widget.session.connectionsPaused,
            builder: (_, paused, _) => IconButton(
              tooltip: paused ? '继续' : '暂停',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  widget.session.connectionsPaused.value = !paused,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            ),
          ),
          ValueListenableBuilder<ConnectionsTotals>(
            valueListenable: widget.session.connectionsTotals,
            builder: (_, totals, _) => IconButton(
              tooltip: '关闭所有',
              visualDensity: VisualDensity.compact,
              onPressed:
                  totals.count == 0 ? null : () => _closeAll(totals.count),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ),
          ConnectionsSettingsMenu(prefs: widget.prefs),
        ],
      ),
      body: SafeArea(
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
                    final tabs = ListenableBuilder(
                      listenable: widget.session.connections,
                      builder: (context, _) {
                        final cn = widget.session.connections;
                        return SegmentedButton<ConnectionsTab>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
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
                          onSelectionChanged: (s) =>
                              setState(() => _tab = s.first),
                        );
                      },
                    );
                    final filter = TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: '筛选',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (v) => setState(() => _filter = v.trim()),
                    );
                    final sortField = ListenableBuilder(
                      listenable: widget.prefs,
                      builder: (context, _) =>
                          PopupMenuButton<ConnectionsSort>(
                        tooltip: '排序字段',
                        position: PopupMenuPosition.under,
                        initialValue: widget.prefs.connectionsSort,
                        onSelected: widget.prefs.setConnectionsSort,
                        itemBuilder: (_) => [
                          for (final s in ConnectionsSort.values)
                            CheckedPopupMenuItem<ConnectionsSort>(
                              value: s,
                              checked: widget.prefs.connectionsSort == s,
                              child: Text(_sortLabel(s)),
                            ),
                        ],
                        child: Container(
                          height: 36,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Text(
                                _sortLabel(widget.prefs.connectionsSort),
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.expand_more, size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                    final direction = ListenableBuilder(
                      listenable: widget.prefs,
                      builder: (context, _) => IconButton(
                        tooltip: widget.prefs.connectionsSortAsc
                            ? '升序'
                            : '降序',
                        onPressed: () => widget.prefs.setConnectionsSortAsc(
                          !widget.prefs.connectionsSortAsc,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              colorScheme.surfaceContainerHighest,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
            ValueListenableBuilder<String?>(
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
                          style:
                              TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: _ConnectionsList(
                session: widget.session,
                tab: _tab,
                filter: _filter,
                onTap: _showDetail,
                onClose: _close,
              ),
            ),
          ],
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
    required this.tab,
    required this.filter,
    required this.onTap,
    required this.onClose,
  });

  final MihomoSession session;
  final ConnectionsTab tab;
  final String filter;
  final ValueChanged<ConnectionRow> onTap;
  final ValueChanged<String> onClose;

  @override
  State<_ConnectionsList> createState() => _ConnectionsListState();
}

class _ConnectionsListState extends State<_ConnectionsList> {
  static const Duration _animDuration = Duration(milliseconds: 200);
  static const double _rowHeight = 96; // tile content + bottom padding + slack

  final ScrollController _scrollController = ScrollController();
  // Coalesce ensureWindow calls during fast scrolls — one call per frame.
  bool _scheduled = false;

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
    if (oldWidget.tab != widget.tab) {
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
  void dispose() {
    widget.session.connections.removeListener(_onChange);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _ensureWindow();
    });
  }

  /// Compute the list index near the scroll viewport's center and ask the
  /// notifier to make sure the cached window covers it.
  void _ensureWindow() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final centerPx = pos.pixels + pos.viewportDimension / 2;
    final centerIndex = (centerPx / _rowHeight).floor().clamp(0, 1 << 30);
    widget.session.connections.ensureWindow(widget.tab, centerIndex);
  }

  int _totalCount() {
    final cn = widget.session.connections;
    return widget.tab == ConnectionsTab.active
        ? cn.activeCount
        : cn.closedCount;
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalCount();
    if (total == 0) {
      return Center(
        child: Text(
          widget.tab == ConnectionsTab.active ? '暂无连接' : '暂无已关闭连接',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final filter = widget.filter;
    return RepaintBoundary(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        // Fixed-height items let ListView do exact scroll math without
        // measuring offscreen widgets.
        itemExtent: _rowHeight,
        itemCount: total,
        itemBuilder: (context, index) {
          final cn = widget.session.connections;
          final row = cn.rowAt(widget.tab, index);
          // When a filter is active, hide rows that don't match (they
          // remain in the virtual list space — ListView still shows the
          // gap, but the slot stays empty so the user perceives the
          // matching rows packed together visually within the window).
          // For now we keep filtering off the virtual scroll, treating
          // filter-misses identically to out-of-window slots.
          final visible = filter.isEmpty || (row != null && row.matches(filter));
          return _RowSlot(
            // Same key for the same row id keeps state across frames so
            // the AnimatedSwitcher inside doesn't re-trigger transitions.
            key: ValueKey(row?.id ?? 'idx::$index'),
            row: visible ? row : null,
            duration: _animDuration,
            onTap: row == null ? null : () => widget.onTap(row),
            onClose: row == null ? null : () => widget.onClose(row.id),
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
    this.onTap,
    this.onClose,
  });

  final ConnectionRow? row;
  final Duration duration;
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
        child: SizeTransition(
          sizeFactor: animation,
          child: child,
        ),
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
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
