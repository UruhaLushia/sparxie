import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../utils.dart';
import '../widgets/section_panel.dart';

class TailscaleScreen extends StatefulWidget {
  const TailscaleScreen({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<TailscaleScreen> createState() => _TailscaleScreenState();
}

class _TailscaleScreenState extends State<TailscaleScreen> {
  StreamSubscription<rust.TailscaleStatus>? _sub;
  rust.TailscaleStatus? _status;
  String? _error;
  bool _loading = false;
  String? _targetKey;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_restart);
    _restart(force: true);
  }

  @override
  void didUpdateWidget(covariant TailscaleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store.removeListener(_restart);
    widget.store.addListener(_restart);
    _restart(force: true);
  }

  @override
  void dispose() {
    widget.store.removeListener(_restart);
    _sub?.cancel();
    super.dispose();
  }

  void _restart({bool force = false}) {
    final controller = widget.store.active;
    final key = controller == null ? null : _controllerKey(controller);
    if (!force && key == _targetKey) return;
    _targetKey = key;
    _sub?.cancel();
    _sub = null;
    _busy.clear();

    if (controller == null) {
      setState(() {
        _loading = false;
        _status = null;
        _error = '请先在“后端”中添加一个后端';
      });
      return;
    }
    if (controller.type != ctl.BackendType.singBox) {
      setState(() {
        _loading = false;
        _status = null;
        _error = '当前后端不支持 Tailscale';
      });
      return;
    }

    final target = rust.backendTargetForController(controller);
    setState(() {
      _loading = true;
      _status = null;
      _error = null;
    });
    _sub = rust
        .tailscaleStatusStream(target: target)
        .listen(
          (status) {
            if (!mounted || _targetKey != key) return;
            setState(() {
              _loading = false;
              _status = status;
              _error = null;
            });
          },
          onError: (Object e) {
            if (!mounted || _targetKey != key) return;
            setState(() {
              _loading = false;
              _error = formatError(e, backendName: controller.name);
            });
          },
          onDone: () {
            if (!mounted || _targetKey != key) return;
            if (_loading) setState(() => _loading = false);
          },
        );
  }

  rust.BackendTarget? _target() {
    final controller = widget.store.active;
    if (controller == null || controller.type != ctl.BackendType.singBox) {
      return null;
    }
    return rust.backendTargetForController(controller);
  }

  Future<void> _runAction({
    required String endpointTag,
    required String action,
    required Future<void> Function(rust.BackendTarget target) call,
  }) async {
    final target = _target();
    if (target == null) return;
    final key = _actionKey(endpointTag, action);
    setState(() => _busy.add(key));
    try {
      await call(target);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(formatError(e))));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _openAuth(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      await _copyAuth(url);
      return;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await _copyAuth(url);
  }

  Future<void> _copyAuth(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('认证链接已复制')));
  }

  Future<void> _logout(String endpointTag) {
    return _runAction(
      endpointTag: endpointTag,
      action: 'logout',
      call: (target) =>
          rust.tailscaleLogout(target: target, endpointTag: endpointTag),
    );
  }

  Future<void> _setExitNode(String endpointTag, String stableId) {
    return _runAction(
      endpointTag: endpointTag,
      action: 'exit:$stableId',
      call: (target) => rust.tailscaleSetExitNode(
        target: target,
        endpointTag: endpointTag,
        stableId: stableId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Tailscale')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _Body(
                loading: _loading,
                error: _error,
                status: status,
                busy: _busy,
                onOpenAuth: _openAuth,
                onCopyAuth: _copyAuth,
                onLogout: _logout,
                onSetExitNode: _setExitNode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.loading,
    required this.error,
    required this.status,
    required this.busy,
    required this.onOpenAuth,
    required this.onCopyAuth,
    required this.onLogout,
    required this.onSetExitNode,
  });

  final bool loading;
  final String? error;
  final rust.TailscaleStatus? status;
  final Set<String> busy;
  final ValueChanged<String> onOpenAuth;
  final ValueChanged<String> onCopyAuth;
  final ValueChanged<String> onLogout;
  final void Function(String endpointTag, String stableId) onSetExitNode;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return SectionPanel(
        title: '状态',
        icon: Icons.vpn_lock_outlined,
        child: _MessageBox(error!, error: true),
      );
    }
    if (loading && status == null) {
      return const SectionPanel(
        title: '状态',
        icon: Icons.vpn_lock_outlined,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final endpoints =
        status?.endpoints ?? const <rust.TailscaleEndpointStatus>[];
    if (endpoints.isEmpty) {
      return const SectionPanel(
        title: '状态',
        icon: Icons.vpn_lock_outlined,
        child: _MessageBox('暂无 Tailscale 端点'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < endpoints.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _EndpointPanel(
            endpoint: endpoints[i],
            busy: busy,
            onOpenAuth: onOpenAuth,
            onCopyAuth: onCopyAuth,
            onLogout: onLogout,
            onSetExitNode: onSetExitNode,
          ),
        ],
      ],
    );
  }
}

class _EndpointPanel extends StatelessWidget {
  const _EndpointPanel({
    required this.endpoint,
    required this.busy,
    required this.onOpenAuth,
    required this.onCopyAuth,
    required this.onLogout,
    required this.onSetExitNode,
  });

  final rust.TailscaleEndpointStatus endpoint;
  final Set<String> busy;
  final ValueChanged<String> onOpenAuth;
  final ValueChanged<String> onCopyAuth;
  final ValueChanged<String> onLogout;
  final void Function(String endpointTag, String stableId) onSetExitNode;

  @override
  Widget build(BuildContext context) {
    final endpointTag = endpoint.endpointTag;
    final authUrl = endpoint.authUrl.trim();
    final self = endpoint.selfPeer;
    final exitNode = endpoint.exitNode;
    final authState = authUrl.isNotEmpty
        ? '等待认证'
        : endpoint.keyAuth
        ? '密钥认证'
        : self == null
        ? '未认证'
        : '已认证';
    final title = _firstNonEmpty([
      endpoint.networkName,
      endpoint.endpointTag,
      'Tailscale',
    ]);
    final rows = [
      ('状态', endpoint.backendState),
      ('网络', endpoint.networkName),
      ('MagicDNS', endpoint.magicDnsSuffix),
      ('认证', authState),
      if (self != null) ('当前设备', _peerTitle(self)),
      if (exitNode != null) ('出口节点', _peerTitle(exitNode)),
    ].where((row) => row.$2.trim().isNotEmpty).toList(growable: false);

    return SectionPanel(
      title: title,
      icon: Icons.vpn_lock_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRows(rows: rows),
          if (authUrl.isNotEmpty || self != null || exitNode != null) ...[
            const SizedBox(height: 14),
            _ActionWrap(
              endpoint: endpoint,
              busy: busy,
              onOpenAuth: onOpenAuth,
              onCopyAuth: onCopyAuth,
              onLogout: onLogout,
              onSetExitNode: onSetExitNode,
            ),
          ],
          if (endpoint.userGroups.isNotEmpty) ...[
            const Divider(height: 28),
            for (var i = 0; i < endpoint.userGroups.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              _UserGroupBlock(
                group: endpoint.userGroups[i],
                endpointTag: endpointTag,
                exitNode: exitNode,
                busy: busy,
                onSetExitNode: onSetExitNode,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ActionWrap extends StatelessWidget {
  const _ActionWrap({
    required this.endpoint,
    required this.busy,
    required this.onOpenAuth,
    required this.onCopyAuth,
    required this.onLogout,
    required this.onSetExitNode,
  });

  final rust.TailscaleEndpointStatus endpoint;
  final Set<String> busy;
  final ValueChanged<String> onOpenAuth;
  final ValueChanged<String> onCopyAuth;
  final ValueChanged<String> onLogout;
  final void Function(String endpointTag, String stableId) onSetExitNode;

  @override
  Widget build(BuildContext context) {
    final endpointTag = endpoint.endpointTag;
    final authUrl = endpoint.authUrl.trim();
    final logoutBusy = busy.contains(_actionKey(endpointTag, 'logout'));
    final clearExitBusy = busy.contains(_actionKey(endpointTag, 'exit:'));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (authUrl.isNotEmpty) ...[
          FilledButton.icon(
            onPressed: () => _showAuthQrSheet(context, authUrl),
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: const Text('扫码认证'),
          ),
          OutlinedButton.icon(
            onPressed: () => onOpenAuth(authUrl),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('打开认证'),
          ),
          OutlinedButton.icon(
            onPressed: () => onCopyAuth(authUrl),
            icon: const Icon(Icons.content_copy, size: 18),
            label: const Text('复制链接'),
          ),
        ],
        if (endpoint.exitNode != null)
          OutlinedButton.icon(
            onPressed: clearExitBusy
                ? null
                : () => onSetExitNode(endpointTag, ''),
            icon: clearExitBusy
                ? const _ButtonSpinner()
                : const Icon(Icons.block, size: 18),
            label: const Text('关闭出口节点'),
          ),
        if (endpoint.selfPeer != null)
          OutlinedButton.icon(
            onPressed: logoutBusy ? null : () => onLogout(endpointTag),
            icon: logoutBusy
                ? const _ButtonSpinner()
                : const Icon(Icons.logout, size: 18),
            label: const Text('退出登录'),
          ),
      ],
    );
  }
}

void _showAuthQrSheet(BuildContext context, String authUrl) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 360),
    builder: (_) => _AuthQrSheet(authUrl: authUrl),
  );
}

class _AuthQrSheet extends StatelessWidget {
  const _AuthQrSheet({required this.authUrl});

  final String authUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '扫码认证',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: authUrl,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              authUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserGroupBlock extends StatelessWidget {
  const _UserGroupBlock({
    required this.group,
    required this.endpointTag,
    required this.exitNode,
    required this.busy,
    required this.onSetExitNode,
  });

  final rust.TailscaleUserGroup group;
  final String endpointTag;
  final rust.TailscalePeer? exitNode;
  final Set<String> busy;
  final void Function(String endpointTag, String stableId) onSetExitNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _firstNonEmpty([
      group.displayName,
      group.loginName,
      group.userId.toString(),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (group.loginName.isNotEmpty && group.loginName != title) ...[
          const SizedBox(height: 2),
          Text(
            group.loginName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < group.peers.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _PeerRow(
            peer: group.peers[i],
            endpointTag: endpointTag,
            selectedExit: exitNode?.stableId == group.peers[i].stableId,
            busy: busy.contains(
              _actionKey(endpointTag, 'exit:${group.peers[i].stableId}'),
            ),
            onSetExitNode: onSetExitNode,
          ),
        ],
      ],
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.peer,
    required this.endpointTag,
    required this.selectedExit,
    required this.busy,
    required this.onSetExitNode,
  });

  final rust.TailscalePeer peer;
  final String endpointTag;
  final bool selectedExit;
  final bool busy;
  final void Function(String endpointTag, String stableId) onSetExitNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = _peerMeta(peer);
    final traffic = _peerTraffic(peer);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StatusDot(online: peer.online, expired: peer.expired),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _peerTitle(peer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (traffic.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    traffic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (peer.exitNodeOption) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: selectedExit ? '当前出口节点' : '设为出口节点',
              onPressed: selectedExit || busy
                  ? null
                  : () => onSetExitNode(endpointTag, peer.stableId),
              icon: busy
                  ? const _ButtonSpinner()
                  : Icon(
                      selectedExit ? Icons.check_circle : Icons.output_outlined,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRows extends StatelessWidget {
  const _InfoRows({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _InfoRow(label: rows[i].$1, value: rows[i].$2),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online, required this.expired});

  final bool online;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = expired
        ? scheme.error
        : online
        ? scheme.primary
        : scheme.outline;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = error ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final fg = error ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: fg)),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

String _controllerKey(ctl.Controller c) =>
    '${c.id}\u{1f}${c.type.name}\u{1f}${c.baseUrl}\u{1f}${c.secret}\u{1f}${c.allowInsecure}';

String _actionKey(String endpointTag, String action) =>
    '$endpointTag\u{1f}$action';

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _peerTitle(rust.TailscalePeer peer) => _firstNonEmpty([
  peer.hostName,
  peer.dnsName,
  if (peer.tailscaleIps.isNotEmpty) peer.tailscaleIps.first,
  peer.stableId,
  '未知设备',
]);

String _peerMeta(rust.TailscalePeer peer) {
  final lastSeen = _timeLabel(peer.lastSeen);
  final items = <String>[
    peer.online ? '在线' : '离线',
    if (peer.os.isNotEmpty) peer.os,
    if (peer.dnsName.isNotEmpty && peer.dnsName != peer.hostName) peer.dnsName,
    if (peer.tailscaleIps.isNotEmpty) peer.tailscaleIps.join(' / '),
    if (peer.exitNode) '出口节点',
    if (peer.shareeNode) '共享设备',
    if (peer.expired) '密钥过期',
    if (lastSeen.isNotEmpty) '最后在线 $lastSeen',
  ];
  return items.join('  ·  ');
}

String _peerTraffic(rust.TailscalePeer peer) {
  final rx = asBigInt(peer.rxBytes);
  final tx = asBigInt(peer.txBytes);
  if (rx == BigInt.zero && tx == BigInt.zero) return '';
  return '↓ ${formatBytes(rx)}  ↑ ${formatBytes(tx)}';
}

String _timeLabel(Object value) {
  final seconds = asBigInt(value);
  if (seconds <= BigInt.zero) return '';
  final local = DateTime.fromMillisecondsSinceEpoch(
    seconds.toInt() * 1000,
    isUtc: true,
  ).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
