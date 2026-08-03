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
  final _controller = SnapshotController();
  var _useSnapshot = false;
  var _releaseGeneration = 0;

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
    _syncSnapshot();
  }

  @override
  void didUpdateWidget(HighRefreshTransitionSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation?.removeStatusListener(_handleAnimationStatus);
      widget.animation?.addStatusListener(_handleAnimationStatus);
    }
    _syncSnapshot();
  }

  void _handleAnimationStatus(AnimationStatus _) => _syncSnapshot();

  bool get _snapshotActive =>
      widget.forceSnapshot || (widget.animation?.isAnimating ?? false);

  void _syncSnapshot() {
    if (_useSnapshot && _snapshotActive) {
      _releaseGeneration++;
      _controller.allowSnapshotting = true;
      return;
    }

    final generation = ++_releaseGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _releaseGeneration || _snapshotActive) {
        return;
      }
      _controller.allowSnapshotting = false;
    });
  }

  @override
  void dispose() {
    _releaseGeneration++;
    widget.animation?.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_useSnapshot) return widget.child;
    return SnapshotWidget(
      controller: _controller,
      mode: SnapshotMode.permissive,
      autoresize: true,
      child: widget.child,
    );
  }
}
