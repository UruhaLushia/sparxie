import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;

/// Launcher card for the backend's outbound modes. Tapping a segment
/// immediately switches the active backend mode; no popup, no navigation.
class OutboundModeCard extends StatefulWidget {
  const OutboundModeCard({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<OutboundModeCard> createState() => _OutboundModeCardState();
}

class _OutboundModeCardState extends State<OutboundModeCard> {
  ctl.Controller? _activeKey;
  String? _mode;
  List<String> _options = const <String>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _bind();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!identical(widget.store.active, _activeKey)) _bind();
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
    final scheme = Theme.of(context).colorScheme;
    final mode = _mode;
    final options = _options;
    if (options.isEmpty) return const SizedBox.shrink();
    return Material(
      color: scheme.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(4),
          child: options.length <= 3
              ? Row(
                  children: [
                    for (final key in options)
                      Expanded(
                        child: _Segment(
                          label: _label(key),
                          selected: mode != null && _sameMode(mode, key),
                          busy: _saving && mode != null && _sameMode(mode, key),
                          onTap:
                              _saving || (mode != null && _sameMode(mode, key))
                              ? null
                              : () => _setMode(key),
                        ),
                      ),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final key in options)
                        SizedBox(
                          width: 96,
                          child: _Segment(
                            label: _label(key),
                            selected: mode != null && _sameMode(mode, key),
                            busy:
                                _saving && mode != null && _sameMode(mode, key),
                            onTap:
                                _saving ||
                                    (mode != null && _sameMode(mode, key))
                                ? null
                                : () => _setMode(key),
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

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: busy
                  ? SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: selected
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    )
                  : Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: selected ? scheme.onPrimary : scheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
