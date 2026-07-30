part of 'theme_settings_screen.dart';

class _ThemeModeSelector extends StatefulWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  State<_ThemeModeSelector> createState() => _ThemeModeSelectorState();
}

class _ThemeModeSelectorState extends State<_ThemeModeSelector> {
  late AppThemeMode _selected;
  var _changeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.value;
  }

  @override
  void didUpdateWidget(_ThemeModeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value || widget.value == _selected) return;
    _changeGeneration++;
    _selected = widget.value;
  }

  void _select(Set<AppThemeMode> selection) {
    final next = selection.first;
    if (next == _selected) return;
    final generation = ++_changeGeneration;
    setState(() => _selected = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _changeGeneration) return;
      widget.onChanged(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompactSegmentedButton<AppThemeMode>(
      expanded: true,
      segments: const [
        ButtonSegment(value: AppThemeMode.system, label: Text('自动')),
        ButtonSegment(value: AppThemeMode.light, label: Text('浅色')),
        ButtonSegment(value: AppThemeMode.dark, label: Text('深色')),
      ],
      selected: {_selected},
      onSelectionChanged: _select,
    );
  }
}

class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 58),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.6),
              thumbColor: scheme.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleSectionHeader extends StatelessWidget {
  const _StyleSectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.primary),
        const SizedBox(width: 7),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.title,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.disabledLabel = '由自动取色控制',
  });

  final String title;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final String disabledLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Opacity(
              opacity: enabled ? 1 : 0.58,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          enabled ? '#${_hex(color)}' : disabledLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: enabled ? color : scheme.primary,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.kind,
    required this.color,
    required this.colorEnabled,
    required this.followsGlobal,
    required this.onTap,
  });

  final CompactControlKind kind;
  final Color color;
  final bool colorEnabled;
  final bool followsGlobal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(kind.icon),
      title: Text(kind.label),
      subtitle: Text(
        !colorEnabled
            ? '自动取色'
            : followsGlobal
            ? '跟随全局'
            : '#${_hex(color)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

extension on CompactControlKind {
  String get label => switch (this) {
    CompactControlKind.button => '按钮',
    CompactControlKind.search => '搜索框',
    CompactControlKind.segmented => '分段选择',
    CompactControlKind.toggle => '开关',
    CompactControlKind.navigationBar => '底栏',
  };

  IconData get icon => switch (this) {
    CompactControlKind.button => Icons.smart_button_outlined,
    CompactControlKind.search => Icons.search,
    CompactControlKind.segmented => Icons.view_week_outlined,
    CompactControlKind.toggle => Icons.toggle_on_outlined,
    CompactControlKind.navigationBar => Icons.space_bar_outlined,
  };
}

String _hex(Color color) =>
    color.toARGB32().toRadixString(16).substring(2).toUpperCase();

String _signedPixels(double value) {
  final rounded = value.round();
  return '${rounded > 0 ? '+' : ''}$rounded px';
}
