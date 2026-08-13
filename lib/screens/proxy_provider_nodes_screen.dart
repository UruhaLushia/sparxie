import 'dart:async';

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../controller_view_state.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/proxy_node_tile.dart';
import '../widgets/route_app_bar.dart';

typedef _WindowRequest = ({
  int offset,
  int limit,
  String query,
  bool showLoading,
  int generation,
});

class ProxyProviderNodesScreen extends StatefulWidget {
  const ProxyProviderNodesScreen({
    super.key,
    required this.target,
    required this.providerKey,
    required this.providerName,
    required this.prefs,
  });

  final rust.BackendTarget target;
  final String providerKey;
  final String providerName;
  final AppPrefs prefs;

  @override
  State<ProxyProviderNodesScreen> createState() =>
      _ProxyProviderNodesScreenState();
}

class _ProxyProviderNodesScreenState extends State<ProxyProviderNodesScreen> {
  static const _filterDebounce = Duration(milliseconds: 200);
  static const _itemExtent = 72.0;
  // Covers a typical wide-screen viewport before layout metrics are known;
  // later requests shrink back to the visible window plus overscan.
  static const _initialLimit = 128;
  static const _overscanRows = 3;

  final _scrollController = ScrollController();
  List<ProxyMember> _nodes = const [];
  Timer? _filterTimer;
  String _query = '';
  String? _error;
  bool _loading = false;
  bool _drainingWindowRequests = false;
  bool _windowScheduled = false;
  _WindowRequest? _pendingWindow;
  int _windowGeneration = 0;
  int _columns = 1;
  int _total = 0;
  int _filtered = 0;
  int _offset = 0;
  ({int offset, int limit})? _requestedWindow;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleWindow);
    _requestWindow(0, _initialLimit, showLoading: true);
  }

  void _onFilterChanged(String value) {
    _query = value.trim();
    _filterTimer?.cancel();
    _filterTimer = Timer(_filterDebounce, () {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _requestWindow(0, _initialLimit, showLoading: true);
    });
  }

  void _requestWindow(int offset, int limit, {bool showLoading = false}) {
    if (!mounted) return;
    final generation = ++_windowGeneration;
    _requestedWindow = (offset: offset, limit: limit);
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _pendingWindow = (
      offset: offset,
      limit: limit,
      query: _query,
      showLoading: showLoading || (_pendingWindow?.showLoading ?? false),
      generation: generation,
    );
    if (!_drainingWindowRequests) {
      unawaited(_drainWindowRequests());
    }
  }

  Future<void> _drainWindowRequests() async {
    _drainingWindowRequests = true;
    while (mounted && _pendingWindow != null) {
      final request = _pendingWindow!;
      _pendingWindow = null;
      try {
        final window = await rust.controllerProxyProviderNodes(
          target: widget.target,
          name: widget.providerKey,
          filter: request.query,
          offset: request.offset,
          limit: request.limit,
        );
        if (!_isCurrent(request)) continue;
        _applyWindow(window);
      } catch (error) {
        if (!_isCurrent(request)) continue;
        _handleWindowError(error);
      } finally {
        if (_isCurrent(request) &&
            request.showLoading &&
            _pendingWindow == null) {
          setState(() => _loading = false);
        }
      }
    }
    _drainingWindowRequests = false;
  }

  bool _isCurrent(_WindowRequest request) =>
      mounted &&
      request.generation == _windowGeneration &&
      request.query == _query;

  void _applyWindow(rust.ProxyProviderNodeWindow window) {
    final nodes = window.entries
        .map(ProxyMember.fromEntry)
        .toList(growable: false);
    final previous = _nodes;
    setState(() {
      _nodes = nodes;
      _total = window.total;
      _filtered = window.filtered;
      _offset = window.offset;
      _error = null;
    });
    if (previous.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _disposeNodes(previous),
      );
    }
    _scheduleWindow();
  }

  void _handleWindowError(Object error) {
    _requestedWindow = null;
    final message = formatError(error);
    setState(() => _error = message);
    if (_nodes.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刷新节点失败：$message')));
    }
  }

  void _scheduleWindow() {
    if (_windowScheduled) return;
    _windowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowScheduled = false;
      if (mounted) _ensureWindow();
    });
  }

  void _ensureWindow() {
    if (!_scrollController.hasClients || _filtered == 0) return;
    final (offset, limit) = _visibleWindow();
    final desiredWindow = (offset: offset, limit: limit);
    final loadedEnd = _offset + _nodes.length;
    final desiredEnd = offset + limit;
    final covered =
        _nodes.isNotEmpty && offset >= _offset && desiredEnd <= loadedEnd;
    final oversized = _nodes.length > limit * 2;
    if (covered && !oversized) {
      if (_drainingWindowRequests && desiredWindow != _requestedWindow) {
        _windowGeneration++;
        _pendingWindow = null;
        _requestedWindow = desiredWindow;
        if (_loading) setState(() => _loading = false);
      }
      return;
    }
    if (desiredWindow == _requestedWindow) return;
    _requestWindow(offset, limit);
  }

  (int, int) _visibleWindow() {
    if (!_scrollController.hasClients) return (0, _initialLimit);
    final position = _scrollController.position;
    final firstRow = (position.pixels / _itemExtent).floor();
    final visibleRows = (position.viewportDimension / _itemExtent).ceil();
    final startRow = (firstRow - _overscanRows).clamp(0, _filtered).toInt();
    final endRow = firstRow + visibleRows + _overscanRows;
    final offset = (startRow * _columns).clamp(0, _filtered).toInt();
    final end = (endRow * _columns).clamp(offset, _filtered).toInt();
    return (offset, (end - offset).clamp(1, 512).toInt());
  }

  void _updateColumns(double width) {
    final contentWidth = (width - 32).clamp(0.0, double.infinity);
    final columns = ((contentWidth + 8) / 368).ceil().clamp(1, 512).toInt();
    if (columns == _columns) return;
    _columns = columns;
    _scheduleWindow();
  }

  ProxyMember? _nodeAt(int index) {
    final local = index - _offset;
    if (local < 0 || local >= _nodes.length) return null;
    return _nodes[local];
  }

  @override
  Widget build(BuildContext context) {
    final countText = _query.isEmpty ? '$_total 个节点' : '$_filtered / $_total';
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: Text(widget.providerName),
          flexibleSpace: const DesktopAppBarDragArea(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CompactSearchField(
                      hintText: '搜索节点名称或类型',
                      onChanged: _onFilterChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    countText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _nodes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null && _nodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    _requestWindow(0, _initialLimit, showLoading: true),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_filtered == 0) {
      return Center(
        child: Text(
          _total == 0 ? '暂无节点' : '没有匹配的节点',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? _updateColumns(constraints.maxWidth) : null,
        );
        return GridView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 360,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 64,
          ),
          itemCount: _filtered,
          itemBuilder: (context, index) {
            final member = _nodeAt(index);
            if (member == null) return const _ProviderNodePlaceholder();
            return ScrollDeferredContent(
              key: ValueKey('${widget.providerKey}::${member.name}::$index'),
              placeholder: const _ProviderNodePlaceholder(),
              child: StandaloneProxyNodeTile(
                member: member,
                loadDetails: () => rust.controllerProxyDetail(
                  target: widget.target,
                  name: member.name,
                ),
                onTestDelay: () => _testNode(member),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _testNode(ProxyMember member) async {
    try {
      final delay = await rust.controllerProxyDelay(
        target: widget.target,
        name: member.name,
        testUrl: widget.prefs.delayTestUrl,
        timeoutMs: widget.prefs.delayTestTimeoutMs,
      );
      if (!mounted || !_nodes.contains(member)) return;
      member.updateDelay(delay.toInt());
    } catch (_) {
      if (!mounted || !_nodes.contains(member)) return;
      member.updateDelay(0);
    }
  }

  @override
  void dispose() {
    _windowGeneration++;
    _pendingWindow = null;
    _filterTimer?.cancel();
    _scrollController
      ..removeListener(_scheduleWindow)
      ..dispose();
    _disposeNodes(_nodes);
    super.dispose();
  }
}

void _disposeNodes(Iterable<ProxyMember> nodes) {
  for (final node in nodes) {
    node.dispose();
  }
}

class _ProviderNodePlaceholder extends StatelessWidget {
  const _ProviderNodePlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
