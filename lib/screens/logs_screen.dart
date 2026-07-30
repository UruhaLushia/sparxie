import 'dart:async';

import 'package:flutter/material.dart';
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

  final ScrollController _scroll = ScrollController();
  final ListController _listController = ListController();
  final Set<BigInt> _enteringIds = <BigInt>{};
  Timer? _flushTimer;

  late int _logsAppendRevision;
  String _filter = '';
  bool _follow = true;
  bool _active = true;
  bool _logsDirty = false;
  bool _autoScrolling = false;
  bool _windowScheduled = false;
  int _autoScrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _logsAppendRevision = widget.session.logs.appendRevision;
    _scroll.addListener(_onScroll);
    _listController.addListener(_scheduleEnsureWindow);
    widget.session.logs.addListener(_onLogs);
  }

  @override
  void dispose() {
    widget.session.logs.removeListener(_onLogs);
    widget.session.logs.setActive(false);
    _scroll.removeListener(_onScroll);
    _listController.removeListener(_scheduleEnsureWindow);
    _flushTimer?.cancel();
    _autoScrollGeneration++;
    _listController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    widget.session.logs.setActive(active);
    if (_active == active) return;
    _active = active;
    if (!active) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _enteringIds.clear();
      return;
    }
    if (_logsDirty) {
      _logsDirty = false;
      _scheduleEnsureWindow();
      _scheduleAutoScroll();
    }
  }

  void _onLogs() {
    if (!mounted) return;
    final logs = widget.session.logs;
    final appendChanged = logs.appendRevision != _logsAppendRevision;
    _logsAppendRevision = logs.appendRevision;
    if (!_active) {
      _enteringIds.clear();
      _logsDirty = true;
      return;
    }
    final latestAppendId = logs.latestAppendId;
    if (appendChanged && _follow && latestAppendId != null) {
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
    setState(() {});
    _scheduleEnsureWindow();
    _scheduleAutoScroll();
  }

  void _setFilter(String value) {
    final next = value.trim();
    if (next == _filter) return;
    _filter = next;
    _enteringIds.clear();
    widget.session.logs.setQuery(next);
  }

  void _onScroll() {
    _scheduleEnsureWindow();
    if (_autoScrolling) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (atBottom != _follow) {
      setState(() => _follow = atBottom);
      widget.session.logs.setFollowing(atBottom);
    }
  }

  void _scheduleEnsureWindow() {
    if (!_active || _windowScheduled) return;
    _windowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowScheduled = false;
      if (!mounted || !_active) return;
      if (!_listController.isAttached) return;
      final range = _listController.visibleRange;
      if (range == null) return;
      widget.session.logs.ensureWindow(range.$1, range.$2);
    });
  }

  // Defer follow-scroll until the rebuild from setState has materialized.
  void _scheduleAutoScroll() {
    if (!_active || !_follow) return;
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(milliseconds: 80), () {
      _flushTimer = null;
      if (!mounted || !_active) return;
      if (!_follow || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.hasContentDimensions) {
        final target = pos.maxScrollExtent;
        if ((target - pos.pixels).abs() < 1) return;
        if (target - pos.pixels > pos.viewportDimension * 2) {
          _scroll.jumpTo(target);
          _scheduleEnsureWindow();
          return;
        }
        final generation = ++_autoScrollGeneration;
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
                _onScroll();
              }),
        );
      }
    });
  }

  void _setLevel(String level) {
    if (level == widget.session.logsLevel) return;
    _enteringIds.clear();
    widget.session.setLogsLevel(level);
  }

  void _togglePause() {
    final paused = widget.session.logs.paused;
    paused.value = !paused.value;
  }

  void _clear() {
    widget.session.clearLogs();
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
            IconButton(
              tooltip: '清空',
              visualDensity: VisualDensity.compact,
              onPressed: logs.isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_outline),
            ),
            LogsSettingsMenu(prefs: widget.prefs),
          ],
        ),
      ),
      body: AppPageBodyTransition(
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
                child: Builder(
                  builder: (_) {
                    if (logs.filterLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (logs.length == 0) {
                      return Center(
                        child: Text(
                          logs.isEmpty ? '暂无日志' : '没有匹配的日志',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }
                    return RepaintBoundary(
                      child: SuperListView.builder(
                        controller: _scroll,
                        listController: _listController,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final entry = logs.rowAt(index);
                          if (entry == null) return const _LogPlaceholder();
                          return _AnimatedLogTile(
                            entry: entry,
                            animate: _enteringIds.contains(entry.id),
                          );
                        },
                      ),
                    );
                  },
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
              onPressed: () {
                setState(() => _follow = true);
                widget.session.logs.setFollowing(true);
                _scheduleAutoScroll();
              },
              child: const Icon(Icons.arrow_downward),
            ),
    );
  }
}

class _LogPlaceholder extends StatelessWidget {
  const _LogPlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 72);
}

class _AnimatedLogTile extends StatefulWidget {
  const _AnimatedLogTile({required this.entry, required this.animate});

  final rust.LogEntry entry;
  final bool animate;

  @override
  State<_AnimatedLogTile> createState() => _AnimatedLogTileState();
}

class _AnimatedLogTileState extends State<_AnimatedLogTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void didUpdateWidget(_AnimatedLogTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.id == oldWidget.entry.id) return;
    if (widget.animate) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _LogTile(entry: widget.entry);
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: _animation,
      child: child,
      builder: (context, child) {
        final progress = _animation.value;
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
    final scheme = Theme.of(context).colorScheme;
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        SelectableText(
                          entry.message,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.35),
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
