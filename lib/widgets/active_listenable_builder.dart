import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Stops listening to frequently changing values while its page is hidden by
/// a [TickerMode]. The latest value is read again as soon as the page becomes
/// active, so cached pages do not request frames in the background.
class ActiveValueListenableBuilder<T> extends StatelessWidget {
  const ActiveValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.child,
  });

  final ValueListenable<T> valueListenable;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.valuesOf(context).enabled) {
      return builder(context, valueListenable.value, child);
    }
    return ValueListenableBuilder<T>(
      valueListenable: valueListenable,
      builder: builder,
      child: child,
    );
  }
}

class ActiveListenableBuilder extends StatelessWidget {
  const ActiveListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.valuesOf(context).enabled) return builder(context, child);
    return ListenableBuilder(
      listenable: listenable,
      builder: builder,
      child: child,
    );
  }
}
