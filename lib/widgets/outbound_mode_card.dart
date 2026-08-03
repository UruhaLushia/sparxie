import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;
import 'active_listenable_builder.dart';
import 'compact_controls.dart';
import 'section_panel.dart';

/// Launcher card for the backend's outbound modes. Tapping a segment
/// immediately switches the active backend mode; no popup, no navigation.
class OutboundModeCard extends StatelessWidget {
  const OutboundModeCard({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  Widget build(BuildContext context) {
    return ActiveListenableSelector<ctl.Controller?>(
      listenable: store,
      selector: () => store.active,
      builder: (_, activeController, _) => _OutboundModeCardBody(
        key: ValueKey((store, activeController)),
        store: store,
      ),
    );
  }
}

class _OutboundModeCardBody extends StatefulWidget {
  const _OutboundModeCardBody({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<_OutboundModeCardBody> createState() => _OutboundModeCardState();
}

class _OutboundModeCardState extends State<_OutboundModeCardBody> {
  ctl.Controller? _activeKey;
  String? _mode;
  List<String> _options = const <String>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  rust.BackendTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.backendTargetForController(c);
  }

  void _bind() {
    _activeKey = widget.store.active;
    _mode = null;
    _options = const <String>[];
    if (_activeKey == null) return;
    _refresh();
  }

  Future<void> _refresh() async {
    final target = _target();
    if (target == null) return;
    try {
      final configs = await rust.configs(target: target);
      if (!mounted || !identical(widget.store.active, _activeKey)) return;
      setState(() {
        _mode = configs.mode;
        _options = _modeChoices(
          configs,
          useDefaultModes: _activeKey?.type != ctl.BackendType.singBox,
        );
      });
    } catch (_) {
      // Silent; the basic-config screen surfaces detailed errors.
      if (!mounted || !identical(widget.store.active, _activeKey)) return;
      setState(() {
        _mode = null;
        _options = const <String>[];
      });
    }
  }

  Future<void> _setMode(String mode) async {
    if (_saving || (_mode != null && _sameMode(mode, _mode!))) return;
    final target = _target();
    if (target == null) return;
    final previous = _mode;
    setState(() {
      _mode = mode;
      _saving = true;
    });
    try {
      await rust.setConfigMode(target: target, mode: mode);
    } catch (e) {
      if (!mounted) return;
      setState(() => _mode = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切换出站模式失败:${_formatError(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatError(Object error) =>
      formatError(error, backendName: _activeKey?.name);

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    final options = _options;
    if (options.isEmpty) return const SizedBox.shrink();
    final expanded = options.length <= 3;
    final selected = mode == null
        ? const <String>{}
        : {
            for (final key in options)
              if (_sameMode(mode, key)) key,
          };
    final controlStyle = CompactControlTheme.segmentedOf(
      context,
    ).copyWith(backgroundColor: Colors.transparent);
    final control = CompactSegmentedButton<String>(
      expanded: expanded,
      style: controlStyle,
      segments: [
        for (final key in options)
          ButtonSegment(
            value: key,
            enabled: !_saving,
            icon: _saving && selected.contains(key)
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            label: Text(_label(key)),
          ),
      ],
      selected: selected,
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) _setMode(selection.first);
      },
    );
    return AppPanelSurface(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: expanded
            ? control
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: control,
              ),
      ),
    );
  }
}

List<String> _modeChoices(
  rust.CoreConfig configs, {
  required bool useDefaultModes,
}) {
  const defaultModes = ['rule', 'global', 'direct'];
  final choices = configs.modeOptions.isEmpty && useDefaultModes
      ? defaultModes
      : configs.modeOptions;
  final out = <String>[];
  for (final value in choices) {
    if (value.isEmpty || out.any((item) => _sameMode(item, value))) continue;
    out.add(value);
  }
  final current = configs.mode;
  if (current != null &&
      current.isNotEmpty &&
      !out.any((item) => _sameMode(item, current))) {
    out.insert(0, current);
  }
  return out;
}

bool _sameMode(String a, String b) => a.toLowerCase() == b.toLowerCase();

String _label(String m) => switch (m.toLowerCase()) {
  'rule' => '规则',
  'global' => '全局',
  'direct' => '直连',
  _ => m,
};
