import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../session.dart';
import '../widgets/section_panel.dart';

/// Standalone page for one-shot mihomo core actions: reload / restart /
/// upgrade / geo update and DNS / FakeIP cache flushes. Each runs against the
/// active backend with per-row busy state and a SnackBar result.
///
/// CMFA builds bake the config into the app and disable mihomo's `/configs`
/// reload/restart/upgrade endpoints, so those rows are disabled there.
class CoreActionsScreen extends StatefulWidget {
  const CoreActionsScreen({
    super.key,
    required this.store,
    required this.session,
  });

  final ctl.ControllerStore store;
  final MihomoSession session;

  @override
  State<CoreActionsScreen> createState() => _CoreActionsScreenState();
}

class _CoreActionsScreenState extends State<CoreActionsScreen> {
  String? _running;

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
      allowInsecure: c.allowInsecure,
    );
  }

  Future<void> _run(
    String id,
    String successMsg,
    Future<void> Function(rust.MihomoTarget target) action, {
    String? confirm,
  }) async {
    final target = _target();
    if (target == null) {
      _snack('请先在“后端”中添加一个 mihomo 实例');
      return;
    }
    if (confirm != null && !await _confirm(id, confirm)) return;
    setState(() => _running = id);
    String? failure;
    try {
      await action(target);
    } catch (e) {
      failure = formatError(e);
    } finally {
      if (mounted) setState(() => _running = null);
    }
    _snack(failure == null ? successMsg : '失败:$failure');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('核心操作')),
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.session.isCmfa,
          builder: (context, isCmfa, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionPanel(
                      title: '配置与核心',
                      icon: Icons.build_outlined,
                      child: Column(
                        children: [
                          _action(
                            icon: Icons.refresh,
                            title: '重载配置',
                            subtitle: '重新加载当前配置文件',
                            id: 'reload',
                            success: '已重载配置',
                            run: (t) =>
                                rust.reloadConfigs(target: t, force: false),
                            disabled: isCmfa,
                          ),
                          _action(
                            icon: Icons.travel_explore,
                            title: '更新 GeoData',
                            subtitle: '刷新 GeoIP / GeoSite 数据库',
                            id: 'geo',
                            success: 'GeoData 已更新',
                            run: (t) => rust.updateGeo(target: t),
                          ),
                          _action(
                            icon: Icons.restart_alt,
                            title: '重启核心',
                            subtitle: '重新启动 mihomo 核心',
                            id: 'restart',
                            success: '核心已重启',
                            run: (t) => rust.restartCore(target: t),
                            confirm: '确定重启核心？',
                            disabled: isCmfa,
                          ),
                          _action(
                            icon: Icons.upgrade,
                            title: '升级核心',
                            subtitle: '下载并替换核心二进制',
                            id: 'upgrade',
                            success: '核心升级已触发',
                            run: (t) =>
                                rust.upgradeCore(target: t, force: false),
                            confirm: '确定升级核心？这会下载并替换核心二进制。',
                            disabled: isCmfa,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionPanel(
                      title: '缓存',
                      icon: Icons.cached,
                      child: Column(
                        children: [
                          _action(
                            icon: Icons.dns_outlined,
                            title: '清空 DNS 缓存',
                            subtitle: '清除核心的 DNS 解析缓存',
                            id: 'dns',
                            success: '已清空 DNS 缓存',
                            run: (t) => rust.flushDns(target: t),
                          ),
                          _action(
                            icon: Icons.layers_clear_outlined,
                            title: '清空 FakeIP',
                            subtitle: '清除 FakeIP 映射池',
                            id: 'fakeip',
                            success: '已清空 FakeIP',
                            run: (t) => rust.flushFakeip(target: t),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String title,
    required String subtitle,
    required String id,
    required String success,
    required Future<void> Function(rust.MihomoTarget target) run,
    String? confirm,
    bool disabled = false,
  }) {
    final busy = _running == id;
    // Lock all rows while any action runs so two can't overlap; `disabled`
    // additionally greys out actions the backend doesn't support (CMFA).
    final enabled = !disabled && _running == null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(disabled ? 'CMFA 不支持此操作' : subtitle),
      trailing: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: enabled ? () => _run(id, success, run, confirm: confirm) : null,
    );
  }
}
