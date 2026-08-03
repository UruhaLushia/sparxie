import 'package:flutter/material.dart';

import 'app_background.dart';
import 'transition_snapshot.dart';

Future<T?> showSettingsDrawer<T>({
  required BuildContext context,
  required String barrierLabel,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (_, animation, _, child) =>
        _SettingsDrawerTransition(animation: animation, child: child),
    pageBuilder: (context, _, _) => builder(context),
  );
}

typedef SettingsDrawerChildrenBuilder =
    List<Widget> Function(BuildContext context);

class SettingsDrawerSheet extends StatelessWidget {
  const SettingsDrawerSheet({
    super.key,
    required this.title,
    required this.listenable,
    required this.childrenBuilder,
  });

  final String title;
  final Listenable listenable;
  final SettingsDrawerChildrenBuilder childrenBuilder;

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
                _SettingsDrawerHeader(title: title),
                const Divider(height: 1),
                Expanded(
                  child: ListenableBuilder(
                    listenable: listenable,
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: childrenBuilder(context),
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

class SettingsDrawerSection extends StatelessWidget {
  const SettingsDrawerSection({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

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

class _SettingsDrawerHeader extends StatelessWidget {
  const _SettingsDrawerHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _SettingsDrawerTransition extends StatelessWidget {
  const _SettingsDrawerTransition({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final liveChild = RepaintBoundary(child: child);
    final transitionChild = AppSurfaceTheme.of(context).effectiveBlur > 0
        ? liveChild
        : HighRefreshTransitionSnapshot(animation: animation, child: liveChild);
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedBuilder(
        animation: animation,
        child: transitionChild,
        builder: (_, child) {
          final progress = Curves.easeOutCubic.transform(
            animation.value.clamp(0.0, 1.0),
          );
          if (progress >= 0.999) return child!;
          return FractionalTranslation(
            translation: Offset(1 - progress, 0),
            child: child,
          );
        },
      ),
    );
  }
}
