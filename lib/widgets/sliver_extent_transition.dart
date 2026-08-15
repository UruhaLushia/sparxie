import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps one controller and render sliver for the lifetime of an expandable
/// section, then unloads only its contents after collapsing.
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
    return _SliverExtentTransition(
      factor: _controller,
      slideExtent: widget.slideExtent,
      // Keeping the wrapper mounted avoids a one-frame pinned-header reset
      // when a collapsed section releases its heavier list subtree.
      sliver: _showChild
          ? widget.sliver
          : const SliverToBoxAdapter(child: SizedBox.shrink()),
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
  double? _lastProgress;
  double? _lastFullScrollExtent;
  double? _anchoredChildScrollOffset;
  double? _anchorTraversedExtent;
  double _anchorBeyondExtent = 0;
  double? _normalizedGroupScrollOffset;
  double? _lastTargetGroupScrollOffset;

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
      _lastProgress = null;
      _lastFullScrollExtent = null;
      _clearScrollAnchor();
      geometry = SliverGeometry.zero;
      return;
    }
    final progress = _factor.value.clamp(0.0, 1.0);
    final previousProgress = _lastProgress;
    final fullScrollExtent = _lastFullScrollExtent;
    if (_anchoredChildScrollOffset == null &&
        previousProgress != null &&
        fullScrollExtent != null &&
        progress < previousProgress &&
        previousProgress > 0 &&
        constraints.scrollOffset > 0) {
      _captureScrollAnchor(previousProgress, fullScrollExtent);
    }
    final anchoredScrollOffset = _anchoredChildScrollOffset;
    final correction = _scrollOffsetCorrection(progress, previousProgress);
    if (correction != null) {
      _lastProgress = progress;
      geometry = SliverGeometry(scrollOffsetCorrection: correction);
      return;
    }

    child.layout(
      anchoredScrollOffset == null
          ? constraints
          : constraints.copyWith(scrollOffset: anchoredScrollOffset),
      parentUsesSize: true,
    );
    final childGeometry = child.geometry!;
    _lastProgress = progress;
    _lastFullScrollExtent = childGeometry.scrollExtent;
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
    if (progress <= 0 || progress >= 1) _clearScrollAnchor();
  }

  void _captureScrollAnchor(double progress, double fullScrollExtent) {
    final previousExtent = fullScrollExtent * progress;
    final traversed = math.min(constraints.scrollOffset, previousExtent);
    _anchorTraversedExtent = traversed / progress;
    _anchorBeyondExtent = constraints.scrollOffset - traversed;
    _anchoredChildScrollOffset = _anchorBeyondExtent + _anchorTraversedExtent!;
    if (constraints.scrollOffset >= previousExtent) return;

    final groupScrollOffset = _leadingScrollExtent + constraints.scrollOffset;
    _normalizedGroupScrollOffset = groupScrollOffset / progress;
    _lastTargetGroupScrollOffset = groupScrollOffset;
  }

  double? _scrollOffsetCorrection(double progress, double? previousProgress) {
    final traversed = _anchorTraversedExtent;
    if (_anchoredChildScrollOffset == null ||
        traversed == null ||
        previousProgress == null ||
        progress == previousProgress) {
      return null;
    }

    // Keep the child's starting viewport and clip it instead of racing through
    // offscreen rows as the wrapper's scroll range shrinks.
    final normalizedGroupOffset = _normalizedGroupScrollOffset;
    final double correction;
    if (normalizedGroupOffset == null) {
      final target = _anchorBeyondExtent + traversed * progress;
      correction = target - constraints.scrollOffset;
    } else {
      // Stop at the pinned header's start, not its trailing edge, so a
      // following group cannot replace it on the animation's final frame.
      final target = normalizedGroupOffset * progress;
      final current = constraints.scrollOffset > 0
          ? _leadingScrollExtent + constraints.scrollOffset
          : _lastTargetGroupScrollOffset!;
      correction = target - current;
      _lastTargetGroupScrollOffset = target;
    }
    return correction.abs() > 0.01 ? correction : null;
  }

  void _clearScrollAnchor() {
    _anchoredChildScrollOffset = null;
    _anchorTraversedExtent = null;
    _anchorBeyondExtent = 0;
    _normalizedGroupScrollOffset = null;
    _lastTargetGroupScrollOffset = null;
  }

  double get _leadingScrollExtent {
    final parent = this.parent;
    if (parent is! RenderSliver) return 0;
    return math.max(
      0,
      constraints.precedingScrollExtent -
          parent.constraints.precedingScrollExtent,
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
