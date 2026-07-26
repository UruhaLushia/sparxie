import 'package:flutter/material.dart';

import '../app_prefs.dart';

/// App-bar tune button. Opens a right-anchored settings sheet on tap.
class ProxiesSettingsMenu extends StatelessWidget {
  const ProxiesSettingsMenu({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '显示设置',
      icon: const Icon(Icons.tune),
      onPressed: () => _open(context),
    );
  }

  void _open(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '代理组设置',
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
      pageBuilder: (_, _, _) => _ProxiesSettingsSheet(prefs: prefs),
    );
  }
}

class _ProxiesSettingsSheet extends StatelessWidget {
  const _ProxiesSettingsSheet({required this.prefs});

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
                        _SettingsRow(
                          label: '布局样式',
                          trailing: _LayoutSegmented(prefs: prefs),
                        ),
                        if (prefs.proxiesLayout == ProxiesLayout.cards)
                          _SettingsRow(
                            label: '卡片渐变配色',
                            trailing: Switch(
                              value: prefs.proxiesCardColored,
                              onChanged: prefs.setProxiesCardColored,
                            ),
                          ),
                        _SettingsRow(
                          label: '代理节点展示列数',
                          trailing: _ColumnsDropdown(prefs: prefs),
                        ),
                        _SettingsRow(
                          label: '节点排序方式',
                          trailing: _SortSegmented(prefs: prefs),
                        ),
                        _SettingsRow(
                          label: '显示代理组图标',
                          trailing: Switch(
                            value: prefs.proxiesShowGroupIcons,
                            onChanged: prefs.setProxiesShowGroupIcons,
                          ),
                        ),
                        _SettingsRow(
                          label: '显示隐藏代理组',
                          trailing: Switch(
                            value: prefs.proxiesShowHiddenGroups,
                            onChanged: prefs.setProxiesShowHiddenGroups,
                          ),
                        ),
                        _SettingsRow(
                          label: '切换节点时断开连接',
                          trailing: Switch(
                            value: prefs.autoCloseOnSwitch,
                            onChanged: prefs.setAutoCloseOnSwitch,
                          ),
                        ),
                        if (prefs.autoCloseOnSwitch)
                          _SettingsRow(
                            label: '打断模式',
                            trailing: _CloseModeSegmented(prefs: prefs),
                          ),
                        _DelayTestUrlRow(prefs: prefs),
                        _SettingsRow(
                          label: '测试地址来源',
                          trailing: _ScopeSegmented(prefs: prefs),
                        ),
                        _SettingsRow(
                          label: '使用策略组 API 测速',
                          trailing: Switch(
                            value: prefs.delayTestUseGroupApi,
                            onChanged: prefs.setDelayTestUseGroupApi,
                          ),
                        ),
                        if (!prefs.delayTestUseGroupApi)
                          _DelayTestConcurrencyRow(prefs: prefs),
                        _DelayTestTimeoutRow(prefs: prefs),
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
          Text('代理组设置', style: Theme.of(context).textTheme.titleLarge),
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

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _LayoutSegmented extends StatelessWidget {
  const _LayoutSegmented({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ProxiesLayout>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: ProxiesLayout.list, label: Text('列表')),
        ButtonSegment(value: ProxiesLayout.cards, label: Text('卡片')),
      ],
      selected: {prefs.proxiesLayout},
      onSelectionChanged: (s) => prefs.setProxiesLayout(s.first),
    );
  }
}

class _SortSegmented extends StatelessWidget {
  const _SortSegmented({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ProxiesSort>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: ProxiesSort.original, label: Text('默认')),
        ButtonSegment(value: ProxiesSort.delay, label: Text('延迟')),
        ButtonSegment(value: ProxiesSort.name, label: Text('名称')),
      ],
      selected: {prefs.proxiesSort},
      onSelectionChanged: (s) => prefs.setProxiesSort(s.first),
    );
  }
}

class _ColumnsDropdown extends StatelessWidget {
  const _ColumnsDropdown({required this.prefs});
  final AppPrefs prefs;

  static const _options = <int>[0, 1, 2, 3, 4];

  String _label(int v) => v == 0 ? '自适应' : '$v 列';

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: prefs.proxiesColumns,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: [
        for (final v in _options)
          DropdownMenuItem(value: v, child: Text(_label(v))),
      ],
      onChanged: (v) {
        if (v != null) prefs.setProxiesColumns(v);
      },
    );
  }
}

class _CloseModeSegmented extends StatelessWidget {
  const _CloseModeSegmented({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CloseMode>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: CloseMode.all, label: Text('所有')),
        ButtonSegment(value: CloseMode.group, label: Text('当前组')),
      ],
      selected: {prefs.closeMode},
      onSelectionChanged: (s) => prefs.setCloseMode(s.first),
    );
  }
}

class _ScopeSegmented extends StatelessWidget {
  const _ScopeSegmented({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<DelayTestScope>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: DelayTestScope.group, label: Text('组')),
        ButtonSegment(value: DelayTestScope.global, label: Text('全局')),
      ],
      selected: {prefs.delayTestScope},
      onSelectionChanged: (s) => prefs.setDelayTestScope(s.first),
    );
  }
}

class _DelayTestUrlRow extends StatefulWidget {
  const _DelayTestUrlRow({required this.prefs});
  final AppPrefs prefs;

  @override
  State<_DelayTestUrlRow> createState() => _DelayTestUrlRowState();
}

class _DelayTestUrlRowState extends State<_DelayTestUrlRow> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.prefs.delayTestUrl);
  }

  @override
  void didUpdateWidget(covariant _DelayTestUrlRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final v = widget.prefs.delayTestUrl;
    if (v != _ctl.text) _ctl.text = v;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
          Text('延迟测试地址', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _ctl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'https://www.gstatic.com/generate_204',
            ),
            onSubmitted: widget.prefs.setDelayTestUrl,
            onEditingComplete: () => widget.prefs.setDelayTestUrl(_ctl.text),
          ),
        ],
      ),
    );
  }
}

class _DelayTestConcurrencyRow extends StatefulWidget {
  const _DelayTestConcurrencyRow({required this.prefs});
  final AppPrefs prefs;

  @override
  State<_DelayTestConcurrencyRow> createState() =>
      _DelayTestConcurrencyRowState();
}

class _DelayTestConcurrencyRowState extends State<_DelayTestConcurrencyRow> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(
      text: widget.prefs.delayTestConcurrency.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _DelayTestConcurrencyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.prefs.delayTestConcurrency.toString();
    if (value != _ctl.text) _ctl.text = value;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _commit() {
    final value =
        int.tryParse(_ctl.text.trim()) ?? AppPrefs.defaultDelayTestConcurrency;
    widget.prefs.setDelayTestConcurrency(value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '延迟测试并发数量',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _ctl,
              textAlign: TextAlign.end,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: '50',
              ),
              onSubmitted: (_) => _commit(),
              onEditingComplete: _commit,
            ),
          ),
        ],
      ),
    );
  }
}

class _DelayTestTimeoutRow extends StatelessWidget {
  const _DelayTestTimeoutRow({required this.prefs});
  final AppPrefs prefs;

  static const _options = <int>[2000, 3000, 5000, 8000, 10000];

  String _label(int ms) {
    if (ms < 1000) return '${ms}ms';
    final s = ms / 1000;
    return s == s.roundToDouble()
        ? '${s.toInt()}s'
        : '${s.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final current = prefs.delayTestTimeoutMs;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('延迟测试超时时间', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ms in _options)
                ChoiceChip(
                  label: Text(_label(ms)),
                  selected: current == ms,
                  onSelected: current == ms
                      ? null
                      : (_) => prefs.setDelayTestTimeoutMs(ms),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
