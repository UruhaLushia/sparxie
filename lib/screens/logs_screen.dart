import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../controller.dart' as ctl;
import '../rust_api.dart' as rust;

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _maxBuffer = 2000;
  static const _levels = ['info', 'debug', 'warning', 'error', 'silent'];

  final Queue<rust.LogEntry> _buffer = Queue<rust.LogEntry>();
  final ValueNotifier<int> _revision = ValueNotifier(0);
  final ScrollController _scroll = ScrollController();

  ctl.Controller? _activeKey;
  StreamSubscription<rust.LogEntry>? _sub;
  Timer? _retry;
  Timer? _flushTimer;
  String _level = 'info';
  String _filter = '';
  bool _paused = false;
  bool _follow = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _scroll.addListener(_onScroll);
    _bind();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _scroll.removeListener(_onScroll);
    _sub?.cancel();
    _retry?.cancel();
    _flushTimer?.cancel();
    _scroll.dispose();
    _revision.dispose();
    super.dispose();
  }

  void _onStore() {
    if (!identical(widget.store.active, _activeKey)) _bind();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // SuperListView keeps offset 0 pinned at the top; we follow the bottom by
    // checking whether we're within a few rows of maxScrollExtent.
    final pos = _scroll.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (atBottom != _follow) {
      setState(() => _follow = atBottom);
    }
  }

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
    );
  }

  void _bind() {
    _activeKey = widget.store.active;
    _resubscribe();
  }

  void _resubscribe() {
    _sub?.cancel();
    _retry?.cancel();
    _sub = null;
    _retry = null;
    _buffer.clear();
    _revision.value++;
    if (mounted) setState(() => _error = null);
    final target = _target();
    if (target == null) {
      setState(() => _error = '请先在“后端”中添加一个 mihomo 实例');
      return;
    }
    final controller = _activeKey;
    _sub = rust.logsStream(target: target, level: _level).listen(
      (entry) {
        if (!mounted) return;
        if (!identical(_activeKey, controller)) return;
        if (_paused) return;
        _buffer.addLast(entry);
        while (_buffer.length > _maxBuffer) {
          _buffer.removeFirst();
        }
        _scheduleFlush();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _error = '$e');
        _retry = Timer(const Duration(seconds: 2), () {
          if (mounted && identical(_activeKey, controller)) _resubscribe();
        });
      },
      cancelOnError: true,
    );
  }

  // Coalesce bursty stream events into one rebuild every ~80 ms. A short
  // timer runs the flush between frames, avoiding the post-frame re-entry
  // that trips `debugFrameWasSentToEngine` / `parentDataDirty` asserts.
  void _scheduleFlush() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(milliseconds: 80), () {
      _flushTimer = null;
      if (!mounted) return;
      _revision.value++;
      if (_follow && _scroll.hasClients) {
        final pos = _scroll.position;
        if (pos.hasContentDimensions) {
          _scroll.jumpTo(pos.maxScrollExtent);
        }
      }
    });
  }

  void _setLevel(String level) {
    if (level == _level) return;
    setState(() => _level = level);
    _resubscribe();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  void _clear() {
    _buffer.clear();
    _revision.value++;
  }

  List<rust.LogEntry> _visibleEntries() {
    if (_filter.isEmpty) return _buffer.toList(growable: false);
    final f = _filter.toLowerCase();
    return _buffer
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            tooltip: _paused ? '继续' : '暂停',
            onPressed: _togglePause,
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: _buffer.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '过滤消息内容',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _filter = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final l in _levels)
                          ChoiceChip(
                            label: Text(l),
                            selected: _level == l,
                            onSelected: (_) => _setLevel(l),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
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
                        _error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _revision,
                builder: (_, _, _) {
                  final entries = _visibleEntries();
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        _buffer.isEmpty ? '暂无日志' : '没有匹配的日志',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }
                  return RepaintBoundary(
                    child: SuperListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                _scheduleFlush();
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              entry.level.isEmpty ? 'log' : entry.level,
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
        return (scheme.onErrorContainer, scheme.errorContainer);
      case 'warning':
      case 'warn':
        return (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        );
      case 'debug':
      case 'trace':
        return (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        );
      case 'info':
      default:
        return (scheme.onPrimaryContainer, scheme.primaryContainer);
    }
  }
}
