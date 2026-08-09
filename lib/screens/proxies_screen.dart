import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../rust_api.dart' as rust;
import '../session.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/app_background.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/page_body_transition.dart';
import '../widgets/proxies_settings_menu.dart';
import '../widgets/proxy_group_card.dart';
import '../widgets/proxy_group_header.dart';
import '../widgets/proxy_node_tile.dart';
import '../widgets/route_app_bar.dart';

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
  final Set<String> _testingGroup = <String>{};
  final Set<String> _expanded = <String>{};
  final Set<String> _searchOpen = <String>{};
  final Map<String, TextEditingController> _searchCtls =
      <String, TextEditingController>{};
  ({
    bool includeHidden,
    ProxiesLayout layout,
    bool showGroupIcons,
    ProxiesSort sort,
    int columns,
    bool cardColored,
    bool cardShowDelay,
    bool groupByProvider,
  })?
  _prefsSnapshot;
  var _active = true;

  @override
  void initState() {
    super.initState();
    _syncRelevantPrefs();
    widget.prefs.addListener(_onPrefs);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = isUiActive(context);
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_onPrefs);
    for (final c in _searchCtls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPrefs() {
    _syncRelevantPrefs();
  }

  void _syncRelevantPrefs() {
    final next = (
      includeHidden: widget.prefs.proxiesShowHiddenGroups,
      layout: widget.prefs.proxiesLayout,
      showGroupIcons: widget.prefs.proxiesShowGroupIcons,
      sort: widget.prefs.proxiesSort,
      columns: widget.prefs.proxiesColumns,
      cardColored: widget.prefs.proxiesCardColored,
      cardShowDelay: widget.prefs.proxiesCardShowDelay,
      groupByProvider: widget.prefs.proxiesGroupByProvider,
    );
    final previous = _prefsSnapshot;
    if (previous == next) return;
    _prefsSnapshot = next;
    if (previous == null ||
        previous.includeHidden != next.includeHidden ||
        previous.sort != next.sort ||
        previous.groupByProvider != next.groupByProvider) {
      _syncProxyCatalogOptions();
    }
    if (previous != null && mounted && _active) setState(() {});
  }

  void _syncProxyCatalogOptions() {
    widget.session.setProxyCatalogOptions(
      includeHidden: widget.prefs.proxiesShowHiddenGroups,
      memberSort: _memberSort(widget.prefs.proxiesSort),
      groupByProvider: widget.prefs.proxiesGroupByProvider,
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
        if (_searchOpen.remove(name)) _searchCtls[name]?.clear();
      } else {
        _expanded.add(name);
        expanded = true;
      }
    });
    if (expanded) unawaited(widget.session.ensureProxyGroupMembers(name, 0, 0));
  }

  void _toggleSearch(ProxyGroup group) {
    final name = group.name;
    var opened = false;
    setState(() {
      if (_searchOpen.remove(name)) {
        _searchCtls[name]?.clear();
      } else {
        _searchOpen.add(name);
        _searchCtls.putIfAbsent(name, TextEditingController.new);
        _expanded.add(name);
        opened = true;
      }
    });
    if (opened && group.memberCount > 0) {
      unawaited(
        widget.session.ensureProxyGroupMembers(name, 0, group.memberCount - 1),
      );
    }
  }

  rust.BackendTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.backendTargetForController(c);
  }

  Future<String> _loadNodeDetails(String name) async {
    final target = _target();
    if (target == null) throw StateError('当前没有可用的控制器');
    return rust.controllerProxyDetail(target: target, name: name);
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
    await _setMember(group, name, fixed: false);
  }

  Future<void> _toggleFixed(ProxyGroup group, String name) async {
    await _setMember(group, name, fixed: true);
  }

  Future<void> _setMember(
    ProxyGroup group,
    String name, {
    required bool fixed,
  }) async {
    if (fixed ? !group.canFixMembers : !group.canSelectOnTap) return;
    final target = _target();
    if (target == null) return;
    if (fixed && group.fixed.value == name) {
      await _unfix(group);
      return;
    }
    final previousNow = group.now.value;
    final previousFixed = group.fixed.value;
    widget.session.proxies.setNowOptimistic(group.name, name);
    if (fixed) {
      widget.session.proxies.setFixedOptimistic(group.name, name);
    }
    try {
      await rust.controllerSelectProxy(
        target: target,
        group: group.name,
        name: name,
      );
      if (widget.prefs.autoCloseOnSwitch) {
        // Fire-and-forget; mihomo emits the close itself, no need to block UI.
        switch (widget.prefs.closeMode) {
          case CloseMode.all:
            unawaited(rust.controllerCloseAllConnections(target: target));
          case CloseMode.group:
            unawaited(
              rust.controllerCloseConnectionsByChain(
                target: target,
                chain: group.name,
              ),
            );
        }
      }
      unawaited(widget.session.refreshProxies());
    } catch (e) {
      widget.session.proxies.setNowOptimistic(group.name, previousNow);
      if (fixed) {
        widget.session.proxies.setFixedOptimistic(group.name, previousFixed);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${fixed ? '固定' : '切换'}失败:$e')));
      }
    }
  }

  Future<void> _unfix(ProxyGroup group) async {
    final target = _target();
    if (target == null) return;
    final previous = group.fixed.value;
    widget.session.proxies.setFixedOptimistic(group.name, '');
    try {
      await rust.controllerUnfixProxy(target: target, name: group.name);
      unawaited(widget.session.refreshProxies());
    } catch (e) {
      widget.session.proxies.setFixedOptimistic(group.name, previous);
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
    final window = widget.session.proxies.currentMemberWindowRequest(
      group.name,
    );
    setState(() => _testingGroup.add(group.name));
    try {
      if (widget.prefs.delayTestUseGroupApi && !widget.session.isStash.value) {
        final delays = await rust.controllerGroupDelay(
          target: target,
          group: group.name,
          testUrl: testUrl,
          timeoutMs: widget.prefs.delayTestTimeoutMs,
          concurrency: widget.prefs.delayTestConcurrency,
        );
        widget.session.proxies.applyGroupDelay(delays);
        await _reloadDelayWindow(target, group, window);
      } else {
        await for (final event in rust.controllerProxyGroupDelayStream(
          target: target,
          group: group.name,
          testUrl: testUrl,
          timeoutMs: widget.prefs.delayTestTimeoutMs,
          concurrency: widget.prefs.delayTestConcurrency,
          memberSort: _memberSort(widget.prefs.proxiesSort),
          windowOffset: window?.offset ?? 0,
          windowLimit: window?.limit ?? 0,
          windowMembersHash: window?.membersHash ?? 0,
        )) {
          widget.session.proxies.applyProxyDelayEvent(
            group.name,
            event,
            applyWindow: !widget.prefs.proxiesGroupByProvider,
          );
        }
        if (widget.prefs.proxiesGroupByProvider) {
          await _reloadDelayWindow(target, group, window);
        }
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
    final window = widget.session.proxies.currentMemberWindowRequest(
      group.name,
    );
    try {
      final event = await rust.controllerProxyDelayWindow(
        target: target,
        group: group.name,
        name: name,
        testUrl: _resolveTestUrl(group),
        timeoutMs: widget.prefs.delayTestTimeoutMs,
        memberSort: _memberSort(widget.prefs.proxiesSort),
        windowOffset: window?.offset ?? 0,
        windowLimit: window?.limit ?? 0,
        windowMembersHash: window?.membersHash ?? 0,
      );
      widget.session.proxies.applyProxyDelayEvent(
        group.name,
        event,
        applyWindow: !widget.prefs.proxiesGroupByProvider,
      );
      if (widget.prefs.proxiesGroupByProvider) {
        await _reloadDelayWindow(target, group, window);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('proxy delay failed for $name: $e');
      widget.session.proxies.applyNodeDelay(name, 0);
    }
  }

  Future<void> _reloadDelayWindow(
    rust.BackendTarget target,
    ProxyGroup group,
    ProxyMemberWindowRequest? window,
  ) async {
    if (window == null || widget.prefs.proxiesSort != ProxiesSort.delay) return;
    final loaded = await rust.controllerProxyGroupMembers(
      target: target,
      group: group.name,
      offset: window.offset,
      limit: window.limit,
      memberSort: rust.ProxyMemberSort.delay,
      groupByProvider: widget.prefs.proxiesGroupByProvider,
    );
    widget.session.proxies.applyGroupMembers(
      group.name,
      window.membersHash,
      loaded.offset,
      loaded.entries,
      sections: loaded.sections,
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
          title: const Text('代理组'),
          flexibleSpace: const DesktopAppBarDragArea(),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: widget.session.refreshProxies,
              icon: const Icon(Icons.refresh),
            ),
            ProxiesSettingsMenu(prefs: widget.prefs),
          ],
        ),
      ),
      body: AppPageBodyTransition(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ActiveValueListenableBuilder<String?>(
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
                child: widget.prefs.proxiesLayout == ProxiesLayout.cards
                    ? _ProxyCardsBody(
                        session: widget.session,
                        prefs: widget.prefs,
                        onSelect: _select,
                        onToggleFixed: _toggleFixed,
                        loadNodeDetails: _loadNodeDetails,
                        onTestGroup: _testGroup,
                        onTestNode: _testNode,
                      )
                    : _ProxiesBody(
                        session: widget.session,
                        prefs: widget.prefs,
                        testingGroups: _testingGroup,
                        expanded: _expanded,
                        searchOpen: _searchOpen,
                        searchControllers: _searchCtls,
                        onToggle: _toggle,
                        onToggleSearch: _toggleSearch,
                        onSearchChanged: () => setState(() {}),
                        onSelect: _select,
                        onToggleFixed: _toggleFixed,
                        loadNodeDetails: _loadNodeDetails,
                        onTestGroup: _testGroup,
                        onTestNode: _testNode,
                      ),
              ),
            ],
          ),
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
    required this.searchOpen,
    required this.searchControllers,
    required this.onToggle,
    required this.onToggleSearch,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onToggleFixed,
    required this.loadNodeDetails,
    required this.onTestGroup,
    required this.onTestNode,
  });

  final MihomoSession session;
  final AppPrefs prefs;
  final Set<String> testingGroups;
  final Set<String> expanded;
  final Set<String> searchOpen;
  final Map<String, TextEditingController> searchControllers;
  final ValueChanged<String> onToggle;
  final ValueChanged<ProxyGroup> onToggleSearch;
  final VoidCallback onSearchChanged;
  final void Function(ProxyGroup, String) onSelect;
  final void Function(ProxyGroup, String) onToggleFixed;
  final Future<String> Function(String) loadNodeDetails;
  final void Function(ProxyGroup) onTestGroup;
  final Future<void> Function(ProxyGroup, String) onTestNode;

  @override
  State<_ProxiesBody> createState() => _ProxiesBodyState();
}

class _ProxiesBodyState extends State<_ProxiesBody> {
  static const double _tileExtent = 60;
  static const double _tileSpacing = 8;
  static const double _emptyExtent = 48;

  late List<ProxyGroup> _groups;
  final Map<String, _PendingMemberRange> _pendingMemberLoads = {};
  final ScrollController _scroll = ScrollController();
  bool _memberLoadScheduled = false;
  int _cols = 1;
  var _active = true;

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
      if (_active) {
        oldWidget.session.proxies.removeListener(_recompute);
        widget.session.proxies.addListener(_recompute);
      }
      _recompute();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = isUiActive(context);
    if (_active == active) return;
    _active = active;
    if (active) {
      widget.session.proxies.addListener(_recompute);
      _groups = widget.session.proxies.groups;
    } else {
      widget.session.proxies.removeListener(_recompute);
      _pendingMemberLoads.clear();
    }
  }

  @override
  void dispose() {
    if (_active) widget.session.proxies.removeListener(_recompute);
    _pendingMemberLoads.clear();
    _scroll.dispose();
    super.dispose();
  }

  void _queueMemberLoad(String group, int index) {
    if (!_active) return;
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
    if (!mounted || !_active) {
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
    _groups = next;
    if (_active) setState(() {});
  }

  String _queryFor(String name) {
    if (!widget.searchOpen.contains(name)) return '';
    final text = widget.searchControllers[name]?.text ?? '';
    return text.trim().toLowerCase();
  }

  double _gridExtentFor(ProxyGroup group) {
    final query = _queryFor(group.name);
    var count = group.memberCount;
    if (query.isNotEmpty) {
      count = 0;
      for (var i = 0; i < group.memberCount; i++) {
        final member = group.memberAt(i);
        if (member != null && member.name.toLowerCase().contains(query)) {
          count++;
        }
      }
    }
    if (count == 0) return _emptyExtent;
    final rows = (count + _cols - 1) ~/ _cols;
    return rows * (_tileExtent + _tileSpacing) + 16;
  }

  Future<void> _waitForFullMembers(ProxyGroup group) async {
    // ensureProxyGroupMembers only queues (returns early) while another load
    // for the group is in flight, so a single await isn't enough.
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (mounted &&
        _active &&
        !group.hasMemberRange(0, group.memberCount - 1) &&
        DateTime.now().isBefore(deadline)) {
      await widget.session.ensureProxyGroupMembers(
        group.name,
        0,
        group.memberCount - 1,
      );
      if (group.hasMemberRange(0, group.memberCount - 1)) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  Future<void> _locate(ProxyGroup group) async {
    if (!widget.expanded.contains(group.name)) widget.onToggle(group.name);
    await _waitForFullMembers(group);
    if (!mounted || !_active) return;
    final now = group.hidesExactNow ? '' : group.now.value;
    final query = _queryFor(group.name);
    var row = -1;
    var seen = 0;
    if (now.isNotEmpty) {
      for (var i = 0; i < group.memberCount; i++) {
        final member = group.memberAt(i);
        if (member == null) continue;
        if (query.isNotEmpty && !member.name.toLowerCase().contains(query)) {
          continue;
        }
        if (member.name == now) {
          row = seen ~/ _cols;
          break;
        }
        seen++;
      }
    }
    // The target's own header pins at the viewport top, so its extent cancels
    // out of the offset — only preceding groups contribute.
    var offset = 8.0;
    for (final g in _groups) {
      if (identical(g, group)) break;
      offset += ProxyGroupHeader.extentFor(
        searchOpen: widget.searchOpen.contains(g.name),
      );
      if (widget.expanded.contains(g.name)) offset += _gridExtentFor(g);
    }
    if (row >= 0) offset += 8 + row * (_tileExtent + _tileSpacing);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_active || !_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        offset.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      return Center(
        child: Text('暂无代理组', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _cols = _resolveColumns(constraints.maxWidth);
        return CustomScrollView(
          controller: _scroll,
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
                        searchOpen: widget.searchOpen.contains(group.name),
                        searchController: widget.searchControllers[group.name],
                        onToggle: () => widget.onToggle(group.name),
                        onTest: () => widget.onTestGroup(group),
                        onToggleSearch: () => widget.onToggleSearch(group),
                        onSearchChanged: (_) => widget.onSearchChanged(),
                        onLocate: () => unawaited(_locate(group)),
                      ),
                    ),
                  ),
                  if (widget.expanded.contains(group.name))
                    ActiveValueListenableBuilder<int>(
                      valueListenable: group.membersVersion,
                      builder: (_, _, _) => _membersSliver(group),
                    ),
                ],
              ),
            // Extend scroll content behind the bottom system gesture bar.
            SliverToBoxAdapter(
              child: SizedBox(
                height: 24 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _membersSliver(ProxyGroup group) {
    final query = _queryFor(group.name);
    if (query.isEmpty) {
      // SliverGrid virtualizes — only viewport-intersecting tiles build,
      // so a 200-node group expands instantly.
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        sliver: SliverGrid.builder(
          addRepaintBoundaries: false,
          addAutomaticKeepAlives: false,
          gridDelegate: _gridDelegate(),
          itemCount: group.memberCount,
          itemBuilder: (context, index) {
            final member = group.memberAt(index);
            if (member == null) {
              if (!isUiFastScrolling(context)) {
                _queueMemberLoad(group.name, index);
              }
              return const _ProxyNodePlaceholder();
            }
            return _deferredTile(group, member);
          },
        ),
      );
    }
    final matched = <ProxyMember>[];
    var loaded = true;
    for (var i = 0; i < group.memberCount; i++) {
      final member = group.memberAt(i);
      if (member == null) {
        loaded = false;
        continue;
      }
      if (member.name.toLowerCase().contains(query)) matched.add(member);
    }
    if (!loaded) {
      _queueMemberLoad(group.name, 0);
      _queueMemberLoad(group.name, group.memberCount - 1);
    }
    if (matched.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: _emptyExtent,
          child: Center(
            child: Text(
              loaded ? '无匹配节点' : '加载中…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      sliver: SliverGrid.builder(
        addRepaintBoundaries: false,
        addAutomaticKeepAlives: false,
        gridDelegate: _gridDelegate(),
        itemCount: matched.length,
        itemBuilder: (context, index) => _deferredTile(group, matched[index]),
      ),
    );
  }

  SliverGridDelegateWithFixedCrossAxisCount _gridDelegate() {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _cols,
      mainAxisSpacing: _tileSpacing,
      crossAxisSpacing: _tileSpacing,
      mainAxisExtent: _tileExtent,
    );
  }

  Widget _tile(ProxyGroup group, ProxyMember member) {
    return ProxyNodeTile(
      key: ValueKey('${group.name}::${member.name}'),
      group: group,
      member: member,
      loadDetails: () => widget.loadNodeDetails(member.name),
      onSelect: () => widget.onSelect(group, member.name),
      onToggleFixed: () => widget.onToggleFixed(group, member.name),
      onTestDelay: () => widget.onTestNode(group, member.name),
    );
  }

  Widget _deferredTile(ProxyGroup group, ProxyMember member) {
    return ScrollDeferredContent(
      key: ValueKey('${group.name}::${member.name}'),
      placeholder: const _ProxyNodePlaceholder(),
      child: _tile(group, member),
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

class _ProxyCardsBody extends StatefulWidget {
  const _ProxyCardsBody({
    required this.session,
    required this.prefs,
    required this.onSelect,
    required this.onToggleFixed,
    required this.loadNodeDetails,
    required this.onTestGroup,
    required this.onTestNode,
  });

  final MihomoSession session;
  final AppPrefs prefs;
  final void Function(ProxyGroup, String) onSelect;
  final void Function(ProxyGroup, String) onToggleFixed;
  final Future<String> Function(String) loadNodeDetails;
  final Future<void> Function(ProxyGroup) onTestGroup;
  final Future<void> Function(ProxyGroup, String) onTestNode;

  @override
  State<_ProxyCardsBody> createState() => _ProxyCardsBodyState();
}

class _ProxyCardsBodyState extends State<_ProxyCardsBody> {
  final List<ProxyGroup> _warmQueue = <ProxyGroup>[];
  final Set<ProxyGroup> _queuedGroups = <ProxyGroup>{};
  bool _warmScheduled = false;
  bool _warming = false;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = isUiActive(context);
    if (_active == active) return;
    _active = active;
    if (active && _warmQueue.isNotEmpty) _scheduleWarmDrain();
  }

  bool _initialMembersReady(ProxyGroup group, bool locateCurrent) {
    if (!locateCurrent) return group.memberAt(0) != null;
    final index = group.locatedMemberIndex;
    return index != null && (index < 0 || group.memberAt(index) != null);
  }

  Future<void> _ensureInitialMembers(ProxyGroup group) async {
    if (group.memberCount == 0) return;
    final locateCurrent =
        widget.prefs.proxiesCardAutoLocate &&
        !group.hidesExactNow &&
        group.now.value.isNotEmpty;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (mounted &&
        widget.session.proxies.groups.contains(group) &&
        !_initialMembersReady(group, locateCurrent)) {
      await widget.session.ensureProxyGroupMembers(
        group.name,
        0,
        0,
        locateCurrent: locateCurrent,
      );
      if (_initialMembersReady(group, locateCurrent) ||
          DateTime.now().isAfter(deadline))
        return;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  void _queueWarm(ProxyGroup group) {
    final locateCurrent =
        widget.prefs.proxiesCardAutoLocate &&
        !group.hidesExactNow &&
        group.now.value.isNotEmpty;
    if (group.memberCount == 0 ||
        _initialMembersReady(group, locateCurrent) ||
        !_queuedGroups.add(group)) {
      return;
    }
    _warmQueue.add(group);
    _scheduleWarmDrain();
  }

  void _scheduleWarmDrain() {
    if (!_active || _warmScheduled || _warming) return;
    _warmScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmScheduled = false;
      if (mounted) unawaited(_drainWarmQueue());
    });
  }

  Future<void> _drainWarmQueue() async {
    if (_warming) return;
    _warming = true;
    try {
      while (mounted && _active && _warmQueue.isNotEmpty) {
        final group = _warmQueue.removeAt(0);
        _queuedGroups.remove(group);
        await _ensureInitialMembers(group);
        // Spread bridge decoding across frames instead of warming every card
        // in one burst on the first proxy-page frame.
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    } finally {
      _warming = false;
    }
  }

  @override
  void dispose() {
    _warmQueue.clear();
    _queuedGroups.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ActiveListenableBuilder(
      listenable: widget.session.proxies,
      builder: (context, _) {
        final groups = widget.session.proxies.groups;
        if (groups.isEmpty) {
          return Center(
            child: Text('暂无代理组', style: Theme.of(context).textTheme.bodyMedium),
          );
        }
        return AppBackdropGroup(
          child: GridView.builder(
            // ProxyGroupCard places its boundary below the press transform, so
            // the grid should not add a duplicate boundary above it.
            addRepaintBoundaries: false,
            addAutomaticKeepAlives: false,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent:
                  widget.prefs.proxiesShowGroupIcons &&
                      !widget.prefs.proxiesCardShowDelay
                  ? 96
                  : 90,
            ),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              _queueWarm(group);
              return ProxyGroupCard(
                key: ValueKey(group.name),
                group: group,
                showIcon: widget.prefs.proxiesShowGroupIcons,
                colored: widget.prefs.proxiesCardColored,
                showDelay: widget.prefs.proxiesCardShowDelay,
                onTap: (sourceFocusNode) async {
                  await _ensureInitialMembers(group);
                  if (!context.mounted) return;
                  await showProxyGroupCardDetail(
                    context,
                    session: widget.session,
                    group: group,
                    showIcon: widget.prefs.proxiesShowGroupIcons,
                    colored: widget.prefs.proxiesCardColored,
                    showDelay: widget.prefs.proxiesCardShowDelay,
                    autoLocate: widget.prefs.proxiesCardAutoLocate,
                    onTestGroup: () => widget.onTestGroup(group),
                    onSelect: (name) => widget.onSelect(group, name),
                    onToggleFixed: (name) => widget.onToggleFixed(group, name),
                    onTestNode: (name) => widget.onTestNode(group, name),
                    loadNodeDetails: widget.loadNodeDetails,
                    sourceFocusNode: sourceFocusNode,
                  );
                  if (context.mounted) _queueWarm(group);
                },
              );
            },
          ),
        );
      },
    );
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
    final surfaceTheme = AppSurfaceTheme.of(context);
    final mark = scheme.onSurfaceVariant.withValues(alpha: 0.16);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceTheme.surfaceColor(
          scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(12),
        border: surfaceTheme.outlineBorder(
          scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.58,
                    child: _ProxyPlaceholderMark(height: 8, color: mark),
                  ),
                  const SizedBox(height: 7),
                  FractionallySizedBox(
                    widthFactor: 0.32,
                    child: _ProxyPlaceholderMark(height: 6, color: mark),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _ProxyPlaceholderMark(width: 30, height: 8, color: mark),
          ],
        ),
      ),
    );
  }
}

class _ProxyPlaceholderMark extends StatelessWidget {
  const _ProxyPlaceholderMark({
    this.width,
    required this.height,
    required this.color,
  });

  final double? width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    ),
  );
}
