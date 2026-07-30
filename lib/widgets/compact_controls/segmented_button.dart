import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
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
            child: Stack(
              key: _stackKey,
              children: [
                if (indicatorRect != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: indicatorRect.left,
                    top: indicatorRect.top,
                    width: indicatorRect.width,
                    height: indicatorRect.height,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: controlStyle.selectedBackground(context),
                          borderRadius: controlStyle.indicatorBorderRadius,
                        ),
                      ),
                    ),
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
                            fallbackBackground: indicatorRect == null,
                            style: controlStyle,
                            onPressed:
                                widget.segments[i].enabled && selectedIndex != i
                                ? () => widget.onSelectionChanged({
                                    widget.segments[i].value,
                                  })
                                : null,
                          ),
                        )
                      else
                        _CompactSegment<T>(
                          key: _segmentKeys[i],
                          segment: widget.segments[i],
                          selected: selectedIndex == i,
                          fallbackBackground: indicatorRect == null,
                          style: controlStyle,
                          onPressed:
                              widget.segments[i].enabled && selectedIndex != i
                              ? () => widget.onSelectionChanged({
                                  widget.segments[i].value,
                                })
                              : null,
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
              padding: EdgeInsets.symmetric(horizontal: 12 * style.widthScale),
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
    );
  }
}
