import 'package:flutter/material.dart';

import '../../gamepad_navigation.dart';
import '../transient_animation.dart';
import 'style.dart';

class CompactSegmentedButton<T> extends StatefulWidget {
  const CompactSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.expanded = false,
    this.style,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;
  final bool expanded;
  final CompactControlStyle? style;

  @override
  State<CompactSegmentedButton<T>> createState() =>
      _CompactSegmentedButtonState<T>();
}

class _CompactSegmentedButtonState<T> extends State<CompactSegmentedButton<T>> {
  final _stackKey = GlobalKey();
  var _segmentKeys = <GlobalKey>[];
  var _segmentRects = <Rect>[];
  var _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    _syncSegmentKeys();
  }

  @override
  void didUpdateWidget(covariant CompactSegmentedButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSegmentKeys();
  }

  void _syncSegmentKeys() {
    if (_segmentKeys.length == widget.segments.length) return;
    _segmentKeys = List.generate(widget.segments.length, (_) => GlobalKey());
    _segmentRects = const [];
  }

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (stack == null || !stack.hasSize) return;
      final rects = <Rect>[];
      for (final key in _segmentKeys) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        rects.add(box.localToGlobal(Offset.zero, ancestor: stack) & box.size);
      }
      if (_sameRects(_segmentRects, rects)) return;
      setState(() => _segmentRects = rects);
    });
  }

  bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  VoidCallback? _onPressed(int index, int selectedIndex) {
    final segment = widget.segments[index];
    if (!segment.enabled) return null;
    return () {
      if (index != selectedIndex) {
        widget.onSelectionChanged({segment.value});
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.expanded) _scheduleMeasurement();
    final controlStyle =
        widget.style ?? CompactControlTheme.segmentedOf(context);
    final selectedIndex = widget.segments.indexWhere(
      (segment) => widget.selected.contains(segment.value),
    );
    final indicatorRect =
        selectedIndex >= 0 && selectedIndex < _segmentRects.length
        ? _segmentRects[selectedIndex]
        : null;
    return ClipRRect(
      borderRadius: controlStyle.borderRadius,
      child: ColoredBox(
        color: controlStyle.background(context),
        child: SizedBox(
          height: controlStyle.buttonHeight,
          child: Padding(
            padding: EdgeInsets.all(controlStyle.segmentInset),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hasIndicator =
                    selectedIndex >= 0 &&
                    (widget.expanded || indicatorRect != null);
                return Stack(
                  key: _stackKey,
                  children: [
                    if (widget.expanded && selectedIndex >= 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: constraints.maxWidth / widget.segments.length,
                        child: TransientAnimatedSlide(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          offset: Offset(selectedIndex.toDouble(), 0),
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: controlStyle.selectedBackground(context),
                                borderRadius:
                                    controlStyle.indicatorBorderRadius,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (indicatorRect != null)
                      TransientAnimatedValue<Rect>(
                        value: indicatorRect,
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        lerp: _lerpRect,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: controlStyle.selectedBackground(context),
                              borderRadius: controlStyle.indicatorBorderRadius,
                            ),
                          ),
                        ),
                        builder: (_, rect, child) =>
                            Positioned.fromRect(rect: rect, child: child!),
                      ),
                    Row(
                      mainAxisSize: widget.expanded
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.segments.length; i++)
                          if (widget.expanded)
                            Expanded(
                              child: _CompactSegment<T>(
                                key: _segmentKeys[i],
                                segment: widget.segments[i],
                                selected: selectedIndex == i,
                                fallbackBackground: !hasIndicator,
                                style: controlStyle,
                                onPressed: _onPressed(i, selectedIndex),
                              ),
                            )
                          else
                            _CompactSegment<T>(
                              key: _segmentKeys[i],
                              segment: widget.segments[i],
                              selected: selectedIndex == i,
                              fallbackBackground: !hasIndicator,
                              style: controlStyle,
                              onPressed: _onPressed(i, selectedIndex),
                            ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static Rect _lerpRect(Rect begin, Rect end, double progress) =>
      Rect.lerp(begin, end, progress)!;
}

class _CompactSegment<T> extends StatelessWidget {
  const _CompactSegment({
    super.key,
    required this.segment,
    required this.selected,
    required this.fallbackBackground,
    required this.style,
    required this.onPressed,
  });

  final ButtonSegment<T> segment;
  final bool selected;
  final bool fallbackBackground;
  final CompactControlStyle style;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? style.selectedForeground(context)
        : style.foreground(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: segment.enabled,
      child: AppFocusHighlight(
        borderRadius: style.borderRadius,
        child: Container(
          height: style.buttonHeight - style.segmentInset * 2,
          decoration: BoxDecoration(
            color: selected && fallbackBackground
                ? style.selectedBackground(context)
                : Colors.transparent,
            borderRadius: selected && fallbackBackground
                ? style.indicatorBorderRadius
                : style.borderRadius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: style.borderRadius,
              hoverColor: style.hover(context),
              splashColor: style.pressed(context),
              highlightColor: style.pressed(context),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12 * style.widthScale,
                ),
                child: Opacity(
                  opacity: segment.enabled ? 1 : 0.38,
                  child: IconTheme(
                    data: IconThemeData(color: foreground, size: 18),
                    child: DefaultTextStyle.merge(
                      style: style
                          .labelStyle(context)
                          ?.copyWith(color: foreground),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (segment.icon != null) ...[segment.icon!],
                          if (segment.icon != null && segment.label != null)
                            const SizedBox(width: 6),
                          if (segment.label != null) segment.label!,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
