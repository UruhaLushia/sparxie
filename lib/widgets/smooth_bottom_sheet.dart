import 'package:flutter/material.dart';

import 'transition_snapshot.dart';

Future<T?> showSmoothModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool enableDrag = true,
}) {
  final navigator = Navigator.of(context);
  final theme = Theme.of(context);
  return navigator.push<T>(
    _SmoothModalBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      barrierColor: theme.bottomSheetTheme.modalBarrierColor ?? Colors.black54,
      showDragHandle: showDragHandle,
      enableDrag: enableDrag,
    ),
  );
}

class _SmoothModalBottomSheetRoute<T> extends PopupRoute<T> {
  _SmoothModalBottomSheetRoute({
    required this.builder,
    required this.capturedThemes,
    required this.barrierLabel,
    required this.barrierColor,
    required this.showDragHandle,
    required this.enableDrag,
  });

  final WidgetBuilder builder;
  final CapturedThemes capturedThemes;
  final bool showDragHandle;
  final bool enableDrag;

  @override
  final String barrierLabel;

  @override
  final Color barrierColor;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  AnimationController get sheetController => controller!;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: _SmoothModalBottomSheet<T>(route: this),
      ),
    );
  }
}

class _SmoothModalBottomSheet<T> extends StatefulWidget {
  const _SmoothModalBottomSheet({required this.route});

  final _SmoothModalBottomSheetRoute<T> route;

  @override
  State<_SmoothModalBottomSheet<T>> createState() =>
      _SmoothModalBottomSheetState<T>();
}

class _SmoothModalBottomSheetState<T>
    extends State<_SmoothModalBottomSheet<T>> {
  late final CurvedAnimation _curvedAnimation = CurvedAnimation(
    parent: widget.route.animation!,
    curve: Easing.legacyDecelerate,
    reverseCurve: Easing.legacyDecelerate,
  );
  late final ProxyAnimation _positionAnimation = ProxyAnimation(
    _curvedAnimation,
  );
  late final Animation<Offset> _slideAnimation = _positionAnimation.drive(
    Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero),
  );

  void _handleDragStart(DragStartDetails _) {
    _positionAnimation.parent = widget.route.animation;
  }

  void _handleDragEnd(DragEndDetails _, {bool? isClosing}) {
    final animation = widget.route.animation!;
    final progress = animation.value;
    _positionAnimation.parent = CurvedAnimation(
      parent: animation,
      curve: Split(progress, endCurve: Easing.legacyDecelerate),
      reverseCurve: Split(progress, endCurve: Easing.legacyDecelerate),
    );
  }

  void _close() {
    if (widget.route.isCurrent) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _positionAnimation.parent = kAlwaysDismissedAnimation;
    _curvedAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = BottomSheet(
      animationController: widget.route.sheetController,
      onClosing: _close,
      builder: widget.route.builder,
      enableDrag: widget.route.enableDrag,
      showDragHandle: widget.route.showDragHandle,
      onDragStart: _handleDragStart,
      onDragEnd: _handleDragEnd,
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: _slideAnimation,
            child: HighRefreshTransitionSnapshot(
              animation: widget.route.animation,
              child: RepaintBoundary(child: sheet),
            ),
          ),
        ),
      ),
    );
  }
}
