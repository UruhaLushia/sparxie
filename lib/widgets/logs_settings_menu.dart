import 'package:flutter/material.dart';

import '../app_prefs.dart';
import 'compact_controls.dart';

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
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '日志设置',
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
      pageBuilder: (_, _, _) => _LogsSettingsSheet(prefs: prefs),
    );
  }
}

class _LogsSettingsSheet extends StatelessWidget {
  const _LogsSettingsSheet({required this.prefs});

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
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        _SettingsBlock(
                          label: '日志缓存',
                          hint:
                              '当前:${prefs.logInfoCapacity} 条。按 Info 筛选条目计数；Debug/Trace 不占额度。',
                          child: _CapacityChips(prefs: prefs),
                        ),
                      ],
                    ),
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
          Text('日志设置', style: Theme.of(context).textTheme.titleLarge),
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
