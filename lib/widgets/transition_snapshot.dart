import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Uses a transient texture while a short transition is moving on a high
/// refresh-rate display. The live subtree is restored immediately afterward.
class HighRefreshTransitionSnapshot extends StatefulWidget {
  const HighRefreshTransitionSnapshot({
    super.key,
    required this.animation,
    required this.child,
    this.forceSnapshot = false,
  });

  final Animation<double>? animation;
  final Widget child;
  final bool forceSnapshot;

  @override
  State<HighRefreshTransitionSnapshot> createState() =>
      _HighRefreshTransitionSnapshotState();
}

class _HighRefreshTransitionSnapshotState
    extends State<HighRefreshTransitionSnapshot> {
  final _controller = SnapshotController(allowSnapshotting: true);
  var _useSnapshot = false;

  @override
  void initState() {
    super.initState();
    widget.animation?.addStatusListener(_handleAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final refreshRate = View.maybeOf(context)?.display.refreshRate ?? 60;
    _useSnapshot = !kIsWeb && refreshRate > 60;
  }

  @override
  void didUpdateWidget(HighRefreshTransitionSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation?.removeStatusListener(_handleAnimationStatus);
      widget.animation?.addStatusListener(_handleAnimationStatus);
    }
  }

  void _handleAnimationStatus(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  bool get _snapshotActive =>
      widget.forceSnapshot || (widget.animation?.isAnimating ?? false);

  @override
  void dispose() {
    widget.animation?.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Remove the render object entirely once motion ends. Toggling
    // allowSnapshotting can leave a stale texture attached on some high
    // refresh-rate Android renderers even though the live subtree keeps
    // receiving layout and gestures underneath it.
    if (!_useSnapshot || !_snapshotActive) return widget.child;
    return SnapshotWidget(
      controller: _controller,
      mode: SnapshotMode.permissive,
      autoresize: true,
      child: widget.child,
    );
  }
}
