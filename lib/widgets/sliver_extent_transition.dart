import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps one controller for the lifetime of a sliver and removes its subtree
/// only after the collapse animation has finished.
class SliverExpandTransition extends StatefulWidget {
  const SliverExpandTransition({
    super.key,
    required this.expanded,
    required this.duration,
    required this.sliver,
    this.curve = Curves.easeInOutCubic,
    this.slideExtent = 6,
    this.onCollapsed,
  });

  final bool expanded;
  final Duration duration;
  final Curve curve;
  final double slideExtent;
  final Widget sliver;
  final VoidCallback? onCollapsed;

  @override
  State<SliverExpandTransition> createState() => _SliverExpandTransitionState();
}

class _SliverExpandTransitionState extends State<SliverExpandTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late bool _showChild = widget.expanded;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.expanded ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant SliverExpandTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) _animate();
  }

  void _animate() {
    final expanded = widget.expanded;
    final target = expanded ? 1.0 : 0.0;
    final current = _controller.value;
    final generation = ++_generation;
    if (expanded) _showChild = true;
    if (current == target) {
      _showChild = expanded;
      if (!expanded) _notifyCollapsed(generation);
      return;
    }
    final milliseconds =
        (widget.duration.inMilliseconds * (target - current).abs())
            .round()
            .clamp(1, widget.duration.inMilliseconds)
            .toInt();
    _controller
        .animateTo(
          target,
          duration: Duration(milliseconds: milliseconds),
          curve: widget.curve,
        )
        .whenCompleteOrCancel(() {
          if (!mounted ||
              generation != _generation ||
              widget.expanded != expanded ||
              _controller.value != target ||
              expanded) {
            return;
          }
          setState(() => _showChild = false);
          _notifyCollapsed(generation);
        });
  }

  void _notifyCollapsed(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _generation &&
          !widget.expanded &&
          _controller.value == 0) {
        widget.onCollapsed?.call();
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showChild) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return _SliverExtentTransition(
      factor: _controller,
      slideExtent: widget.slideExtent,
      sliver: widget.sliver,
    );
  }
}

/// Clips and scales a sliver's scroll extent without laying out all children.
class _SliverExtentTransition extends SingleChildRenderObjectWidget {
  const _SliverExtentTransition({
    required this.factor,
    this.slideExtent = 0,
    required Widget sliver,
  }) : super(child: sliver);

  final Animation<double> factor;
  final double slideExtent;

  @override
  _RenderSliverExtentTransition createRenderObject(BuildContext context) =>
      _RenderSliverExtentTransition(factor, slideExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverExtentTransition renderObject,
  ) {
    renderObject
      ..factor = factor
      ..slideExtent = slideExtent;
  }
}

class _RenderSliverExtentTransition extends RenderProxySliver {
  _RenderSliverExtentTransition(Animation<double> factor, double slideExtent)
    : _factor = factor,
      _slideExtent = slideExtent;

  Animation<double> _factor;
  double _slideExtent;

  set factor(Animation<double> value) {
    if (identical(value, _factor)) return;
    if (attached) _factor.removeListener(_handleFactorChanged);
    _factor = value;
    if (attached) _factor.addListener(_handleFactorChanged);
    markNeedsLayout();
  }

  void _handleFactorChanged() => markNeedsLayout();

  set slideExtent(double value) {
    if (value == _slideExtent) return;
    _slideExtent = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _factor.addListener(_handleFactorChanged);
  }

  @override
  void detach() {
    _factor.removeListener(_handleFactorChanged);
    super.detach();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final childGeometry = child.geometry!;
    final progress = _factor.value.clamp(0.0, 1.0);
    final maxPaintExtent = childGeometry.maxPaintExtent * progress;
    final paintExtent = math.max(
      0.0,
      math.min(
        childGeometry.paintExtent,
        maxPaintExtent - constraints.scrollOffset,
      ),
    );
    final layoutExtent = math.min(
      childGeometry.layoutExtent,
      childGeometry.paintOrigin + paintExtent,
    );
    final hitTestExtent = math.min(
      childGeometry.hitTestExtent,
      childGeometry.paintOrigin + paintExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: childGeometry.scrollExtent * progress,
      paintOrigin: childGeometry.paintOrigin,
      paintExtent: paintExtent,
      layoutExtent: layoutExtent,
      maxPaintExtent: maxPaintExtent,
      cacheExtent: childGeometry.cacheExtent,
      maxScrollObstructionExtent: childGeometry.maxScrollObstructionExtent,
      visible: progress > 0 && childGeometry.visible,
      hitTestExtent: hitTestExtent,
      hasVisualOverflow: progress < 1 || childGeometry.hasVisualOverflow,
      scrollOffsetCorrection: childGeometry.scrollOffsetCorrection,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || geometry!.paintExtent <= 0) {
      layer = null;
      return;
    }
    if (_factor.value >= 1) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final size = constraints.axis == Axis.vertical
        ? Size(constraints.crossAxisExtent, geometry!.paintExtent)
        : Size(geometry!.paintExtent, constraints.crossAxisExtent);
    final distance = _slideExtent * (1 - _factor.value);
    final direction = applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    );
    final slide = switch (direction) {
      AxisDirection.down => Offset(0, distance),
      AxisDirection.up => Offset(0, -distance),
      AxisDirection.right => Offset(distance, 0),
      AxisDirection.left => Offset(-distance, 0),
    };
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => super.paint(context, offset + slide),
      oldLayer: layer as ClipRectLayer?,
    );
  }
}
