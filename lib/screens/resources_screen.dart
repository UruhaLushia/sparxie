import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../utils.dart';
import '../widgets/section_panel.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({
    super.key,
    required this.store,
    this.compact = false,
  });

  final ctl.ControllerStore store;

  /// On phone the screen runs as a stand-alone route, so it owns its own
  /// AppBar. On the wide-cards main area it's already framed, so [compact]
  /// strips the AppBar to avoid stacked headers.
  final bool compact;

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProxyProviderSection(store: widget.store),
                const SizedBox(height: 16),
                _RuleProviderSection(store: widget.store),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.compact) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('外部资源')),
      body: body,
    );
  }
}

abstract class _ProviderSection<T> extends StatefulWidget {
  const _ProviderSection({required this.store});
  final ctl.ControllerStore store;
}

class _ProxyProviderSection extends _ProviderSection<_ProxyProvider> {
  const _ProxyProviderSection({required super.store});

  @override
  State<_ProxyProviderSection> createState() => _ProxyProviderSectionState();
}

class _RuleProviderSection extends _ProviderSection<_RuleProvider> {
  const _RuleProviderSection({required super.store});

  @override
  State<_RuleProviderSection> createState() => _RuleProviderSectionState();
}

class _ProxyProvider {
  _ProxyProvider({
    required this.name,
    required this.vehicleType,
    required this.proxies,
    required this.updatedAt,
  });
  final String name;
  final String vehicleType;
  final int proxies;
  final DateTime? updatedAt;
}

class _RuleProvider {
  _RuleProvider({
    required this.name,
    required this.vehicleType,
    required this.behavior,
    required this.format,
    required this.ruleCount,
    required this.updatedAt,
  });
  final String name;
  final String vehicleType;
  final String behavior;
  final String format;
  final int ruleCount;
  final DateTime? updatedAt;
}

class _ProxyProviderSectionState extends State<_ProxyProviderSection> {
  bool _loading = false;
  String? _error;
  final Set<String> _busy = <String>{};
  List<_ProxyProvider> _items = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _ProxyProviderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) _refresh();
  }

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
    );
  }

  Future<void> _refresh() async {
    final target = _target();
    if (target == null) {
      setState(() {
        _items = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await rust.proxyProviders(target: target);
      final root = jsonDecode(raw) as Map<String, dynamic>;
      final providers = asMap(root['providers']);
      final list = <_ProxyProvider>[];
      providers.forEach((name, value) {
        final data = asMap(value);
        // Hide the auto-generated "Compatible" provider that wraps inline proxies.
        if (data['vehicleType']?.toString().toLowerCase() == 'compatible') return;
        list.add(_ProxyProvider(
          name: name,
          vehicleType: data['vehicleType']?.toString() ?? '',
          proxies: (data['proxies'] is List) ? (data['proxies'] as List).length : 0,
          updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
        ));
      });
      list.sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(_ProxyProvider p) async {
    final target = _target();
    if (target == null) return;
    setState(() => _busy.add(p.name));
    try {
      await rust.proxyProviderUpdate(target: target, name: p.name);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} 更新失败:${formatError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(p.name));
    }
  }

  Future<void> _updateAll() async {
    for (final p in _items) {
      if (p.vehicleType.toLowerCase() == 'http') {
        await _update(p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: '代理订阅',
      icon: Icons.cloud_queue_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_items.any((p) => p.vehicleType.toLowerCase() == 'http'))
            IconButton(
              tooltip: '更新全部',
              onPressed: _busy.isNotEmpty || _loading ? null : _updateAll,
              icon: const Icon(Icons.cloud_sync_outlined, size: 20),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      child: _ProviderBody(
        loading: _loading && _items.isEmpty,
        error: _error,
        empty: _items.isEmpty,
        emptyText: '暂无代理订阅',
        children: [
          for (final p in _items)
            _ProxyProviderTile(
              provider: p,
              busy: _busy.contains(p.name),
              onUpdate: () => _update(p),
            ),
        ],
      ),
    );
  }
}

class _RuleProviderSectionState extends State<_RuleProviderSection> {
  bool _loading = false;
  String? _error;
  final Set<String> _busy = <String>{};
  List<_RuleProvider> _items = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _RuleProviderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) _refresh();
  }

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
    );
  }

  Future<void> _refresh() async {
    final target = _target();
    if (target == null) {
      setState(() {
        _items = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await rust.ruleProviders(target: target);
      final root = jsonDecode(raw) as Map<String, dynamic>;
      final providers = asMap(root['providers']);
      final list = <_RuleProvider>[];
      providers.forEach((name, value) {
        final data = asMap(value);
        list.add(_RuleProvider(
          name: name,
          vehicleType: data['vehicleType']?.toString() ?? '',
          behavior: data['behavior']?.toString() ?? '',
          format: data['format']?.toString() ?? '',
          ruleCount: asInt(data['ruleCount']),
          updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
        ));
      });
      list.sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(_RuleProvider p) async {
    final target = _target();
    if (target == null) return;
    setState(() => _busy.add(p.name));
    try {
      await rust.ruleProviderUpdate(target: target, name: p.name);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} 更新失败:${formatError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(p.name));
    }
  }

  Future<void> _updateAll() async {
    for (final p in _items) {
      if (p.vehicleType.toLowerCase() == 'http') {
        await _update(p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: '规则集',
      icon: Icons.rule,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_items.any((p) => p.vehicleType.toLowerCase() == 'http'))
            IconButton(
              tooltip: '更新全部',
              onPressed: _busy.isNotEmpty || _loading ? null : _updateAll,
              icon: const Icon(Icons.cloud_sync_outlined, size: 20),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      child: _ProviderBody(
        loading: _loading && _items.isEmpty,
        error: _error,
        empty: _items.isEmpty,
        emptyText: '暂无规则集',
        children: [
          for (final p in _items)
            _RuleProviderTile(
              provider: p,
              busy: _busy.contains(p.name),
              onUpdate: () => _update(p),
            ),
        ],
      ),
    );
  }
}

class _ProviderBody extends StatelessWidget {
  const _ProviderBody({
    required this.loading,
    required this.error,
    required this.empty,
    required this.emptyText,
    required this.children,
  });
  final bool loading;
  final String? error;
  final bool empty;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error!,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (empty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(emptyText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 18),
          children[i],
        ],
      ],
    );
  }
}

String _ago(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s 前';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m 前';
  if (diff.inHours < 24) return '${diff.inHours}h 前';
  return '${diff.inDays}d 前';
}

class _ProxyProviderTile extends StatelessWidget {
  const _ProxyProviderTile({
    required this.provider,
    required this.busy,
    required this.onUpdate,
  });
  final _ProxyProvider provider;
  final bool busy;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final updatable = provider.vehicleType.toLowerCase() == 'http';
    final updated =
        provider.updatedAt == null ? '' : _ago(provider.updatedAt!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  provider.vehicleType,
                  '${provider.proxies} 个节点',
                  if (updated.isNotEmpty) updated,
                ].join('  ·  '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (updatable)
          IconButton(
            tooltip: '更新',
            onPressed: busy ? null : onUpdate,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined, size: 20),
          ),
      ],
    );
  }
}

class _RuleProviderTile extends StatelessWidget {
  const _RuleProviderTile({
    required this.provider,
    required this.busy,
    required this.onUpdate,
  });
  final _RuleProvider provider;
  final bool busy;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final updatable = provider.vehicleType.toLowerCase() == 'http';
    final updated =
        provider.updatedAt == null ? '' : _ago(provider.updatedAt!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  provider.vehicleType,
                  if (provider.behavior.isNotEmpty) provider.behavior,
                  if (provider.format.isNotEmpty) provider.format,
                  '${provider.ruleCount} 条',
                  if (updated.isNotEmpty) updated,
                ].join('  ·  '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (updatable)
          IconButton(
            tooltip: '更新',
            onPressed: busy ? null : onUpdate,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined, size: 20),
          ),
      ],
    );
  }
}
