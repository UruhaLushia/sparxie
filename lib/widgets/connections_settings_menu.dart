import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../platform_capabilities.dart';
import 'compact_controls.dart';
import 'settings_drawer.dart';

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
    showSettingsDrawer<void>(
      context: context,
      barrierLabel: '连接设置',
      builder: (_) => _ConnectionsSettingsSheet(prefs: prefs),
    );
  }
}

class _ConnectionsSettingsSheet extends StatelessWidget {
  const _ConnectionsSettingsSheet({required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SettingsDrawerSheet(
      title: '连接设置',
      listenable: prefs,
      childrenBuilder: (context) {
        final canResolveProcess = supportsProcessIdentity;
        return [
          SettingsDrawerSection(
            label: '连接列表刷新间隔',
            hint: '当前:${_formatMs(prefs.connectionsRefreshMs)}。设置过低会增加后端与设备负载。',
            child: _RefreshChips(prefs: prefs),
          ),
          SettingsDrawerSection(
            label: '已关闭连接缓存',
            hint: '当前:${prefs.closedConnectionsCapacity} 条。仅限制历史连接，不影响活动连接。',
            child: _ClosedCapacityChips(prefs: prefs),
          ),
          CompactSwitch.tile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('显示进程图标'),
            subtitle: const Text('仅本机内核;按连接所属应用显示图标'),
            value: prefs.connectionsShowProcessIcon,
            onChanged: canResolveProcess
                ? prefs.setConnectionsShowProcessIcon
                : null,
          ),
          CompactSwitch.tile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('显示应用名称'),
            subtitle: const Text('用解析到的应用名替代原始进程名'),
            value: prefs.connectionsShowAppName,
            onChanged: canResolveProcess
                ? prefs.setConnectionsShowAppName
                : null,
          ),
          CompactSwitch.tile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('来源归类'),
            subtitle: const Text('活动连接按来源分组'),
            value: prefs.connectionsGroupByProcess,
            onChanged: prefs.setConnectionsGroupByProcess,
          ),
          if (prefs.connectionsGroupByProcess) _GroupSortRow(prefs: prefs),
        ];
      },
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: CompactSegmentedButton<int>(
        segments: [
          for (final ms in _options)
            ButtonSegment(value: ms, label: Text(_formatMs(ms))),
        ],
        selected: {current},
        onSelectionChanged: (selection) =>
            prefs.setConnectionsRefreshMs(selection.first),
      ),
    );
  }
}

class _ClosedCapacityChips extends StatelessWidget {
  const _ClosedCapacityChips({required this.prefs});

  final AppPrefs prefs;

  static const _options = <int>[100, 250, 500, 1000, 2000, 5000];

  @override
  Widget build(BuildContext context) {
    final values = <int>{..._options, prefs.closedConnectionsCapacity}.toList()
      ..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: CompactSegmentedButton<int>(
        segments: [
          for (final value in values)
            ButtonSegment(value: value, label: Text('$value')),
        ],
        selected: {prefs.closedConnectionsCapacity},
        onSelectionChanged: (selection) =>
            prefs.setClosedConnectionsCapacity(selection.first),
      ),
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
          CompactMenuButton<GroupSort>(
            value: prefs.connectionsGroupSort,
            label: _labels[prefs.connectionsGroupSort]!,
            semanticLabel: '归类排序',
            itemBuilder: (_) => [
              for (final entry in _labels.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onSelected: prefs.setConnectionsGroupSort,
          ),
          const SizedBox(width: 4),
          CompactIconButton(
            semanticLabel: asc ? '升序' : '降序',
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
