import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../controller.dart' as ctl;
import '../rust_api.dart' as rust;
import '../session.dart';
import '../widgets/compact_controls.dart';

/// Renders the buffer owned by `MihomoSession` (`session.logs`). The
/// WebSocket is opened on controller connect — independent of this widget's
/// lifecycle — so navigating to "日志" shows already-cached lines instead of
/// waiting for a fresh subscription.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.store, required this.session});

  final ctl.ControllerStore store;
  final MihomoSession session;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _baseLevels = ['info', 'debug', 'warning', 'error', 'silent'];

  final ScrollController _scroll = ScrollController();
  Timer? _flushTimer;

  String _filter = '';
  List<rust.LogEntry> _visibleEntries = const <rust.LogEntry>[];
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.session.logs.addListener(_onLogs);
    _recomputeVisibleEntries();
  }

  @override
  void dispose() {
    widget.session.logs.removeListener(_onLogs);
    _scroll.removeListener(_onScroll);
    _flushTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onLogs() {
    if (!mounted) return;
    _recomputeVisibleEntries();
    setState(() {});
    _scheduleAutoScroll();
  }

  void _setFilter(String value) {
    final next = value.trim();
    if (next == _filter) return;
    _filter = next;
    _recomputeVisibleEntries();
    setState(() {});
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (atBottom != _follow) {
      setState(() => _follow = atBottom);
    }
  }

  // Defer follow-scroll until the rebuild from setState has materialized.
  void _scheduleAutoScroll() {
    if (!_follow) return;
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(milliseconds: 80), () {
      _flushTimer = null;
      if (!mounted) return;
      if (!_follow || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.hasContentDimensions) {
        _scroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  void _setLevel(String level) {
    if (level == widget.session.logsLevel) return;
    widget.session.setLogsLevel(level);
    setState(() {});
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

  void _recomputeVisibleEntries() {
    final all = widget.session.logs.entries;
    if (_filter.isEmpty) {
      _visibleEntries = all;
      return;
    }
    final f = _filter.toLowerCase();
    _visibleEntries = all
        .where(
          (e) =>
              e.message.toLowerCase().contains(f) ||
              e.level.toLowerCase().contains(f),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logs = widget.session.logs;
    final levels = widget.store.active?.type == ctl.BackendType.singBox
        ? const ['info', 'debug', 'trace', 'warning', 'error', 'silent']
        : _baseLevels;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: logs.paused,
            builder: (_, paused, _) => IconButton(
              tooltip: paused ? '继续' : '暂停',
              onPressed: _togglePause,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            ),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: logs.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
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
            ValueListenableBuilder<String?>(
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
                  final entries = _visibleEntries;
                  if (entries.isEmpty) {
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
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, index) =>
                          _LogTile(entry: entries[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _follow
          ? null
          : FloatingActionButton.small(
              tooltip: '回到底部',
              onPressed: () {
                setState(() => _follow = true);
                _scheduleAutoScroll();
              },
              child: const Icon(Icons.arrow_downward),
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final rust.LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (badgeFg, badgeBg) = _levelColors(entry.level, scheme);
    final ts = entry.time.isEmpty ? '' : entry.time;
    final level = entry.level.isEmpty ? 'log' : entry.level;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 68,
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                SelectableText(
                  entry.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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
