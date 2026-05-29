import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../error_format.dart';
import '../rust_api.dart' as rust;

/// Launcher card with three pill segments (规则/全局/直连). Tapping a
/// segment immediately PATCHes mihomo's `mode`; no popup, no navigation.
class OutboundModeCard extends StatefulWidget {
  const OutboundModeCard({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  State<OutboundModeCard> createState() => _OutboundModeCardState();
}

class _OutboundModeCardState extends State<OutboundModeCard> {
  ctl.Controller? _activeKey;
  String? _mode;
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

  rust.MihomoTarget? _target() {
    final c = widget.store.active;
    if (c == null) return null;
    return rust.MihomoTarget(
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
      allowInsecure: c.allowInsecure,
    );
  }

  void _bind() {
    _activeKey = widget.store.active;
    _mode = null;
    if (_activeKey == null) return;
    _refresh();
  }

  Future<void> _refresh() async {
    final target = _target();
    if (target == null) return;
    try {
      final raw = await rust.configs(target: target);
      if (!mounted || !identical(widget.store.active, _activeKey)) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final m = (json['mode'] ?? 'rule').toString().toLowerCase();
      setState(() => _mode = m);
    } catch (_) {
      // Silent; the basic-config screen surfaces detailed errors.
    }
  }

  Future<void> _setMode(String mode) async {
    if (_saving || mode == _mode) return;
    final target = _target();
    if (target == null) return;
    final previous = _mode;
    setState(() {
      _mode = mode;
      _saving = true;
    });
    try {
      await rust.patchConfigs(
        target: target,
        bodyJson: jsonEncode({'mode': mode}),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _mode = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换出站模式失败:${formatError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _options = <(String, String)>[
    ('rule', '规则'),
    ('global', '全局'),
    ('direct', '直连'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mode = _mode;
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
          child: Row(
            children: [
              for (final (key, label) in _options)
                Expanded(
                  child: _Segment(
                    label: label,
                    selected: mode == key,
                    busy: _saving && mode == key,
                    // Disable all segments while a switch is in flight to
                    // prevent the user from racing two patches against each
                    // other (and getting an out-of-order final state).
                    onTap: mode == null || _saving
                        ? null
                        : () => _setMode(key),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurface,
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
