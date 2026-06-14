import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../platform_capabilities.dart';

/// AppBar tune button for the connections page. Opens a right-anchored
/// settings sheet exposing connection-list preferences.
class ConnectionsSettingsMenu extends StatelessWidget {
  const ConnectionsSettingsMenu({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '显示设置',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.tune),
      onPressed: () => _open(context),
    );
  }

  void _open(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '连接设置',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, _, child) {
        final offset =
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(position: offset, child: child),
        );
      },
      pageBuilder: (_, _, _) => _ConnectionsSettingsSheet(prefs: prefs),
    );
  }
}

class _ConnectionsSettingsSheet extends StatelessWidget {
  const _ConnectionsSettingsSheet({required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width.clamp(0, 420).toDouble();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 6,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(onClose: () => Navigator.of(context).pop()),
                const Divider(height: 1),
                Expanded(
                  child: ListenableBuilder(
                    listenable: prefs,
                    builder: (context, _) {
                      final canResolveProcess = supportsProcessIdentity;
                      return ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          _SettingsBlock(
                            label: '连接列表刷新间隔',
                            hint:
                                '当前:${_formatMs(prefs.connectionsRefreshMs)}。设置过低会增加后端与设备负载。',
                            child: _RefreshChips(prefs: prefs),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            title: const Text('显示进程图标'),
                            subtitle: const Text('仅本机内核;按连接所属应用显示图标'),
                            value: prefs.connectionsShowProcessIcon,
                            onChanged: canResolveProcess
                                ? prefs.setConnectionsShowProcessIcon
                                : null,
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            title: const Text('显示应用名称'),
                            subtitle: const Text('用解析到的应用名替代原始进程名'),
                            value: prefs.connectionsShowAppName,
                            onChanged: canResolveProcess
                                ? prefs.setConnectionsShowAppName
                                : null,
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            title: const Text('来源归类'),
                            subtitle: const Text('活动连接按来源分组'),
                            value: prefs.connectionsGroupByProcess,
                            onChanged: prefs.setConnectionsGroupByProcess,
                          ),
                          if (prefs.connectionsGroupByProcess)
                            _GroupSortRow(prefs: prefs),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          Text('连接设置', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SettingsBlock extends StatelessWidget {
  const _SettingsBlock({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          child,
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _RefreshChips extends StatelessWidget {
  const _RefreshChips({required this.prefs});

  final AppPrefs prefs;

  static const _options = <int>[500, 1000, 2000, 5000, 10000];

  @override
  Widget build(BuildContext context) {
    final current = prefs.connectionsRefreshMs;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final ms in _options)
          ChoiceChip(
            label: Text(_formatMs(ms)),
            selected: current == ms,
            onSelected: current == ms
                ? null
                : (_) => prefs.setConnectionsRefreshMs(ms),
          ),
      ],
    );
  }
}

String _formatMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  final s = ms / 1000;
  return s == s.roundToDouble() ? '${s.toInt()}s' : '${s.toStringAsFixed(1)}s';
}

class _GroupSortRow extends StatelessWidget {
  const _GroupSortRow({required this.prefs});

  final AppPrefs prefs;

  static const _labels = <GroupSort, String>{
    GroupSort.name: '名称',
    GroupSort.count: '连接数',
    GroupSort.upload: '上传量',
    GroupSort.download: '下载量',
    GroupSort.uploadSpeed: '上传速度',
    GroupSort.downloadSpeed: '下载速度',
  };

  @override
  Widget build(BuildContext context) {
    final asc = prefs.connectionsGroupSortAsc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text('归类排序', style: Theme.of(context).textTheme.bodyLarge),
          ),
          const SizedBox(width: 12),
          DropdownButton<GroupSort>(
            value: prefs.connectionsGroupSort,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(8),
            items: [
              for (final entry in _labels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) {
              if (v != null) prefs.setConnectionsGroupSort(v);
            },
          ),
          IconButton(
            tooltip: asc ? '升序' : '降序',
            visualDensity: VisualDensity.compact,
            onPressed: () => prefs.setConnectionsGroupSortAsc(!asc),
            icon: Icon(
              asc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
