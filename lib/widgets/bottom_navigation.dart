import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_prefs.dart';
import 'app_background.dart';
import 'compact_controls/style.dart';

class AppNavDestination {
  const AppNavDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class SideNavigationRail extends StatelessWidget {
  const SideNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const double itemHeight = 64;

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final leftInset = MediaQuery.paddingOf(context).left;
    return AppSurfaceBackdrop(
      child: ColoredBox(
        color: surfaceTheme.chromeColor(scheme.surface),
        child: SizedBox(
          width: 84 + leftInset,
          child: Padding(
            padding: EdgeInsets.only(left: leftInset),
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    SizedBox(
                      height: itemHeight,
                      child: _SideNavigationRailItem(
                        destination: destinations[i],
                        selected: i == selectedIndex,
                        onTap: () => onSelected(i),
                        scheme: scheme,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavigationRailItem extends StatelessWidget {
  const _SideNavigationRailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(destination.icon, size: 22, color: foreground),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class FloatingBottomNavBar extends StatelessWidget {
  const FloatingBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    required this.style,
    required this.surfaceTheme,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppNavDestination> destinations;
  final NavBarStyle style;
  final AppSurfaceTheme surfaceTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controlStyle = CompactControlTheme.navigationBarOf(context);
    final height = controlStyle.buttonHeight;
    final horizontalInset = (24 + (1 - controlStyle.widthScale) * 40).clamp(
      8.0,
      56.0,
    );
    final isDark = scheme.brightness == Brightness.dark;
    final background = controlStyle.background(context);
    final surfaceColor = surfaceTheme.surfaceColor(background);
    final shadowStrength = surfaceTheme.enabled
        ? surfaceTheme.effectiveSurfaceOpacity()
        : 1.0;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final surface = AppSurfaceBackdrop(
      borderRadius: controlStyle.borderRadius,
      surfaceTheme: surfaceTheme,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: controlStyle.borderRadius,
          border: surfaceTheme.outlineBorder(
            isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: (isDark ? 0.3 : 0.08) * shadowStrength,
              ),
              blurRadius: 16,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(
                alpha: (isDark ? 0.12 : 0.03) * shadowStrength,
              ),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            height: height,
            child: BottomNavBarItems(
              style: style,
              styleConfig: controlStyle,
              destinations: destinations,
              selectedIndex: selectedIndex,
              onSelected: onSelected,
              shrinkWrap: true,
            ),
          ),
        ),
      ),
    );
    final heightOffset = controlStyle.floatingHeightOffset;
    // Upward movement contributes to layout height for Scaffold geometry.
    final upwardOffset = heightOffset.clamp(0, 20).toDouble();
    final downwardOffset = (-heightOffset).clamp(0, 20).toDouble();
    return Transform.translate(
      offset: Offset(0, downwardOffset),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalInset,
          0,
          horizontalInset,
          6 + bottomPadding + upwardOffset,
        ),
        child: Center(heightFactor: 1, child: AppBackdropGroup(child: surface)),
      ),
    );
  }
}

Color _indicatorColor(
  BuildContext context,
  CompactControlStyle style,
  bool isDark,
) => style.selectedBackground(context).withValues(alpha: isDark ? 0.72 : 0.92);

const double _navDragActivationDistance = 26;
const Duration _navAnimationDuration = Duration(milliseconds: 220);

double _dragEdgeStrength(double alignment) =>
    ((alignment.abs() - 0.72) / 0.28).clamp(0.0, 1.0).toDouble();

class _HorizontalDragActivation {
  double? _origin;

  void begin(double position) {
    _origin = position;
  }

  bool accepts(double position) {
    final origin = _origin ?? position;
    _origin = origin;
    return (position - origin).abs() >= _navDragActivationDistance;
  }

  void reset() {
    _origin = null;
  }
}

class _ElasticDragIndicator extends StatelessWidget {
  const _ElasticDragIndicator({
    required this.strength,
    required this.duration,
    required this.child,
  });

  final double strength;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: strength),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.scale(
        scaleX: 1 + value * 0.035,
        scaleY: 1 - value * 0.025,
        child: child,
      ),
      child: child,
    );
  }
}

class BottomNavBarItems extends StatelessWidget {
  const BottomNavBarItems({
    super.key,
    required this.style,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.shrinkWrap = false,
    this.styleConfig,
  });

  final NavBarStyle style;
  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool shrinkWrap;
  final CompactControlStyle? styleConfig;

  static const double _cellWidth = 68;

  Widget _cell(Widget child, CompactControlStyle controlStyle) => shrinkWrap
      ? SizedBox(width: _cellWidth * controlStyle.widthScale, child: child)
      : Expanded(child: child);

  Widget _labeledItem(
    BuildContext context,
    int index,
    CompactControlStyle controlStyle,
    Color selectedColor, {
    int? activeIndex,
  }) {
    return _LabeledNavItem(
      icon: destinations[index].icon,
      label: destinations[index].label,
      selected: index == (activeIndex ?? selectedIndex),
      onTap: () => onSelected(index),
      selectedColor: selectedColor,
      unselectedColor: controlStyle.foreground(context),
    );
  }

  Widget _labeledRow(
    BuildContext context,
    CompactControlStyle controlStyle,
    Color selectedColor, {
    bool fill = false,
    int? activeIndex,
  }) {
    return Row(
      mainAxisSize: fill || !shrinkWrap ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (var i = 0; i < destinations.length; i++)
          fill
              ? Expanded(
                  child: _labeledItem(
                    context,
                    i,
                    controlStyle,
                    selectedColor,
                    activeIndex: activeIndex,
                  ),
                )
              : _cell(
                  _labeledItem(
                    context,
                    i,
                    controlStyle,
                    selectedColor,
                    activeIndex: activeIndex,
                  ),
                  controlStyle,
                ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controlStyle =
        styleConfig ?? CompactControlTheme.navigationBarOf(context);
    final isDark = scheme.brightness == Brightness.dark;
    return switch (style) {
      NavBarStyle.capsule => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _CapsuleNavBar(
          destinations: destinations,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
          shrinkWrap: shrinkWrap,
          styleConfig: controlStyle,
        ),
      ),
      NavBarStyle.pill => _PillNavBar(
        destinationCount: destinations.length,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        styleConfig: controlStyle,
        childBuilder: (activeIndex) => _labeledRow(
          context,
          controlStyle,
          controlStyle.selectedForeground(context),
          fill: true,
          activeIndex: activeIndex,
        ),
      ),
      NavBarStyle.tint => _labeledRow(
        context,
        controlStyle,
        controlStyle.focus(context),
      ),
      NavBarStyle.m3 => Row(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (var i = 0; i < destinations.length; i++)
            _cell(
              _M3NavItem(
                icon: destinations[i].icon,
                label: destinations[i].label,
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
                isDark: isDark,
                styleConfig: controlStyle,
              ),
              controlStyle,
            ),
        ],
      ),
    };
  }
}

class _PillNavBar extends StatefulWidget {
  const _PillNavBar({
    required this.destinationCount,
    required this.selectedIndex,
    required this.onSelected,
    required this.childBuilder,
    required this.styleConfig,
  });

  final int destinationCount;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget Function(int activeIndex) childBuilder;
  final CompactControlStyle styleConfig;

  @override
  State<_PillNavBar> createState() => _PillNavBarState();
}

class _PillNavBarState extends State<_PillNavBar> {
  static const double _indicatorInset = 3;
  static const double _indicatorExtraWidth = 12;
  static const double _contentInset = _indicatorExtraWidth / 2;

  int? _dragIndex;
  double? _dragCenter;
  final _dragActivation = _HorizontalDragActivation();

  int _indexAt(double position, double width) {
    final contentWidth = width - _contentInset * 2;
    final cellWidth = contentWidth / widget.destinationCount;
    return ((position - _contentInset) / cellWidth)
        .floor()
        .clamp(0, widget.destinationCount - 1)
        .toInt();
  }

  double _centerFor(int index, double width) =>
      _contentInset +
      (index + 0.5) * (width - _contentInset * 2) / widget.destinationCount;

  double _indicatorWidth(double width) {
    final cellWidth = (width - _contentInset * 2) / widget.destinationCount;
    return ((cellWidth + _indicatorExtraWidth) *
            widget.styleConfig.indicatorWidthScale)
        .clamp(0, width)
        .toDouble();
  }

  double _clampCenter(double position, double width) {
    final halfWidth = _indicatorWidth(width) / 2;
    return position.clamp(halfWidth, width - halfWidth).toDouble();
  }

  void _startDrag(Offset position, double width) {
    final index = _indexAt(position.dx, width);
    setState(() {
      _dragIndex = index;
      _dragCenter = _clampCenter(position.dx, width);
    });
    unawaited(HapticFeedback.selectionClick());
  }

  void _handleDragUpdate(Offset position, double width) {
    if (_dragIndex == null) {
      if (!_dragActivation.accepts(position.dx)) return;
      _startDrag(position, width);
      return;
    }
    _updateDrag(position, width);
  }

  void _updateDrag(Offset position, double width) {
    final index = _indexAt(position.dx, width);
    final changedIndex = index != _dragIndex;
    setState(() {
      _dragIndex = index;
      _dragCenter = _clampCenter(position.dx, width);
    });
    if (changedIndex) unawaited(HapticFeedback.selectionClick());
  }

  void _finishDrag() {
    final index = _dragIndex;
    if (index != null && index != widget.selectedIndex) {
      widget.onSelected(index);
    }
    _resetDrag();
  }

  void _resetDrag() {
    _dragActivation.reset();
    if (_dragIndex == null && _dragCenter == null) return;
    setState(() {
      _dragIndex = null;
      _dragCenter = null;
    });
  }

  @override
  void didUpdateWidget(covariant _PillNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationCount != widget.destinationCount) {
      _dragIndex = null;
      _dragCenter = null;
      _dragActivation.reset();
    }
  }

  Widget _indicator(
    BuildContext context,
    bool isDark,
    double width,
    double edgeStrength,
    Duration duration,
  ) {
    final height = widget.styleConfig.indicatorHeight
        .clamp(24.0, widget.styleConfig.buttonHeight)
        .toDouble();
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _indicatorInset),
        child: _ElasticDragIndicator(
          strength: edgeStrength,
          duration: duration,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _indicatorColor(context, widget.styleConfig, isDark),
              borderRadius: widget.styleConfig.indicatorBorderRadius,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destinationCount == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : BottomNavBarItems._cellWidth *
                      widget.styleConfig.widthScale *
                      widget.destinationCount +
                  _contentInset * 2;
        if (width <= _contentInset * 2) return const SizedBox.shrink();
        final indicatorWidth = _indicatorWidth(width);
        final indicatorCenter =
            _dragCenter ??
            _clampCenter(_centerFor(widget.selectedIndex, width), width);
        final indicatorAlignment = widget.destinationCount == 1
            ? 0.0
            : -1 +
                  2 *
                      (indicatorCenter - indicatorWidth / 2) /
                      (width - indicatorWidth);
        final dragging = _dragCenter != null;
        final edgeStrength = dragging
            ? _dragEdgeStrength(indicatorAlignment)
            : 0.0;
        final animationDuration = dragging
            ? Duration.zero
            : _navAnimationDuration;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (details) =>
              _dragActivation.begin(details.localPosition.dx),
          onHorizontalDragUpdate: (details) =>
              _handleDragUpdate(details.localPosition, width),
          onHorizontalDragEnd: (_) => _finishDrag(),
          onHorizontalDragCancel: _resetDrag,
          child: SizedBox(
            width: width,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedAlign(
                  duration: animationDuration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(indicatorAlignment, 0),
                  child: _indicator(
                    context,
                    isDark,
                    indicatorWidth,
                    edgeStrength,
                    animationDuration,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _contentInset,
                  ),
                  child: widget.childBuilder(
                    _dragIndex ?? widget.selectedIndex,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CapsuleNavBar extends StatefulWidget {
  const _CapsuleNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.shrinkWrap,
    required this.styleConfig,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool shrinkWrap;
  final CompactControlStyle styleConfig;

  @override
  State<_CapsuleNavBar> createState() => _CapsuleNavBarState();
}

class _CapsuleNavBarState extends State<_CapsuleNavBar> {
  static const double _unselectedWidth = 52;
  static const double _minimumUnselectedWidth = 44;
  static const double _selectedHorizontalPadding = 10;
  static const double _iconSize = 21;
  static const double _iconLabelGap = 6;

  int? _dragIndex;
  double? _dragPosition;
  final _dragActivation = _HorizontalDragActivation();

  int _indexAt(
    double position,
    double selectedWidth,
    double unselectedWidth,
    int activeIndex,
  ) {
    var offset = 0.0;
    for (var i = 0; i < widget.destinations.length; i++) {
      final itemWidth = i == activeIndex ? selectedWidth : unselectedWidth;
      if (position < offset + itemWidth) return i;
      offset += itemWidth;
    }
    return widget.destinations.length - 1;
  }

  void _startDrag(int index, double position) {
    setState(() {
      _dragIndex = index;
      _dragPosition = position;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  void _handleDragUpdate(
    double position,
    int Function(double position) indexAt,
  ) {
    if (_dragIndex == null) {
      if (!_dragActivation.accepts(position)) return;
      _startDrag(indexAt(position), position);
      return;
    }
    _updateDrag(indexAt(position), position);
  }

  void _updateDrag(int index, double position) {
    final changedIndex = index != _dragIndex;
    setState(() {
      _dragIndex = index;
      _dragPosition = position;
    });
    if (changedIndex) unawaited(HapticFeedback.selectionClick());
  }

  void _finishDrag() {
    final index = _dragIndex;
    if (index != null && index != widget.selectedIndex) {
      widget.onSelected(index);
    }
    _resetDrag();
  }

  void _resetDrag() {
    _dragActivation.reset();
    if (_dragIndex == null && _dragPosition == null) return;
    setState(() {
      _dragIndex = null;
      _dragPosition = null;
    });
  }

  @override
  void didUpdateWidget(covariant _CapsuleNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.length != widget.destinations.length) {
      _dragIndex = null;
      _dragPosition = null;
      _dragActivation.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destinations.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final widthScale = widget.styleConfig.widthScale;
    final selectedColor = widget.styleConfig.selectedForeground(context);
    final unselectedColor = widget.styleConfig.foreground(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: selectedColor,
    );
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final selectedWidths = <double>[];
    for (final destination in widget.destinations) {
      final painter = TextPainter(
        text: TextSpan(text: destination.label, style: labelStyle),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      selectedWidths.add(
        _selectedHorizontalPadding * widthScale * 2 +
            _iconSize +
            _iconLabelGap * widthScale +
            painter.width,
      );
    }
    final naturalWidth =
        selectedWidths.reduce(math.max) +
        _unselectedWidth * widthScale * (widget.destinations.length - 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final requestedWidth = widget.shrinkWrap || !constraints.hasBoundedWidth
            ? naturalWidth
            : constraints.maxWidth;
        final width = constraints.constrainWidth(requestedWidth);
        if (width <= 0) return const SizedBox.shrink();
        final activeIndex = (_dragIndex ?? widget.selectedIndex)
            .clamp(0, widget.destinations.length - 1)
            .toInt();
        final minimumUnselectedWidth = _minimumUnselectedWidth * widthScale;
        final minimumSelectedWidth = math.min(
          _unselectedWidth * widthScale,
          width,
        );
        final availableSelectedWidth = widget.destinations.length == 1
            ? width
            : width - minimumUnselectedWidth * (widget.destinations.length - 1);
        final maximumSelectedWidth = availableSelectedWidth
            .clamp(minimumSelectedWidth, width)
            .toDouble();
        final selectedWidth = selectedWidths[activeIndex]
            .clamp(minimumSelectedWidth, maximumSelectedWidth)
            .toDouble();
        final unselectedWidth = widget.destinations.length == 1
            ? 0.0
            : (width - selectedWidth) / (widget.destinations.length - 1);
        int indexAt(double position) => _indexAt(
          position.clamp(0, width).toDouble(),
          selectedWidth,
          unselectedWidth,
          activeIndex,
        );
        final dragPosition = _dragPosition;
        final indicatorLeft = dragPosition == null
            ? activeIndex * unselectedWidth
            : (dragPosition - selectedWidth / 2)
                  .clamp(0, width - selectedWidth)
                  .toDouble();
        final positionDuration = dragPosition == null
            ? _navAnimationDuration
            : Duration.zero;
        final edgeStrength = dragPosition == null
            ? 0.0
            : _dragEdgeStrength(dragPosition / width * 2 - 1);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (details) =>
              _dragActivation.begin(details.localPosition.dx),
          onHorizontalDragUpdate: (details) =>
              _handleDragUpdate(details.localPosition.dx, indexAt),
          onHorizontalDragEnd: (_) => _finishDrag(),
          onHorizontalDragCancel: _resetDrag,
          child: SizedBox(
            width: width,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedPositioned(
                  left: indicatorLeft,
                  top: 0,
                  bottom: 0,
                  width: selectedWidth,
                  duration: positionDuration,
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    child: Center(
                      child: Transform.scale(
                        scaleX: widget.styleConfig.indicatorWidthScale,
                        child: SizedBox(
                          width: double.infinity,
                          height: widget.styleConfig.indicatorHeight
                              .clamp(24.0, widget.styleConfig.buttonHeight)
                              .toDouble(),
                          child: _ElasticDragIndicator(
                            strength: edgeStrength,
                            duration: positionDuration,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _indicatorColor(
                                  context,
                                  widget.styleConfig,
                                  isDark,
                                ),
                                borderRadius:
                                    widget.styleConfig.indicatorBorderRadius,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < widget.destinations.length; i++)
                      AnimatedContainer(
                        width: i == activeIndex
                            ? selectedWidth
                            : unselectedWidth,
                        height: double.infinity,
                        duration: _navAnimationDuration,
                        curve: Curves.easeOutCubic,
                        child: _CapsuleNavItem(
                          destination: widget.destinations[i],
                          selected: i == activeIndex,
                          onTap: () => widget.onSelected(i),
                          itemWidth: i == activeIndex
                              ? selectedWidth
                              : unselectedWidth,
                          labelStyle: labelStyle,
                          selectedColor: selectedColor,
                          unselectedColor: unselectedColor,
                          widthScale: widthScale,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CapsuleNavItem extends StatelessWidget {
  const _CapsuleNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.itemWidth,
    required this.labelStyle,
    required this.selectedColor,
    required this.unselectedColor,
    required this.widthScale,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final double itemWidth;
  final TextStyle labelStyle;
  final Color selectedColor;
  final Color unselectedColor;
  final double widthScale;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? selectedColor : unselectedColor;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: ClipRect(
            child: AnimatedContainer(
              width: selected ? itemWidth : 42,
              height: 42,
              duration: _navAnimationDuration,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: selected
                    ? _CapsuleNavBarState._selectedHorizontalPadding *
                          widthScale
                    : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    destination.icon,
                    size: _CapsuleNavBarState._iconSize,
                    color: foreground,
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: selected ? 1 : 0),
                    duration: _navAnimationDuration,
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: Opacity(
                          opacity: ((value - 0.95) / 0.05)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                          child: child,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: _CapsuleNavBarState._iconLabelGap * widthScale,
                      ),
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: labelStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledNavItem extends StatelessWidget {
  const _LabeledNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.unselectedColor,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color unselectedColor;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? selectedColor
        : unselectedColor.withValues(alpha: 0.72);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: fg),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, child) =>
                      Icon(icon, size: 22, color: color),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  fontSize: 10,
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _M3NavItem extends StatelessWidget {
  const _M3NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    required this.styleConfig,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final CompactControlStyle styleConfig;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 48 * styleConfig.indicatorWidthScale,
              height: styleConfig.indicatorHeight
                  .clamp(24.0, styleConfig.buttonHeight - 18)
                  .toDouble(),
              decoration: BoxDecoration(
                color: selected
                    ? _indicatorColor(context, styleConfig, isDark)
                    : Colors.transparent,
                borderRadius: styleConfig.indicatorBorderRadius,
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? styleConfig.selectedForeground(context)
                    : styleConfig.foreground(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: selected
                    ? styleConfig.selectedForeground(context)
                    : styleConfig.foreground(context).withValues(alpha: 0.72),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
