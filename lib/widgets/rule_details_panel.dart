import 'package:flutter/material.dart';

import '../rust_api.dart' as rust;
import 'app_background.dart';

extension RuleEntryStats on rust.RuleEntry {
  double? get hitRate {
    final total = hitCount + missCount;
    return total > BigInt.zero ? hitCount / total * 100 : null;
  }
}

class RuleDetailsPanel extends StatelessWidget {
  const RuleDetailsPanel({super.key, required this.rule});

  final rust.RuleEntry rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Material(
        color: surfaceTheme.modalSurfaceColor(scheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RuleHeader(rule: rule),
              if (rule.hasExtra) ...[
                const SizedBox(height: 12),
                _RuleExtraSummary(rule: rule),
              ],
              const SizedBox(height: 12),
              _RuleDetailField(
                label: '规则内容',
                value: rule.payload.isEmpty ? 'Match' : rule.payload,
                prominent: true,
              ),
              if (rule.proxy.isNotEmpty) ...[
                const SizedBox(height: 9),
                _RuleDetailField(label: '出站', value: rule.proxy),
              ],
              if (rule.extraParams.isNotEmpty) ...[
                const SizedBox(height: 9),
                _RuleDetailField(
                  label: '附加参数',
                  value: rule.extraParams.join('\n'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleHeader extends StatelessWidget {
  const _RuleHeader({required this.rule});

  final rust.RuleEntry rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.route_rounded, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '规则详情',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '#${rule.index} · ${rule.ruleType.isEmpty ? '未知类型' : rule.ruleType}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (rule.hasExtra) ...[
          const SizedBox(width: 8),
          _RuleStatus(disabled: rule.disabled),
        ],
      ],
    );
  }
}

class _RuleStatus extends StatelessWidget {
  const _RuleStatus({required this.disabled});

  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = disabled ? scheme.error : scheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          disabled ? '已禁用' : '已启用',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RuleExtraSummary extends StatelessWidget {
  const _RuleExtraSummary({required this.rule});

  final rust.RuleEntry rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rate = rule.hitRate;
    final hasTimes = rule.hitAt.isNotEmpty || rule.missAt.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '运行统计',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'extra',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              _RuleMetric(label: '命中', value: rule.hitCount.toString()),
              const _MetricSeparator(),
              _RuleMetric(label: '未命中', value: rule.missCount.toString()),
              const _MetricSeparator(),
              _RuleMetric(
                label: '命中率',
                value: rate == null ? '—' : '${rate.toStringAsFixed(1)}%',
                emphasized: true,
              ),
            ],
          ),
          if (hasTimes) ...[
            const SizedBox(height: 9),
            Container(
              height: 0.5,
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 7),
            _RuleExtraTime(
              label: '最后命中',
              value: rule.hitCount == BigInt.zero
                  ? '—'
                  : _formatRuleTime(rule.hitAt),
            ),
            const SizedBox(height: 3),
            _RuleExtraTime(
              label: '最后未命中',
              value: rule.missCount == BigInt.zero
                  ? '—'
                  : _formatRuleTime(rule.missAt),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuleMetric extends StatelessWidget {
  const _RuleMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = emphasized ? scheme.primary : scheme.onSurface;
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 20,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSeparator extends StatelessWidget {
  const _MetricSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 26,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
  }
}

class _RuleExtraTime extends StatelessWidget {
  const _RuleExtraTime({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

String _formatRuleTime(String raw) {
  final value = DateTime.tryParse(raw)?.toLocal();
  if (value == null) return raw.isEmpty ? '—' : raw;
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

class _RuleDetailField extends StatelessWidget {
  const _RuleDetailField({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style:
              (prominent
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.bodySmall)
                  ?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: prominent ? FontWeight.w600 : FontWeight.w500,
                    height: 1.3,
                  ),
        ),
      ],
    );
  }
}
