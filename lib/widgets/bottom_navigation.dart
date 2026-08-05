import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_prefs.dart';
import '../gamepad_navigation.dart';
import 'app_background.dart';
import 'compact_controls/style.dart';
import 'transient_animation.dart';

class AppNavDestination {
  const AppNavDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

double _sideIndicatorWidth(double availableWidth, CompactControlStyle style) {
  final baseWidth = math.max(36.0, availableWidth - 12);
  return (baseWidth * style.indicatorWidthScale)
      .clamp(math.min(36.0, availableWidth), availableWidth)
      .toDouble();
}

class SideNavigationRail extends StatelessWidget {
  const SideNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.style,
    required this.surfaceTheme,
    this.styleConfig,
  });

  static double itemHeightFor(CompactControlStyle style) =>
      style.buttonHeight.clamp(52.0, 76.0).toDouble();

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final NavBarStyle style;
  final AppSurfaceTheme surfaceTheme;
  final CompactControlStyle? styleConfig;

  @override
  Widget build(BuildContext context) {
    final controlStyle =
        styleConfig ?? CompactControlTheme.navigationBarOf(context);
    final leftInset = MediaQuery.paddingOf(context).left;
    final itemHeight = itemHeightFor(controlStyle);
    final railWidth = (84 * controlStyle.widthScale)
        .clamp(68.0, 116.0)
        .toDouble();
    return AppSurfaceBackdrop(
      surfaceTheme: surfaceTheme,
      child: ColoredBox(
        color: surfaceTheme.surfaceColor(controlStyle.background(context)),
        child: SizedBox(
          width: railWidth + leftInset,
          child: Padding(
            padding: EdgeInsets.only(left: leftInset),
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SideNavigationRailItems(
                    destinations: destinations,
                    selectedIndex: selectedIndex,
                    onSelected: onSelected,
                    style: style,
                    styleConfig: controlStyle,
                    itemHeight: itemHeight,
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

class _SideNavigationRailItems extends StatelessWidget {
  const _SideNavigationRailItems({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.style,
    required this.styleConfig,
    required this.itemHeight,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final NavBarStyle style;
  final CompactControlStyle styleConfig;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) return const SizedBox.shrink();
    final items = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < destinations.length; i++)
          SizedBox(
            height: itemHeight,
            child: _SideNavigationRailItem(
              destination: destinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
              style: style,
              styleConfig: styleConfig,
            ),
          ),
      ],
    );
    if (style != NavBarStyle.pill) return items;
    final activeIndex = selectedIndex.clamp(0, destinations.length - 1).toInt();
    final indicatorHeight = styleConfig.indicatorHeight
        .clamp(28.0, itemHeight - 8)
        .toDouble();
    final top = activeIndex * itemHeight + (itemHeight - indicatorHeight) / 2;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(0.0, constraints.maxWidth - 12);
        final indicatorWidth = _sideIndicatorWidth(availableWidth, styleConfig);
        return SizedBox(
          height: destinations.length * itemHeight,
          child: Stack(
            children: [
              TransientAnimatedValue<Rect>(
                value: Rect.fromLTWH(
                  (constraints.maxWidth - indicatorWidth) / 2,
                  top,
                  indicatorWidth,
                  indicatorHeight,
                ),
                duration: _navAnimationDuration,
                curve: Curves.easeOutCubic,
                lerp: _lerpRect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _indicatorColor(context, styleConfig, isDark),
                    borderRadius: styleConfig.indicatorBorderRadius,
                  ),
                ),
                builder: (_, rect, child) =>
                    Positioned.fromRect(rect: rect, child: child!),
              ),
              items,
            ],
          ),
        );
      },
    );
  }
}

class _SideNavigationRailItem extends StatefulWidget {
  const _SideNavigationRailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.style,
    required this.styleConfig,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final NavBarStyle style;
  final CompactControlStyle styleConfig;

  @override
  State<_SideNavigationRailItem> createState() =>
      _SideNavigationRailItemState();
}

class _SideNavigationRailItemState extends State<_SideNavigationRailItem> {
  final _statesController = WidgetStatesController();

  @override
  void dispose() {
    _statesController.dispose();
    super.dispose();
  }

  Color _withStateLayer(
    BuildContext context,
    CompactControlStyle style,
    Color background,
    Set<WidgetState> states,
  ) {
    final overlay = states.contains(WidgetState.pressed)
        ? style.pressed(context)
        : states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)
        ? style.hover(context)
        : null;
    return overlay == null ? background : Color.alphaBlend(overlay, background);
  }

  Size _indicatorSize(
    BoxConstraints constraints,
    CompactControlStyle style, {
    required double minHeight,
  }) {
    final availableWidth = constraints.maxWidth;
    return Size(
      _sideIndicatorWidth(availableWidth, style),
      style.indicatorHeight.clamp(minHeight, constraints.maxHeight).toDouble(),
    );
  }

  Widget _buildVisual(BuildContext context, Set<WidgetState> states) {
    final destination = widget.destination;
    final selected = widget.selected;
    final style = widget.style;
    final styleConfig = widget.styleConfig;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedForeground = style == NavBarStyle.tint
        ? _surfaceAccentForeground(context, styleConfig)
        : _indicatorForeground(context, styleConfig, isDark);
    final unselectedForeground = styleConfig
        .foreground(context)
        .withValues(alpha: style == NavBarStyle.capsule ? 1 : 0.72);
    final foreground = selected ? selectedForeground : unselectedForeground;
    final labelForeground = style == NavBarStyle.m3 && selected
        ? styleConfig.foreground(context)
        : foreground;
    final capsule = style == NavBarStyle.capsule;
    final showLabel = style != NavBarStyle.capsule || selected;
    final material3IndicatorHeight = styleConfig.indicatorHeight
        .clamp(
          24.0,
          math.max(24.0, math.min(38.0, styleConfig.buttonHeight - 23)),
        )
        .toDouble();
    final icon = style == NavBarStyle.m3
        ? TransientAnimatedValue<_NavBoxVisual>(
            value: (
              width: (48 * styleConfig.indicatorWidthScale)
                  .clamp(36.0, 56.0)
                  .toDouble(),
              height: material3IndicatorHeight,
              decoration: BoxDecoration(
                color: _withStateLayer(
                  context,
                  styleConfig,
                  selected
                      ? _indicatorColor(context, styleConfig, isDark)
                      : Colors.transparent,
                  states,
                ),
                borderRadius: styleConfig.indicatorBorderRadius,
              ),
            ),
            duration: _navAnimationDuration,
            curve: Curves.easeOutCubic,
            lerp: _lerpNavBox,
            child: Icon(destination.icon, size: 20, color: foreground),
            builder: (_, visual, child) => Container(
              width: visual.width,
              height: visual.height,
              decoration: visual.decoration,
              child: child,
            ),
          )
        : TransientAnimatedScale(
            scale: selected && style != NavBarStyle.capsule ? 1.12 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: TransientAnimatedValue<Color>(
              value: foreground,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              lerp: _lerpColor,
              builder: (context, color, child) =>
                  Icon(destination.icon, size: 22, color: color),
            ),
          );
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          TransientAnimatedValue<double>(
            value: showLabel ? 1 : 0,
            duration: _navAnimationDuration,
            curve: Curves.easeOutCubic,
            lerp: _lerpDouble,
            builder: (context, value, child) => ClipRect(
              child: Align(
                heightFactor: value,
                child: Opacity(opacity: value, child: child),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: capsule ? 10.5 : 10,
                  color: labelForeground,
                  fontWeight: selected
                      ? style == NavBarStyle.m3
                            ? FontWeight.w600
                            : FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (style == NavBarStyle.m3) return content;
        final size = _indicatorSize(
          constraints,
          styleConfig,
          minHeight: capsule ? 40 : 28,
        );
        final background = capsule && selected
            ? _indicatorColor(context, styleConfig, isDark)
            : Colors.transparent;
        final stateLayer = TransientAnimatedValue<_NavBoxVisual>(
          value: (
            width: size.width,
            height: style == NavBarStyle.tint
                ? constraints.maxHeight
                : size.height,
            decoration: BoxDecoration(
              color: _withStateLayer(context, styleConfig, background, states),
              borderRadius: styleConfig.indicatorBorderRadius,
            ),
          ),
          duration: _navAnimationDuration,
          curve: Curves.easeOutCubic,
          lerp: _lerpNavBox,
          child: capsule ? content : null,
          builder: (_, visual, child) => Container(
            width: visual.width,
            height: visual.height,
            decoration: visual.decoration,
            child: child,
          ),
        );
        if (capsule) return Center(child: stateLayer);
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Center(child: stateLayer),
            content,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: AppFocusHighlight(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            statesController: _statesController,
            onTap: widget.onTap,
            excludeFromSemantics: true,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            child: Semantics(
              button: true,
              selected: widget.selected,
              label: widget.destination.label,
              excludeSemantics: true,
              child: Tooltip(
                message: widget.destination.label,
                child: ValueListenableBuilder<Set<WidgetState>>(
                  valueListenable: _statesController,
                  builder: (context, states, _) =>
                      _buildVisual(context, states),
                ),
              ),
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
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: controlStyle.borderRadius,
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
      child: AppSurfaceBackdrop(
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

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

Color _readableForeground(
  Color preferred,
  Color background, {
  required Color fallback,
}) {
  if (_contrastRatio(preferred, background) >= 4.5) return preferred;
  if (_contrastRatio(fallback, background) >= 4.5) return fallback;
  final blackContrast = _contrastRatio(Colors.black, background);
  final whiteContrast = _contrastRatio(Colors.white, background);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

Color _indicatorForeground(
  BuildContext context,
  CompactControlStyle style,
  bool isDark,
) {
  final surface = style.background(context);
  final indicator = Color.alphaBlend(
    _indicatorColor(context, style, isDark),
    surface,
  );
  return _readableForeground(
    style.selectedForeground(context),
    indicator,
    fallback: style.foreground(context),
  );
}

Color _surfaceAccentForeground(
  BuildContext context,
  CompactControlStyle style,
) => _readableForeground(
  style.focus(context),
  style.background(context),
  fallback: style.foreground(context),
);

const double _navDragActivationDistance = 26;
const Duration _navAnimationDuration = Duration(milliseconds: 220);

typedef _NavBoxVisual = ({
  double width,
  double height,
  BoxDecoration decoration,
});
typedef _HorizontalExtent = ({double left, double width});
typedef _CapsuleContentVisual = ({double width, EdgeInsets padding});

double _lerpDouble(double begin, double end, double progress) =>
    begin + (end - begin) * progress;

Color _lerpColor(Color begin, Color end, double progress) =>
    Color.lerp(begin, end, progress)!;

Alignment _lerpAlignment(Alignment begin, Alignment end, double progress) =>
    Alignment.lerp(begin, end, progress)!;

Rect _lerpRect(Rect begin, Rect end, double progress) =>
    Rect.lerp(begin, end, progress)!;

TextStyle _lerpTextStyle(TextStyle begin, TextStyle end, double progress) =>
    TextStyle.lerp(begin, end, progress)!;

_NavBoxVisual _lerpNavBox(
  _NavBoxVisual begin,
  _NavBoxVisual end,
  double progress,
) => (
  width: _lerpDouble(begin.width, end.width, progress),
  height: _lerpDouble(begin.height, end.height, progress),
  decoration: BoxDecoration.lerp(begin.decoration, end.decoration, progress)!,
);

_HorizontalExtent _lerpHorizontalExtent(
  _HorizontalExtent begin,
  _HorizontalExtent end,
  double progress,
) => (
  left: _lerpDouble(begin.left, end.left, progress),
  width: _lerpDouble(begin.width, end.width, progress),
);

_CapsuleContentVisual _lerpCapsuleContent(
  _CapsuleContentVisual begin,
  _CapsuleContentVisual end,
  double progress,
) => (
  width: _lerpDouble(begin.width, end.width, progress),
  padding: EdgeInsets.lerp(begin.padding, end.padding, progress)!,
);

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
    return TransientAnimatedValue<double>(
      value: strength,
      duration: duration,
      curve: Curves.easeOutCubic,
      lerp: _lerpDouble,
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
      ? Flexible(
          child: SizedBox(
            width: _cellWidth * controlStyle.widthScale,
            child: child,
          ),
        )
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
    final indicatorForeground = _indicatorForeground(
      context,
      controlStyle,
      isDark,
    );
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
          indicatorForeground,
          fill: true,
          activeIndex: activeIndex,
        ),
      ),
      NavBarStyle.tint => _labeledRow(
        context,
        controlStyle,
        _surfaceAccentForeground(context, controlStyle),
      ),
      NavBarStyle.m3 => Row(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (var i = 0; i < destinations.length; i++)
            _cell(
              _Material3NavItem(
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
  final _dragCenter = ValueNotifier<double?>(null);
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
    _dragCenter.value = _clampCenter(position.dx, width);
    setState(() => _dragIndex = index);
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
    _dragCenter.value = _clampCenter(position.dx, width);
    if (changedIndex) setState(() => _dragIndex = index);
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
    if (_dragIndex == null && _dragCenter.value == null) return;
    _dragCenter.value = null;
    setState(() => _dragIndex = null);
  }

  @override
  void didUpdateWidget(covariant _PillNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationCount != widget.destinationCount) {
      _dragIndex = null;
      _dragCenter.value = null;
      _dragActivation.reset();
    }
  }

  @override
  void dispose() {
    _dragCenter.dispose();
    super.dispose();
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
                ValueListenableBuilder<double?>(
                  valueListenable: _dragCenter,
                  builder: (context, dragCenter, _) {
                    final indicatorCenter =
                        dragCenter ??
                        _clampCenter(
                          _centerFor(widget.selectedIndex, width),
                          width,
                        );
                    final indicatorAlignment = widget.destinationCount == 1
                        ? 0.0
                        : -1 +
                              2 *
                                  (indicatorCenter - indicatorWidth / 2) /
                                  (width - indicatorWidth);
                    final dragging = dragCenter != null;
                    final duration = dragging
                        ? Duration.zero
                        : _navAnimationDuration;
                    return TransientAnimatedValue<Alignment>(
                      value: Alignment(indicatorAlignment, 0),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      lerp: _lerpAlignment,
                      child: _indicator(
                        context,
                        isDark,
                        indicatorWidth,
                        dragging ? _dragEdgeStrength(indicatorAlignment) : 0,
                        duration,
                      ),
                      builder: (_, alignment, child) =>
                          Align(alignment: alignment, child: child),
                    );
                  },
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
  final _dragPosition = ValueNotifier<double?>(null);
  final _dragActivation = _HorizontalDragActivation();
  var _metricsDirty = true;
  List<double> _selectedWidths = const [];
  var _naturalWidth = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _metricsDirty = true;
  }

  @override
  void reassemble() {
    super.reassemble();
    _metricsDirty = true;
  }

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
    _dragPosition.value = position;
    setState(() => _dragIndex = index);
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
    _dragPosition.value = position;
    if (changedIndex) setState(() => _dragIndex = index);
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
    if (_dragIndex == null && _dragPosition.value == null) return;
    _dragPosition.value = null;
    setState(() => _dragIndex = null);
  }

  @override
  void didUpdateWidget(covariant _CapsuleNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.destinations, widget.destinations) ||
        oldWidget.styleConfig != widget.styleConfig) {
      _metricsDirty = true;
    }
    if (oldWidget.destinations.length != widget.destinations.length) {
      _dragIndex = null;
      _dragPosition.value = null;
      _dragActivation.reset();
    }
  }

  void _ensureLabelMetrics(
    TextStyle labelStyle,
    TextDirection textDirection,
    TextScaler textScaler,
    double widthScale,
  ) {
    if (!_metricsDirty) return;
    final widths = <double>[];
    for (final destination in widget.destinations) {
      final painter = TextPainter(
        text: TextSpan(text: destination.label, style: labelStyle),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      final textWidth = painter.width;
      painter.dispose();
      widths.add(
        _selectedHorizontalPadding * widthScale * 2 +
            _iconSize +
            _iconLabelGap * widthScale +
            textWidth,
      );
    }
    _selectedWidths = widths;
    _naturalWidth =
        widths.reduce(math.max) +
        _unselectedWidth * widthScale * (widget.destinations.length - 1);
    _metricsDirty = false;
  }

  @override
  void dispose() {
    _dragPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destinations.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final widthScale = widget.styleConfig.widthScale;
    final selectedColor = _indicatorForeground(
      context,
      widget.styleConfig,
      isDark,
    );
    final unselectedColor = widget.styleConfig.foreground(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: selectedColor,
    );
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    _ensureLabelMetrics(labelStyle, textDirection, textScaler, widthScale);
    final selectedWidths = _selectedWidths;
    final naturalWidth = _naturalWidth;
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
        final itemDuration = _dragPosition.value == null
            ? _navAnimationDuration
            : Duration.zero;
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
                ValueListenableBuilder<double?>(
                  valueListenable: _dragPosition,
                  builder: (context, dragPosition, _) {
                    final indicatorLeft = dragPosition == null
                        ? activeIndex * unselectedWidth
                        : (dragPosition - selectedWidth / 2)
                              .clamp(0, width - selectedWidth)
                              .toDouble();
                    final duration = dragPosition == null
                        ? _navAnimationDuration
                        : Duration.zero;
                    final edgeStrength = dragPosition == null
                        ? 0.0
                        : _dragEdgeStrength(dragPosition / width * 2 - 1);
                    return TransientAnimatedValue<_HorizontalExtent>(
                      value: (left: indicatorLeft, width: selectedWidth),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      lerp: _lerpHorizontalExtent,
                      builder: (_, extent, child) => Positioned(
                        left: extent.left,
                        top: 0,
                        bottom: 0,
                        width: extent.width,
                        child: child!,
                      ),
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
                                duration: duration,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _indicatorColor(
                                      context,
                                      widget.styleConfig,
                                      isDark,
                                    ),
                                    borderRadius: widget
                                        .styleConfig
                                        .indicatorBorderRadius,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    for (var i = 0; i < widget.destinations.length; i++)
                      TransientAnimatedValue<double>(
                        value: i == activeIndex
                            ? selectedWidth
                            : unselectedWidth,
                        duration: itemDuration,
                        curve: Curves.easeOutCubic,
                        lerp: _lerpDouble,
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
                          styleConfig: widget.styleConfig,
                        ),
                        builder: (_, width, child) => SizedBox(
                          width: width,
                          height: double.infinity,
                          child: child,
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

class _CapsuleNavItem extends StatefulWidget {
  const _CapsuleNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.itemWidth,
    required this.labelStyle,
    required this.selectedColor,
    required this.unselectedColor,
    required this.widthScale,
    required this.styleConfig,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final double itemWidth;
  final TextStyle labelStyle;
  final Color selectedColor;
  final Color unselectedColor;
  final double widthScale;
  final CompactControlStyle styleConfig;

  @override
  State<_CapsuleNavItem> createState() => _CapsuleNavItemState();
}

class _CapsuleNavItemState extends State<_CapsuleNavItem> {
  final _statesController = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_handleHighlightModeChange);
  }

  void _handleHighlightModeChange(FocusHighlightMode _) {
    if (mounted && _statesController.value.contains(WidgetState.focused)) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(
      _handleHighlightModeChange,
    );
    _statesController.dispose();
    super.dispose();
  }

  Widget _stateLayer(BuildContext context, Set<WidgetState> states) {
    final style = widget.styleConfig;
    final focused =
        states.contains(WidgetState.focused) &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final baseWidth = widget.selected ? widget.itemWidth : 42.0;
    return Center(
      child: Container(
        width: baseWidth * style.indicatorWidthScale,
        height: style.indicatorHeight
            .clamp(24.0, style.buttonHeight)
            .toDouble(),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: style.indicatorBorderRadius,
          border: focused
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.selected
        ? widget.selectedColor
        : widget.unselectedColor;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.destination.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          statesController: _statesController,
          onTap: widget.onTap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          child: ValueListenableBuilder<Set<WidgetState>>(
            valueListenable: _statesController,
            builder: (context, states, child) => Stack(
              fit: StackFit.expand,
              children: [_stateLayer(context, states), child!],
            ),
            child: Center(
              child: ClipRect(
                child: TransientAnimatedValue<_CapsuleContentVisual>(
                  value: (
                    width: widget.selected ? widget.itemWidth : 42,
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.selected
                          ? _CapsuleNavBarState._selectedHorizontalPadding *
                                widget.widthScale
                          : 0,
                    ),
                  ),
                  duration: _navAnimationDuration,
                  curve: Curves.easeOutCubic,
                  lerp: _lerpCapsuleContent,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.destination.icon,
                        size: _CapsuleNavBarState._iconSize,
                        color: foreground,
                      ),
                      Flexible(
                        child: TransientAnimatedValue<double>(
                          value: widget.selected ? 1 : 0,
                          duration: _navAnimationDuration,
                          curve: Curves.easeOutCubic,
                          lerp: _lerpDouble,
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
                              left:
                                  _CapsuleNavBarState._iconLabelGap *
                                  widget.widthScale,
                            ),
                            child: Text(
                              widget.destination.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: widget.labelStyle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  builder: (_, visual, child) => Container(
                    width: visual.width,
                    height: 42,
                    padding: visual.padding,
                    child: child,
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
      child: AppFocusHighlight(
        borderRadius: BorderRadius.circular(12),
        showShadow: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TransientAnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: TransientAnimatedValue<Color>(
                    value: fg,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    lerp: _lerpColor,
                    builder: (context, color, child) =>
                        Icon(icon, size: 22, color: color),
                  ),
                ),
                const SizedBox(height: 3),
                TransientAnimatedValue<TextStyle>(
                  value: Theme.of(context).textTheme.labelSmall!.copyWith(
                    fontSize: 10,
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  duration: const Duration(milliseconds: 180),
                  lerp: _lerpTextStyle,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  builder: (_, style, child) =>
                      DefaultTextStyle(style: style, child: child!),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Material3NavItem extends StatelessWidget {
  const _Material3NavItem({
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
    return AppFocusHighlight(
      borderRadius: BorderRadius.circular(12),
      showShadow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TransientAnimatedValue<_NavBoxVisual>(
                value: (
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
                ),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                lerp: _lerpNavBox,
                child: Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? _indicatorForeground(context, styleConfig, isDark)
                      : styleConfig.foreground(context),
                ),
                builder: (_, visual, child) => Container(
                  width: visual.width,
                  height: visual.height,
                  decoration: visual.decoration,
                  child: child,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  // The label sits on the navigation surface, not inside the
                  // selected indicator, so it must use the surface foreground.
                  color: styleConfig
                      .foreground(context)
                      .withValues(alpha: selected ? 1 : 0.72),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
