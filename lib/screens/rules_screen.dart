import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../widgets/active_listenable_builder.dart';
import '../widgets/app_background.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/rule_context_menu.dart';
import '../widgets/rule_details_panel.dart';

/// Read-only view of the active backend's routing rules.
///
/// Rulesets stay in the backend cache; this screen only holds the visible
/// window and requests another window as the user scrolls.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  Widget build(BuildContext context) {
    return ActiveListenableSelector<ctl.Controller?>(
      listenable: store,
      selector: () => store.active,
      builder: (_, activeController, _) =>
          _RulesView(key: ValueKey((store, activeController)), store: store),
    );
  }
}

class _RulesView extends StatefulWidget {
  const _RulesView({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<_RulesView> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<_RulesView> {
  static const int _windowOverscan = 5;
  static const int _windowRefetchMargin = 2;
  static const int _initialWindowLimit = 48;
  static const double _rowHeight = _ruleCardHeight + _ruleItemSpacing;
  static const Duration _filterDebounce = Duration(milliseconds: 200);

  final ScrollController _scrollController = ScrollController();

  ctl.Controller? _activeKey;
  bool _loading = false;
  String? _error;
  String _filter = '';
  Timer? _filterTimer;
  var _filterPending = false;

  int _total = 0;
  int _filtered = 0;

  int _offset = 0;
  ({int offset, int limit})? _requestedWindow;
  int _windowEpoch = 0;
  final List<rust.RuleEntry> _window = <rust.RuleEntry>[];
  bool _scheduled = false;
  var _active = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bind();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = isUiActive(context);
    if (_active == active) return;
    _active = active;
    if (!active) {
      _filterTimer?.cancel();
      _filterTimer = null;
      return;
    }
    if (_filterPending) {
      unawaited(_applyFilter());
    } else {
      _scheduleEnsureWindow();
    }
  }

  @override
  void dispose() {
    _filterTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback update) {
    if (_active) {
      setState(update);
    } else {
      update();
    }
  }

  rust.BackendTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.backendTargetForController(c);
  }

  void _bind() {
    _filterTimer?.cancel();
    _filterTimer = null;
    _filterPending = false;
    _activeKey = widget.store.active;
    _resetWindow();
    if (_activeKey == null) {
      setState(() => _error = '请先在“后端”中添加一个后端');
      return;
    }
    unawaited(_load());
  }

  void _resetWindow() {
    _windowEpoch++;
    _offset = 0;
    _requestedWindow = null;
    _window.clear();
    _total = 0;
    _filtered = 0;
  }

  /// (Re)fetch the full ruleset into the backend cache, then load the head
  /// window. Used on bind, controller switch, and manual refresh.
  Future<void> _load({bool force = false}) async {
    final target = _target();
    if (target == null) return;
    final loadEpoch = ++_windowEpoch;
    final requestedFilter = _filter;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await rust.controllerRulesLoad(
        target: target,
        filter: requestedFilter,
        force: force,
      );
      if (!_isCurrent(loadEpoch)) return;
      if (requestedFilter != _filter) {
        _filterPending = true;
        return;
      }
      _total = summary.total;
      _filtered = summary.filtered;
      await _fetchWindow(0, _initialLimit(), epoch: loadEpoch);
    } catch (e) {
      if (_isCurrent(loadEpoch)) {
        _updateState(() => _error = _formatError(e));
      }
    } finally {
      if (_isCurrent(loadEpoch)) {
        _updateState(() => _loading = false);
        if (_filterPending && _active) {
          unawaited(_applyFilter());
        } else {
          _scheduleEnsureWindow();
        }
      }
    }
  }

  void _onFilterChanged(String value) {
    _filter = value.trim();
    _filterPending = true;
    _filterTimer?.cancel();
    _filterTimer = Timer(_filterDebounce, () => unawaited(_applyFilter()));
  }

  Future<void> _applyFilter() async {
    _filterTimer = null;
    if (!_active) return;
    if (_loading) {
      _filterPending = true;
      return;
    }
    _filterPending = false;
    final target = _target();
    if (target == null) return;
    final filterEpoch = ++_windowEpoch;
    final requestedFilter = _filter;
    try {
      final summary = await rust.controllerRulesSetFilter(
        target: target,
        filter: requestedFilter,
      );
      if (!_isCurrent(filterEpoch)) return;
      if (requestedFilter != _filter) {
        _filterPending = true;
        return;
      }
      if (!_active) {
        _filterPending = true;
        return;
      }
      _total = summary.total;
      _filtered = summary.filtered;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      await _fetchWindow(0, _initialLimit(), epoch: filterEpoch);
      _scheduleEnsureWindow();
    } catch (_) {
      // Filter failures are non-fatal; the list just stays as-is.
    }
  }

  void _onScroll() {
    if (!_active || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _active) _ensureWindow();
    });
  }

  void _scheduleEnsureWindow() {
    if (!_active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active) _ensureWindow();
    });
  }

  void _ensureWindow() {
    if (!_active || !_scrollController.hasClients || _filtered == 0) return;
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
    final cachedEnd = _offset + _window.length;
    final covered =
        _window.isNotEmpty &&
        (safeFirst >= _offset + _windowRefetchMargin || _offset == 0) &&
        (safeLast < cachedEnd - _windowRefetchMargin || cachedEnd >= _filtered);
    final oversized = _window.length > desiredLimit * 2;
    final desiredWindow = (offset: desiredOffset, limit: desiredLimit);
    if (covered && !oversized) {
      _requestedWindow = desiredWindow;
      return;
    }
    if (desiredWindow == _requestedWindow) return;
    unawaited(_fetchWindow(desiredOffset, desiredLimit));
  }

  int _initialLimit() {
    if (!_scrollController.hasClients) {
      return _initialWindowLimit.clamp(0, _filtered).toInt();
    }
    final visibleRows =
        (_scrollController.position.viewportDimension / _rowHeight).ceil();
    return (visibleRows + _windowOverscan * 2).clamp(0, _filtered).toInt();
  }

  Future<void> _fetchWindow(int offset, int limit, {int? epoch}) async {
    final target = _target();
    final requestEpoch = epoch ?? _windowEpoch;
    final request = (offset: offset, limit: limit);
    _requestedWindow = request;
    if (target == null || limit <= 0) {
      if (mounted) _updateState(() => _window.clear());
      return;
    }
    try {
      final rows = await rust.controllerRulesWindow(
        target: target,
        offset: offset,
        limit: limit,
      );
      if (!_isCurrent(requestEpoch) || request != _requestedWindow) return;
      _updateState(() {
        _offset = offset;
        _window
          ..clear()
          ..addAll(rows);
      });
    } catch (_) {
      if (_isCurrent(requestEpoch) && request == _requestedWindow) {
        _requestedWindow = null;
      }
      // Silent — a later scroll or frame retriggers.
    }
  }

  bool _isCurrent(int epoch) =>
      mounted &&
      identical(widget.store.active, _activeKey) &&
      epoch == _windowEpoch;

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
      await rust.controllerRulesDisable(
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
        hitAt: r.hitAt,
        missCount: r.missCount,
        missAt: r.missAt,
        hasExtra: r.hasExtra,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('分流规则'),
          flexibleSpace: const DesktopAppBarDragArea(),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
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
                      child: AppBackdropGroup(
                        child: ListView.builder(
                          controller: _scrollController,
                          // RuleContextMenu isolates each real row below its
                          // press transform; avoid a duplicate automatic layer.
                          addRepaintBoundaries: false,
                          addAutomaticKeepAlives: false,
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
                              key: ValueKey(rule.index),
                              rule: rule,
                              onToggle: (v) => _toggle(rule, v),
                            );
                          },
                        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: _ruleItemSpacing),
      child: const _RuleSurface(child: SizedBox.expand()),
    );
  }
}

const _ruleRadius = BorderRadius.all(Radius.circular(12));
const _ruleCardHeight = 66.0;
const _ruleItemSpacing = 6.0;
const _ruleSwitchExclusionSize = Size(64, 42);

class _RuleSurface extends StatelessWidget {
  const _RuleSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return AppSurfaceBackdrop(
      borderRadius: _ruleRadius,
      grouped: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceTheme.surfaceColor(scheme.surfaceContainerLow, 0.05),
          borderRadius: _ruleRadius,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({super.key, required this.rule, required this.onToggle});

  final rust.RuleEntry rule;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = rule.hitRate;
    final meta = [
      if (rule.ruleType.isNotEmpty) rule.ruleType,
      if (rule.proxy.isNotEmpty) rule.proxy,
      if (rule.extraParams.isNotEmpty) rule.extraParams.join(', '),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: _ruleItemSpacing),
      child: RuleContextMenu(
        rule: rule,
        excludedTopRightSize: rule.hasExtra
            ? _ruleSwitchExclusionSize
            : Size.zero,
        child: SizedBox(
          width: double.infinity,
          height: _ruleCardHeight,
          child: _RuleSurface(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rule.payload.isEmpty ? 'Match' : rule.payload,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (rule.hasExtra)
                        CompactSwitch(
                          value: !rule.disabled,
                          onChanged: onToggle,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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
                            color: scheme.primaryContainer.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${rate.toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
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
        ),
      ),
    );
  }
}
