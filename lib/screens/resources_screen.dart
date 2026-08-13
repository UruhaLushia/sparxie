import 'dart:async';

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../utils.dart';
import '../widgets/active_listenable_builder.dart';
import '../widgets/app_page_route.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';
import 'proxy_provider_nodes_screen.dart';

class ResourcesScreen extends StatelessWidget {
  const ResourcesScreen({
    super.key,
    required this.store,
    required this.prefs,
    this.compact = false,
  });

  final ctl.ControllerStore store;
  final AppPrefs prefs;

  /// On phone the screen runs as a stand-alone route, so it owns its own
  /// AppBar. On the wide-cards main area it's already framed, so [compact]
  /// strips the AppBar to avoid stacked headers.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ActiveListenableSelector<ctl.Controller?>(
      listenable: store,
      selector: () => store.active,
      builder: (context, activeController, _) =>
          _buildScreen(context, activeController),
    );
  }

  Widget _buildScreen(BuildContext context, ctl.Controller? activeController) {
    final body = SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          MaxWidthContent(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProxyProviderSection(
                  key: ValueKey(('proxy', store, activeController)),
                  store: store,
                  prefs: prefs,
                ),
                const SizedBox(height: 16),
                _RuleProviderSection(
                  key: ValueKey(('rule', store, activeController)),
                  store: store,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (compact) return body;
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('外部资源'),
          flexibleSpace: const DesktopAppBarDragArea(),
        ),
      ),
      body: body,
    );
  }
}

class _ProxyProviderSection extends StatefulWidget {
  const _ProxyProviderSection({
    super.key,
    required this.store,
    required this.prefs,
  });

  final ctl.ControllerStore store;
  final AppPrefs prefs;

  @override
  State<_ProxyProviderSection> createState() => _ProxyProviderSectionState();
}

class _RuleProviderSection extends StatefulWidget {
  const _RuleProviderSection({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<_RuleProviderSection> createState() => _RuleProviderSectionState();
}

class _ProxyProvider {
  _ProxyProvider({
    required this.key,
    required this.name,
    required this.vehicleType,
    required this.proxies,
    required this.updatedAt,
    required this.updatable,
    required this.subscription,
  });

  factory _ProxyProvider.fromRust(rust.ProxyProviderEntry entry) {
    return _ProxyProvider(
      key: entry.key,
      name: entry.name,
      vehicleType: entry.vehicleType,
      proxies: entry.proxies,
      updatedAt: _parseDateTime(entry.updatedAt),
      updatable: entry.updatable,
      subscription: entry.hasSubscriptionInfo
          ? _SubscriptionInfo(
              upload: entry.subscriptionUpload,
              download: entry.subscriptionDownload,
              total: entry.subscriptionTotal,
              expire: entry.subscriptionExpire,
            )
          : null,
    );
  }

  final String key;
  final String name;
  final String vehicleType;
  final int proxies;
  final DateTime? updatedAt;
  final bool updatable;
  final _SubscriptionInfo? subscription;

  bool get nodesAvailable => proxies > 0;
}

class _SubscriptionInfo {
  const _SubscriptionInfo({
    required this.upload,
    required this.download,
    required this.total,
    required this.expire,
  });

  final BigInt upload;
  final BigInt download;
  final BigInt total;
  final BigInt expire;

  BigInt get used => upload + download;
}

class _RuleProvider {
  _RuleProvider({
    required this.key,
    required this.name,
    required this.vehicleType,
    required this.behavior,
    required this.format,
    required this.ruleCount,
    required this.updatedAt,
    required this.updatable,
  });

  factory _RuleProvider.fromRust(rust.RuleProviderEntry entry) {
    return _RuleProvider(
      key: entry.key,
      name: entry.name,
      vehicleType: entry.vehicleType,
      behavior: entry.behavior,
      format: entry.format,
      ruleCount: entry.ruleCount,
      updatedAt: _parseDateTime(entry.updatedAt),
      updatable: entry.updatable,
    );
  }

  final String key;
  final String name;
  final String vehicleType;
  final String behavior;
  final String format;
  final int ruleCount;
  final DateTime? updatedAt;
  final bool updatable;

  String get kind => vehicleType.toLowerCase();
}

DateTime? _parseDateTime(String value) =>
    value.isEmpty ? null : DateTime.tryParse(value);

rust.BackendTarget? _targetFor(ctl.ControllerStore store) {
  final controller = store.active;
  return controller == null
      ? null
      : rust.backendTargetForController(controller);
}

class _ProxyProviderSectionState extends State<_ProxyProviderSection> {
  bool _loading = false;
  String? _error;
  final Set<String> _busy = <String>{};
  List<_ProxyProvider> _items = const [];
  bool _updatingAll = false;

  bool get _isSurgeController =>
      widget.store.active?.type == ctl.BackendType.surgeController;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final target = _targetFor(widget.store);
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
      final entries = await rust.controllerProxyProviderCatalog(
        target: target,
        force: force,
      );
      final list = entries.map(_ProxyProvider.fromRust).toList(growable: false);
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(_ProxyProvider p) async {
    final target = _targetFor(widget.store);
    if (target == null || _updatingAll) return;
    setState(() => _busy.add(p.key));
    try {
      await rust.controllerProxyProviderUpdate(target: target, name: p.key);
      await _refresh(force: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} 更新失败:${_formatError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(p.key));
    }
  }

  void _openNodes(_ProxyProvider provider) {
    final target = _targetFor(widget.store);
    if (target == null) return;
    unawaited(
      Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ProxyProviderNodesScreen(
            target: target,
            providerKey: provider.key,
            providerName: provider.name,
            prefs: widget.prefs,
          ),
        ),
      ),
    );
  }

  Future<void> _updateAll() async {
    final target = _targetFor(widget.store);
    final providers = _items.where((p) => p.updatable).toList(growable: false);
    if (target == null || providers.isEmpty) return;
    final failures = <String>[];
    setState(() => _updatingAll = true);
    try {
      for (final provider in providers) {
        try {
          await rust.controllerProxyProviderUpdate(
            target: target,
            name: provider.key,
          );
        } catch (error) {
          failures.add('${provider.name}: ${_formatError(error)}');
        }
      }
      if (mounted) await _refresh(force: true);
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
    if (mounted && failures.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('有 ${failures.length} 项更新失败：${failures.first}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActiveListenableBuilder(
      listenable: widget.prefs,
      builder: (context, _) {
        final style = widget.prefs.proxyProviderStyle;
        return SectionPanel(
          title: _isSurgeController ? '策略组' : '代理订阅',
          icon: Icons.cloud_queue_outlined,
          trailing: _ProviderActions(
            hasUpdates: _items.any((provider) => provider.updatable),
            busy: _busy.isNotEmpty,
            loading: _loading,
            updatingAll: _updatingAll,
            onUpdateAll: _updateAll,
          ),
          child: _ProviderBody(
            loading: _loading && _items.isEmpty,
            error: _error,
            empty: _items.isEmpty,
            emptyText: _isSurgeController ? '暂无策略组资源' : '暂无代理订阅',
            children: [
              _ProxyProviderList(
                providers: _items,
                busy: _busy,
                updatesEnabled: !_updatingAll,
                liquid: style == ProxyProviderStyle.liquid,
                onUpdate: _update,
                onView: _openNodes,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatError(Object error) =>
      formatError(error, backendName: widget.store.active?.name);
}

class _RuleProviderSectionState extends State<_RuleProviderSection> {
  bool _loading = false;
  String? _error;
  final Set<String> _busy = <String>{};
  List<_RuleProvider> _items = const [];
  bool _updatingAll = false;

  bool get _isSurgeController =>
      widget.store.active?.type == ctl.BackendType.surgeController;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final target = _targetFor(widget.store);
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
      final entries = await rust.controllerRuleProviderCatalog(
        target: target,
        force: force,
      );
      final list = entries.map(_RuleProvider.fromRust).toList(growable: false);
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(_RuleProvider p) async {
    final target = _targetFor(widget.store);
    if (target == null || _updatingAll) return;
    setState(() => _busy.add(p.key));
    try {
      await rust.controllerRuleProviderUpdate(target: target, name: p.key);
      await _refresh(force: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} 更新失败:${_formatError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(p.key));
    }
  }

  Future<void> _updateAll(List<_RuleProvider> items) async {
    final target = _targetFor(widget.store);
    final providers = items.where((p) => p.updatable).toList(growable: false);
    if (target == null || providers.isEmpty) return;
    final failures = <String>[];
    setState(() => _updatingAll = true);
    try {
      for (final provider in providers) {
        try {
          await rust.controllerRuleProviderUpdate(
            target: target,
            name: provider.key,
          );
        } catch (error) {
          failures.add('${provider.name}: ${_formatError(error)}');
        }
      }
      if (mounted) await _refresh(force: true);
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
    if (mounted && failures.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('有 ${failures.length} 项更新失败：${failures.first}')),
      );
    }
  }

  String _formatError(Object error) =>
      formatError(error, backendName: widget.store.active?.name);

  @override
  Widget build(BuildContext context) {
    if (!_isSurgeController) {
      return _buildSection(
        title: '规则集',
        icon: Icons.rule,
        emptyText: '暂无规则集',
        items: _items,
      );
    }
    final rules = _items
        .where((item) => const {'ruleset', 'domainset'}.contains(item.kind))
        .toList(growable: false);
    final scripts = _items
        .where((item) => item.kind == 'script')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSection(
          title: '规则',
          icon: Icons.rule,
          emptyText: '暂无规则资源',
          items: rules,
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: '脚本',
          icon: Icons.code_rounded,
          emptyText: '暂无脚本资源',
          items: scripts,
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required String emptyText,
    required List<_RuleProvider> items,
  }) {
    return SectionPanel(
      title: title,
      icon: icon,
      trailing: _ProviderActions(
        hasUpdates: items.any((provider) => provider.updatable),
        busy: _busy.isNotEmpty,
        loading: _loading,
        updatingAll: _updatingAll,
        onUpdateAll: () => _updateAll(items),
      ),
      child: _ProviderBody(
        loading: _loading && _items.isEmpty,
        error: _error,
        empty: items.isEmpty,
        emptyText: emptyText,
        children: [
          for (final provider in items)
            _RuleProviderTile(
              provider: provider,
              busy: _busy.contains(provider.key),
              enabled: !_updatingAll,
              onUpdate: () => _update(provider),
            ),
        ],
      ),
    );
  }
}

class _ProviderActions extends StatelessWidget {
  const _ProviderActions({
    required this.hasUpdates,
    required this.busy,
    required this.loading,
    required this.updatingAll,
    required this.onUpdateAll,
  });

  final bool hasUpdates;
  final bool busy;
  final bool loading;
  final bool updatingAll;
  final VoidCallback onUpdateAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasUpdates)
          IconButton(
            tooltip: '更新全部',
            onPressed: updatingAll || busy || loading ? null : onUpdateAll,
            icon: updatingAll
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined, size: 20),
          ),
      ],
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
          borderRadius: BorderRadius.circular(12),
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
          child: Text(
            emptyText,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
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
  if (diff.isNegative || diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final months = (diff.inDays / 30).round();
  if (months < 12) return '$months 个月前';
  return '${(diff.inDays / 365).round()} 年前';
}

class _ProxyProviderList extends StatelessWidget {
  const _ProxyProviderList({
    required this.providers,
    required this.busy,
    required this.updatesEnabled,
    required this.liquid,
    required this.onUpdate,
    required this.onView,
  });

  final List<_ProxyProvider> providers;
  final Set<String> busy;
  final bool updatesEnabled;
  final bool liquid;
  final ValueChanged<_ProxyProvider> onUpdate;
  final ValueChanged<_ProxyProvider> onView;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < providers.length; i++) ...[
          if (i > 0)
            liquid ? const SizedBox(height: 8) : const Divider(height: 18),
          if (liquid)
            _LiquidProxyProviderTile(
              provider: providers[i],
              busy: busy.contains(providers[i].key),
              enabled: updatesEnabled,
              onUpdate: () => onUpdate(providers[i]),
              onView: () => onView(providers[i]),
            )
          else
            _PlainProxyProviderTile(
              provider: providers[i],
              busy: busy.contains(providers[i].key),
              enabled: updatesEnabled,
              onUpdate: () => onUpdate(providers[i]),
              onView: () => onView(providers[i]),
            ),
        ],
      ],
    );
  }
}

class _LiquidProxyProviderTile extends StatelessWidget {
  const _LiquidProxyProviderTile({
    required this.provider,
    required this.busy,
    required this.enabled,
    required this.onUpdate,
    required this.onView,
  });

  final _ProxyProvider provider;
  final bool busy;
  final bool enabled;
  final VoidCallback onUpdate;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subscription = provider.subscription;
    final progress = subscription == null
        ? null
        : _subscriptionRemainingProgress(subscription);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    const radius = BorderRadius.all(Radius.circular(12));

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        child: Stack(
          children: [
            if (progress != null)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          colors: [
                            scheme.primary.withValues(alpha: 0.2),
                            scheme.primary.withValues(alpha: 0.09),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProxyProviderHeader(
                    provider: provider,
                    busy: busy,
                    enabled: enabled,
                    compact: true,
                    onUpdate: onUpdate,
                    onView: onView,
                  ),
                  if (subscription != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _subscriptionRemaining(subscription),
                            style: secondaryStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _subscriptionExpiry(subscription.expire),
                          style: secondaryStyle,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlainProxyProviderTile extends StatelessWidget {
  const _PlainProxyProviderTile({
    required this.provider,
    required this.busy,
    required this.enabled,
    required this.onUpdate,
    required this.onView,
  });

  final _ProxyProvider provider;
  final bool busy;
  final bool enabled;
  final VoidCallback onUpdate;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final subscription = provider.subscription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyProviderHeader(
          provider: provider,
          busy: busy,
          enabled: enabled,
          onUpdate: onUpdate,
          onView: onView,
        ),
        if (subscription != null) ...[
          const SizedBox(height: 8),
          _SubscriptionUsage(info: subscription),
        ],
      ],
    );
  }
}

class _ProxyProviderHeader extends StatelessWidget {
  const _ProxyProviderHeader({
    required this.provider,
    required this.busy,
    required this.enabled,
    this.compact = false,
    required this.onUpdate,
    required this.onView,
  });

  final _ProxyProvider provider;
  final bool busy;
  final bool enabled;
  final bool compact;
  final VoidCallback onUpdate;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final updated = provider.updatedAt == null ? '' : _ago(provider.updatedAt!);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  _resourceTypeLabel(provider.vehicleType),
                  if (provider.nodesAvailable) '${provider.proxies} 个节点',
                  if (updated.isNotEmpty) updated,
                ].join('  ·  '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '查看节点',
          onPressed: provider.nodesAvailable ? onView : null,
          padding: compact ? EdgeInsets.zero : null,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 36, height: 36)
              : null,
          visualDensity: compact ? VisualDensity.compact : null,
          icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
        ),
        if (provider.updatable)
          IconButton(
            tooltip: '更新',
            onPressed: busy || !enabled ? null : onUpdate,
            padding: compact ? EdgeInsets.zero : null,
            constraints: compact
                ? const BoxConstraints.tightFor(width: 36, height: 36)
                : null,
            visualDensity: compact ? VisualDensity.compact : null,
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

class _SubscriptionUsage extends StatelessWidget {
  const _SubscriptionUsage({required this.info});

  final _SubscriptionInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _subscriptionUsedProgress(info);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _subscriptionUsage(info),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(_subscriptionExpiry(info.expire), style: style),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
            color: scheme.primary.withValues(alpha: 0.72),
            backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
          ),
        ],
      ],
    );
  }
}

String _subscriptionUsage(_SubscriptionInfo info) => info.total > BigInt.zero
    ? '${_formatSubscriptionUsage(info.used)} / ${formatBytes(info.total)}'
    : '已用 ${_formatSubscriptionUsage(info.used)}';

String _subscriptionRemaining(_SubscriptionInfo info) {
  if (info.total <= BigInt.zero) {
    return '已用 ${_formatSubscriptionUsage(info.used)}';
  }
  final remaining = info.total > info.used
      ? info.total - info.used
      : BigInt.zero;
  return '剩余 ${_formatSubscriptionUsage(remaining)} / ${formatBytes(info.total)}';
}

double? _subscriptionUsedProgress(_SubscriptionInfo info) {
  if (info.total <= BigInt.zero) return null;
  return (info.used.toDouble() / info.total.toDouble()).clamp(0.0, 1.0);
}

double? _subscriptionRemainingProgress(_SubscriptionInfo info) {
  if (info.total <= BigInt.zero) return null;
  final used = (info.used.toDouble() / info.total.toDouble()).clamp(0.0, 1.0);
  return 1 - used;
}

String _formatSubscriptionUsage(BigInt bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  if (unit < 3) return formatBytes(bytes);
  return '${size.toStringAsFixed(1)} ${units[unit]}';
}

String _subscriptionExpiry(BigInt seconds) {
  if (seconds <= BigInt.zero) return '长期有效';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (seconds * BigInt.from(1000)).toInt(),
    isUtc: true,
  ).toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

class _RuleProviderTile extends StatelessWidget {
  const _RuleProviderTile({
    required this.provider,
    required this.busy,
    required this.enabled,
    required this.onUpdate,
  });
  final _RuleProvider provider;
  final bool busy;
  final bool enabled;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final updatable = provider.updatable;
    final updated = provider.updatedAt == null ? '' : _ago(provider.updatedAt!);
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
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  _resourceTypeLabel(provider.vehicleType),
                  if (provider.behavior.isNotEmpty &&
                      provider.behavior.toLowerCase() != provider.kind)
                    provider.behavior,
                  if (provider.format.isNotEmpty) provider.format,
                  if (provider.ruleCount > 0) '${provider.ruleCount} 条',
                  if (updated.isNotEmpty) updated,
                ].join('  ·  '),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (updatable)
          IconButton(
            tooltip: '更新',
            onPressed: busy || !enabled ? null : onUpdate,
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

String _resourceTypeLabel(String value) {
  return switch (value.toLowerCase()) {
    'policy-group' => '策略组',
    'ruleset' => '规则集',
    'domainset' => '域名集',
    'script' => '脚本',
    _ => value,
  };
}
