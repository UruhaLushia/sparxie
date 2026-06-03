import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../rust_api.dart' as rust;
import '../session.dart';
import '../widgets/proxies_settings_menu.dart';
import '../widgets/proxy_group_header.dart';
import '../widgets/proxy_node_tile.dart';

class ProxiesScreen extends StatefulWidget {
  const ProxiesScreen({
    super.key,
    required this.store,
    required this.session,
    required this.prefs,
  });

  final ctl.ControllerStore store;
  final MihomoSession session;
  final AppPrefs prefs;

  @override
  State<ProxiesScreen> createState() => _ProxiesScreenState();
}

class _ProxiesScreenState extends State<ProxiesScreen> {
  String _filter = '';
  final Set<String> _testingGroup = <String>{};
  final Set<String> _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _syncProxyCatalogOptions();
    widget.prefs.addListener(_onPrefs);
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    _syncProxyCatalogOptions();
    if (mounted) setState(() {});
  }

  void _syncProxyCatalogOptions() {
    widget.session.setProxyCatalogOptions(
      includeHidden: widget.prefs.proxiesShowHiddenGroups,
      filter: _filter,
      memberSort: _memberSort(widget.prefs.proxiesSort),
    );
  }

  static rust.ProxyMemberSort _memberSort(ProxiesSort sort) => switch (sort) {
    ProxiesSort.original => rust.ProxyMemberSort.original,
    ProxiesSort.name => rust.ProxyMemberSort.name,
    ProxiesSort.delay => rust.ProxyMemberSort.delay,
  };

  void _toggle(String name) {
    var expanded = false;
    setState(() {
      if (_expanded.remove(name)) {
        widget.session.proxies.releaseGroupMembers(name);
      } else {
        _expanded.add(name);
        expanded = true;
      }
    });
    if (expanded) unawaited(widget.session.ensureProxyGroupMembers(name, 0, 0));
  }

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
      allowInsecure: c.allowInsecure,
    );
  }

  /// Resolve the URL used for a group's delay test, honoring scope:
  /// `group` first tries the group-level `testUrl`, falling back to global.
  String _resolveTestUrl(ProxyGroup group) {
    if (widget.prefs.delayTestScope == DelayTestScope.group &&
        group.testUrl.isNotEmpty) {
      return group.testUrl;
    }
    return widget.prefs.delayTestUrl;
  }

  Future<void> _select(ProxyGroup group, String name) async {
    final target = _target();
    if (target == null) return;
    // Tapping the already-pinned node releases the fix instead of
    // re-fixing it — the same gesture toggles back to automatic selection.
    if (group.fixed.value == name) {
      await _unfix(group);
      return;
    }
    final previous = group.now.value;
    widget.session.proxies.setNowOptimistic(group.name, name);
    try {
      await rust.selectProxy(target: target, group: group.name, name: name);
      if (widget.prefs.autoCloseOnSwitch) {
        // Fire-and-forget; mihomo emits the close itself, no need to block UI.
        switch (widget.prefs.closeMode) {
          case CloseMode.all:
            unawaited(rust.closeAllConnections(target: target));
          case CloseMode.group:
            unawaited(
              rust.closeConnectionsByChain(target: target, chain: group.name),
            );
        }
      }
      unawaited(widget.session.refreshProxies());
    } catch (e) {
      widget.session.proxies.setNowOptimistic(group.name, previous);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('切换失败:$e')));
      }
    }
  }

  Future<void> _unfix(ProxyGroup group) async {
    final target = _target();
    if (target == null) return;
    try {
      await rust.unfixProxy(target: target, name: group.name);
      unawaited(widget.session.refreshProxies());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('取消固定失败:$e')));
      }
    }
  }

  Future<void> _testGroup(ProxyGroup group) async {
    final target = _target();
    if (target == null || _testingGroup.contains(group.name)) return;
    final testUrl = _resolveTestUrl(group);
    setState(() => _testingGroup.add(group.name));
    try {
      if (widget.prefs.delayTestUseGroupApi) {
        final delays = await rust.groupDelay(
          target: target,
          group: group.name,
          testUrl: testUrl,
          timeoutMs: widget.prefs.delayTestTimeoutMs,
          concurrency: widget.prefs.delayTestConcurrency,
        );
        widget.session.proxies.applyGroupDelay(delays);
      } else {
        final delays = await rust.proxyGroupBatchDelay(
          target: target,
          group: group.name,
          testUrl: testUrl,
          timeoutMs: widget.prefs.delayTestTimeoutMs,
          concurrency: widget.prefs.delayTestConcurrency,
        );
        widget.session.proxies.applyProxyDelay(delays);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('测速失败:$e')));
      }
    } finally {
      if (mounted) setState(() => _testingGroup.remove(group.name));
    }
  }

  Future<void> _testNode(ProxyGroup group, String name) async {
    final target = _target();
    if (target == null) return;
    try {
      final ms = await rust.proxyDelay(
        target: target,
        name: name,
        testUrl: _resolveTestUrl(group),
        timeoutMs: widget.prefs.delayTestTimeoutMs,
      );
      widget.session.proxies.applyNodeDelay(name, ms.toInt());
    } catch (_) {
      widget.session.proxies.applyNodeDelay(name, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('代理组'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => _SearchDialog(initial: _filter),
              );
              if (result != null) {
                setState(() => _filter = result);
                _syncProxyCatalogOptions();
              }
            },
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: widget.session.refreshProxies,
            icon: const Icon(Icons.refresh),
          ),
          ProxiesSettingsMenu(prefs: widget.prefs),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_filter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.filter_alt, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '筛选:$_filter',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _filter = '');
                        _syncProxyCatalogOptions();
                      },
                      child: const Text('清除'),
                    ),
                  ],
                ),
              ),
            ValueListenableBuilder<String?>(
              valueListenable: widget.session.error,
              builder: (_, err, _) {
                if (err == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: _ProxiesBody(
                session: widget.session,
                prefs: widget.prefs,
                testingGroups: _testingGroup,
                expanded: _expanded,
                onToggle: _toggle,
                onSelect: _select,
                onTestGroup: _testGroup,
                onTestNode: _testNode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxiesBody extends StatefulWidget {
  const _ProxiesBody({
    required this.session,
    required this.prefs,
    required this.testingGroups,
    required this.expanded,
    required this.onToggle,
    required this.onSelect,
    required this.onTestGroup,
    required this.onTestNode,
  });

  final MihomoSession session;
  final AppPrefs prefs;
  final Set<String> testingGroups;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;
  final void Function(ProxyGroup, String) onSelect;
  final void Function(ProxyGroup) onTestGroup;
  final void Function(ProxyGroup, String) onTestNode;

  @override
  State<_ProxiesBody> createState() => _ProxiesBodyState();
}

class _ProxiesBodyState extends State<_ProxiesBody> {
  late List<ProxyGroup> _groups;
  final Map<String, _PendingMemberRange> _pendingMemberLoads = {};
  bool _memberLoadScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.session.proxies.addListener(_recompute);
    _groups = widget.session.proxies.groups;
  }

  @override
  void didUpdateWidget(covariant _ProxiesBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.proxies.removeListener(_recompute);
      widget.session.proxies.addListener(_recompute);
      _recompute();
    }
  }

  @override
  void dispose() {
    widget.session.proxies.removeListener(_recompute);
    _pendingMemberLoads.clear();
    super.dispose();
  }

  void _queueMemberLoad(String group, int index) {
    final pending = _pendingMemberLoads[group];
    if (pending == null) {
      _pendingMemberLoads[group] = _PendingMemberRange(index);
    } else {
      pending.include(index);
    }
    if (_memberLoadScheduled) return;
    _memberLoadScheduled = true;
    scheduleMicrotask(_flushMemberLoads);
  }

  void _flushMemberLoads() {
    _memberLoadScheduled = false;
    if (!mounted) {
      _pendingMemberLoads.clear();
      return;
    }
    final pending = Map<String, _PendingMemberRange>.of(_pendingMemberLoads);
    _pendingMemberLoads.clear();
    for (final entry in pending.entries) {
      final range = entry.value;
      unawaited(
        widget.session.ensureProxyGroupMembers(
          entry.key,
          range.first,
          range.last,
        ),
      );
    }
  }

  void _recompute() {
    final next = widget.session.proxies.groups;
    if (identical(_groups, next)) return;
    setState(() {
      _groups = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      return Center(
        child: Text(
          widget.session.proxies.groups.isEmpty ? '暂无代理组' : '没有匹配的项',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _resolveColumns(constraints.maxWidth);
        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            for (final group in _groups)
              MultiSliver(
                pushPinnedChildren: true,
                children: [
                  SliverPinnedHeader(
                    child: RepaintBoundary(
                      child: ProxyGroupHeader(
                        group: group,
                        showIcon: widget.prefs.proxiesShowGroupIcons,
                        testing: widget.testingGroups.contains(group.name),
                        expanded: widget.expanded.contains(group.name),
                        onToggle: () => widget.onToggle(group.name),
                        onTest: () => widget.onTestGroup(group),
                      ),
                    ),
                  ),
                  // SliverGrid virtualizes — only viewport-intersecting tiles
                  // build, so a 200-node group expands instantly.
                  if (widget.expanded.contains(group.name))
                    ValueListenableBuilder<int>(
                      valueListenable: group.membersVersion,
                      builder: (_, _, _) => SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                mainAxisExtent: 60,
                              ),
                          itemCount: group.memberCount,
                          itemBuilder: (context, index) {
                            final member = group.memberAt(index);
                            if (member == null) {
                              _queueMemberLoad(group.name, index);
                              return const _ProxyNodePlaceholder();
                            }
                            return ProxyNodeTile(
                              key: ValueKey('${group.name}::${member.name}'),
                              name: member.name,
                              type: member.type,
                              delay: member.delay,
                              nowListenable: group.now,
                              fixedListenable: group.fixed,
                              onSelect: () =>
                                  widget.onSelect(group, member.name),
                              onTestDelay: () =>
                                  widget.onTestNode(group, member.name),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  int _resolveColumns(double width) {
    final manual = widget.prefs.proxiesColumns;
    if (manual > 0) return manual;
    if (width >= 1100) return 4;
    if (width >= 800) return 3;
    if (width >= 520) return 2;
    return 1;
  }
}

class _PendingMemberRange {
  _PendingMemberRange(int index) : first = index, last = index;

  int first;
  int last;

  void include(int index) {
    if (index < first) first = index;
    if (index > last) last = index;
  }
}

class _ProxyNodePlaceholder extends StatelessWidget {
  const _ProxyNodePlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.initial});
  final String initial;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('搜索'),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '组名或节点',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('清除'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctl.text.trim()),
          child: const Text('应用'),
        ),
      ],
    );
  }
}
