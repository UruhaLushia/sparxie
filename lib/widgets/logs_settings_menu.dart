import 'package:flutter/material.dart';

import '../app_prefs.dart';
import 'compact_controls.dart';
import 'settings_drawer.dart';

/// AppBar tune button for the logs page. Opens a right-anchored settings
/// sheet exposing log-buffer preferences.
class LogsSettingsMenu extends StatelessWidget {
  const LogsSettingsMenu({super.key, required this.prefs});

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
      barrierLabel: '日志设置',
      builder: (_) => _LogsSettingsSheet(prefs: prefs),
    );
  }
}

class _LogsSettingsSheet extends StatelessWidget {
  const _LogsSettingsSheet({required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SettingsDrawerSheet(
      title: '日志设置',
      listenable: prefs,
      childrenBuilder: (_) => [
        SettingsDrawerSection(
          label: '日志缓存',
          hint:
              '当前:总计最多 ${prefs.logInfoCapacity * 2} 条，其中 Info 及以上最多 ${prefs.logInfoCapacity} 条。',
          child: _CapacityChips(prefs: prefs),
        ),
      ],
    );
  }
}

class _CapacityChips extends StatelessWidget {
  const _CapacityChips({required this.prefs});

  static const _options = <int>[100, 250, 500, 1000, 2000, 5000];

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final values = <int>{..._options, prefs.logInfoCapacity}.toList()..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: CompactSegmentedButton<int>(
        segments: [
          for (final value in values)
            ButtonSegment(value: value, label: Text('$value')),
        ],
        selected: {prefs.logInfoCapacity},
        onSelectionChanged: (selection) =>
            prefs.setLogInfoCapacity(selection.first),
      ),
    );
  }
}
