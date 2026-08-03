import 'package:flutter/material.dart';

import '../app_prefs.dart';
import 'compact_controls.dart';
import 'settings_drawer.dart';

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
    showSettingsDrawer<void>(
      context: context,
      barrierLabel: '代理组设置',
      builder: (_) => _ProxiesSettingsSheet(prefs: prefs),
    );
  }
}

class _ProxiesSettingsSheet extends StatelessWidget {
  const _ProxiesSettingsSheet({required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return SettingsDrawerSheet(
      title: '代理组设置',
      listenable: prefs,
      childrenBuilder: (_) => [
        _SettingsRow(
          label: '布局样式',
          trailing: _LayoutSegmented(prefs: prefs),
        ),
        if (prefs.proxiesLayout == ProxiesLayout.cards)
          _SettingsRow(
            label: '卡片渐变配色',
            trailing: CompactSwitch(
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
          trailing: CompactSwitch(
            value: prefs.proxiesShowGroupIcons,
            onChanged: prefs.setProxiesShowGroupIcons,
          ),
        ),
        _SettingsRow(
          label: '显示隐藏代理组',
          trailing: CompactSwitch(
            value: prefs.proxiesShowHiddenGroups,
            onChanged: prefs.setProxiesShowHiddenGroups,
          ),
        ),
        _SettingsRow(
          label: '切换节点时断开连接',
          trailing: CompactSwitch(
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
          trailing: CompactSwitch(
            value: prefs.delayTestUseGroupApi,
            onChanged: prefs.setDelayTestUseGroupApi,
          ),
        ),
        if (!prefs.delayTestUseGroupApi) _DelayTestConcurrencyRow(prefs: prefs),
        _DelayTestTimeoutRow(prefs: prefs),
      ],
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
    return CompactSegmentedButton<ProxiesLayout>(
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
    return CompactSegmentedButton<ProxiesSort>(
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
    return CompactMenuButton<int>(
      value: prefs.proxiesColumns,
      label: _label(prefs.proxiesColumns),
      semanticLabel: '每行列数',
      itemBuilder: (_) => [
        for (final v in _options)
          PopupMenuItem(value: v, child: Text(_label(v))),
      ],
      onSelected: prefs.setProxiesColumns,
    );
  }
}

class _CloseModeSegmented extends StatelessWidget {
  const _CloseModeSegmented({required this.prefs});
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return CompactSegmentedButton<CloseMode>(
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
    return CompactSegmentedButton<DelayTestScope>(
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CompactSegmentedButton<int>(
              segments: [
                for (final ms in _options)
                  ButtonSegment(value: ms, label: Text(_label(ms))),
              ],
              selected: {current},
              onSelectionChanged: (selection) =>
                  prefs.setDelayTestTimeoutMs(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}
