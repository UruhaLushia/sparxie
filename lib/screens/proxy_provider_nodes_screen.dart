import 'dart:async';

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../session.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/proxy_node_tile.dart';
import '../widgets/route_app_bar.dart';

class ProxyProviderNodesScreen extends StatefulWidget {
  const ProxyProviderNodesScreen({
    super.key,
    required this.target,
    required this.providerName,
    required this.prefs,
  });

  final rust.BackendTarget target;
  final String providerName;
  final AppPrefs prefs;

  @override
  State<ProxyProviderNodesScreen> createState() =>
      _ProxyProviderNodesScreenState();
}

class _ProxyProviderNodesScreenState extends State<ProxyProviderNodesScreen> {
  List<ProxyMember> _nodes = const [];
  String _query = '';
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await rust.controllerProxyProviderNodes(
        target: widget.target,
        name: widget.providerName,
      );
      if (!mounted) return;
      final nodes = entries.map(ProxyMember.fromEntry).toList(growable: false);
      final previous = _nodes;
      setState(() => _nodes = nodes);
      if (previous.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _disposeNodes(previous),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = formatError(error);
      setState(() => _error = message);
      if (_nodes.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刷新节点失败：$message')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ProxyMember> get _visibleNodes {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _nodes;
    return _nodes
        .where(
          (node) =>
              node.name.toLowerCase().contains(query) ||
              node.type.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _visibleNodes;
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: Text(widget.providerName),
          flexibleSpace: const DesktopAppBarDragArea(),
          actions: [
            IconButton(
              tooltip: '刷新节点',
              onPressed: _loading ? null : _refresh,
              icon: _loading && _nodes.isNotEmpty
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
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
              child: Row(
                children: [
                  Expanded(
                    child: CompactSearchField(
                      hintText: '搜索节点名称或类型',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _query.trim().isEmpty
                        ? '${_nodes.length} 个节点'
                        : '${nodes.length} / ${_nodes.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, nodes)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<ProxyMember> nodes) {
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
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (nodes.isEmpty) {
      return Center(
        child: Text(
          _nodes.isEmpty ? '暂无节点' : '没有匹配的节点',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return GridView.builder(
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
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final member = nodes[index];
        return ScrollDeferredContent(
          key: ValueKey('${widget.providerName}::${member.name}::$index'),
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
