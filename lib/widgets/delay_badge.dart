import 'package:flutter/material.dart';

import '../utils.dart';
import 'active_listenable_builder.dart';

/// Color-coded latency. Tap to retest.
class DelayBadge extends StatelessWidget {
  const DelayBadge({super.key, required this.delay, required this.onTap});

  final int delay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bucket = classifyDelay(delay);
    final color = switch (bucket) {
      DelayBucket.untested => scheme.onSurfaceVariant,
      DelayBucket.timeout => scheme.error,
      DelayBucket.fast => const Color(0xff10b981),
      DelayBucket.slow => const Color(0xfff59e0b),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          delayLabel(delay),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Subscribes to a node's per-tile delay notifier so byte-frequency repaints
/// don't fan out beyond this widget. Falls back to the "untested" badge when
/// the node has no notifier (e.g. it was evicted between polls).
class NodeDelay extends StatelessWidget {
  const NodeDelay({super.key, required this.delay, required this.onTest});

  final ValueNotifier<int>? delay;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final notifier = delay;
    if (notifier == null) {
      return DelayBadge(delay: -1, onTap: onTest);
    }
    return ActiveValueListenableBuilder<int>(
      valueListenable: notifier,
      pauseWhileScrolling: true,
      builder: (_, ms, _) => DelayBadge(delay: ms, onTap: onTest),
    );
  }
}
