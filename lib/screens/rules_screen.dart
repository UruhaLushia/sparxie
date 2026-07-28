import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../widgets/compact_controls.dart';

/// Read-only view of the active backend's routing rules.
///
/// Rulesets run to thousands of entries, so the full list stays in Rust:
/// [rust.rulesLoad] fetches and caches it, [rust.rulesSetFilter] re-filters
/// in place, and this screen only ever holds a sliding window of rows pulled
/// via [rust.rulesWindow] as the user scrolls.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  static const int _windowOverscan = 5;
  static const int _windowRefetchMargin = 2;
  static const double _rowHeight = 86;
  static const Duration _filterDebounce = Duration(milliseconds: 200);

  final ScrollController _scrollController = ScrollController();

  ctl.Controller? _activeKey;
  bool _loading = false;
  String? _error;
  String _filter = '';
  Timer? _filterTimer;

  int _total = 0;
  int _filtered = 0;

  int _offset = 0;
  int _limit = 0;
  final List<rust.RuleEntry> _window = <rust.RuleEntry>[];
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _scrollController.addListener(_onScroll);
    _bind();
  }

  @override
  void dispose() {
    _filterTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!identical(widget.store.active, _activeKey)) _bind();
  }

  rust.BackendTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.backendTargetForController(c);
  }

  void _bind() {
    _activeKey = widget.store.active;
    _resetWindow();
    if (_activeKey == null) {
      setState(() => _error = '请先在“后端”中添加一个后端');
      return;
    }
    _load();
  }

  void _resetWindow() {
    _offset = 0;
    _limit = 0;
    _window.clear();
    _total = 0;
    _filtered = 0;
  }

  /// (Re)fetch the full ruleset into the backend cache, then load the head
  /// window. Used on bind, controller switch, and manual refresh.
  Future<void> _load() async {
    final target = _target();
    if (target == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await rust.rulesLoad(target: target, filter: _filter);
      if (!mounted || !identical(widget.store.active, _activeKey)) return;
      _total = summary.total;
      _filtered = summary.filtered;
      _offset = 0;
      _limit = _initialLimit();
      await _fetchWindow(_offset, _limit);
    } catch (e) {
      if (mounted) setState(() => _error = _formatError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scheduleEnsureWindow();
      }
    }
  }

  void _onFilterChanged(String value) {
    _filter = value.trim();
    _filterTimer?.cancel();
    _filterTimer = Timer(_filterDebounce, _applyFilter);
  }

  Future<void> _applyFilter() async {
    final target = _target();
    if (target == null) return;
    try {
      final summary = await rust.rulesSetFilter(
        target: target,
        filter: _filter,
      );
      if (!mounted || !identical(widget.store.active, _activeKey)) return;
      _total = summary.total;
      _filtered = summary.filtered;
      _offset = 0;
      _limit = _initialLimit();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      await _fetchWindow(_offset, _limit);
      _scheduleEnsureWindow();
    } catch (_) {
      // Filter failures are non-fatal; the list just stays as-is.
    }
  }

  void _onScroll() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _ensureWindow();
    });
  }

  void _scheduleEnsureWindow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureWindow();
    });
  }

  void _ensureWindow() {
    if (!_scrollController.hasClients || _filtered == 0) return;
    final pos = _scrollController.position;
    final firstIndex = (pos.pixels / _rowHeight).floor();
    final lastIndex =
        ((pos.pixels + pos.viewportDimension) / _rowHeight).ceil() - 1;
    final safeFirst = firstIndex.clamp(0, _filtered - 1).toInt();
    final safeLast = lastIndex.clamp(safeFirst, _filtered - 1).toInt();
    final desiredOffset = (safeFirst - _windowOverscan)
        .clamp(0, _filtered)
        .toInt();
    final end = (safeLast + 1 + _windowOverscan).clamp(0, _filtered).toInt();
    final desiredLimit = end - desiredOffset;
    final cachedEnd = _offset + _limit;
    final covered =
        _window.isNotEmpty &&
        safeFirst >= _offset + _windowRefetchMargin &&
        safeLast < cachedEnd - _windowRefetchMargin;
    final unchanged =
        desiredOffset == _offset &&
        desiredLimit == _limit &&
        _window.isNotEmpty;
    if (covered || unchanged) {
      return;
    }
    _offset = desiredOffset;
    _limit = desiredLimit;
    _fetchWindow(desiredOffset, desiredLimit);
  }

  int _initialLimit() {
    if (!_scrollController.hasClients) {
      return (_windowOverscan + 1).clamp(0, _filtered).toInt();
    }
    final visibleRows =
        (_scrollController.position.viewportDimension / _rowHeight).ceil();
    return (visibleRows + _windowOverscan * 2).clamp(0, _filtered).toInt();
  }

  Future<void> _fetchWindow(int offset, int limit) async {
    final target = _target();
    if (target == null || limit <= 0) {
      if (mounted) setState(() => _window.clear());
      return;
    }
    try {
      final rows = await rust.rulesWindow(
        target: target,
        offset: offset,
        limit: limit,
      );
      if (!mounted ||
          !identical(widget.store.active, _activeKey) ||
          offset != _offset ||
          limit != _limit) {
        return;
      }
      setState(() {
        _window
          ..clear()
          ..addAll(rows);
      });
    } catch (_) {
      // Silent — a later scroll or frame retriggers.
    }
  }

  rust.RuleEntry? _ruleAt(int index) {
    final local = index - _offset;
    if (local < 0 || local >= _window.length) return null;
    return _window[local];
  }

  Future<void> _toggle(rust.RuleEntry rule, bool enabled) async {
    final target = _target();
    if (target == null) return;
    // Optimistic: swap the cached entry's disabled flag locally. The backend
    // patches its own cache on success, so the next window fetch agrees.
    final local = _window.indexOf(rule);
    if (local >= 0) {
      setState(() => _window[local] = _withDisabled(rule, !enabled));
    }
    try {
      await rust.rulesDisable(
        target: target,
        index: rule.index,
        disabled: !enabled,
      );
    } catch (e) {
      if (!mounted) return;
      if (local >= 0 && local < _window.length) {
        setState(() => _window[local] = _withDisabled(rule, enabled));
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切换失败:${_formatError(e)}')));
    }
  }

  String _formatError(Object error) =>
      formatError(error, backendName: _activeKey?.name);

  static rust.RuleEntry _withDisabled(rust.RuleEntry r, bool disabled) =>
      rust.RuleEntry(
        index: r.index,
        ruleType: r.ruleType,
        payload: r.payload,
        proxy: r.proxy,
        extraParams: r.extraParams,
        disabled: disabled,
        hitCount: r.hitCount,
        missCount: r.missCount,
        hasExtra: r.hasExtra,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('分流规则'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: CompactSearchField(
                hintText: '筛选 规则 / 类型 / 出站',
                suffixText: '$_filtered/$_total',
                onChanged: _onFilterChanged,
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
                    Icon(Icons.warning_rounded, color: scheme.onErrorContainer),
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
              child: _loading && _window.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered == 0
                  ? Center(
                      child: Text(
                        _total == 0 ? '暂无规则' : '没有匹配的规则',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        itemExtent: _rowHeight,
                        itemCount: _filtered,
                        itemBuilder: (_, index) {
                          final rule = _ruleAt(index);
                          if (rule == null) return const _RulePlaceholder();
                          return _RuleTile(
                            rule: rule,
                            onToggle: (v) => _toggle(rule, v),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RulePlaceholder extends StatelessWidget {
  const _RulePlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.rule, required this.onToggle});

  final rust.RuleEntry rule;
  final ValueChanged<bool> onToggle;

  double? get _hitRate {
    final total = rule.hitCount + rule.missCount;
    return total > BigInt.zero ? rule.hitCount / total * 100 : null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = _hitRate;
    final meta = [
      if (rule.ruleType.isNotEmpty) rule.ruleType,
      if (rule.proxy.isNotEmpty) rule.proxy,
      if (rule.extraParams.isNotEmpty) rule.extraParams.join(', '),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.payload.isEmpty ? 'Match' : rule.payload,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rule.hasExtra)
                    CompactSwitch(value: !rule.disabled, onChanged: onToggle),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rate != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${rate.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
