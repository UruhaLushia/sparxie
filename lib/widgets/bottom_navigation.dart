import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_prefs.dart';

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
    final leftInset = MediaQuery.paddingOf(context).left;
    return Container(
      width: 84 + leftInset,
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
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppNavDestination> destinations;
  final NavBarStyle style;

  static const double _height = 64;
  static const double _horizontalInset = 24;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalInset,
        0,
        _horizontalInset,
        6 + bottomPadding,
      ),
      child: Center(
        heightFactor: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_height / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? scheme.surfaceContainerHigh.withValues(alpha: 0.68)
                    : scheme.surfaceContainer.withValues(alpha: 0.74),
                borderRadius: BorderRadius.circular(_height / 2),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  height: _height,
                  child: BottomNavBarItems(
                    style: style,
                    destinations: destinations,
                    selectedIndex: selectedIndex,
                    onSelected: onSelected,
                    shrinkWrap: true,
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

Color _indicatorColor(ColorScheme scheme, bool isDark) =>
    scheme.primaryContainer.withValues(alpha: isDark ? 0.6 : 0.9);

class BottomNavBarItems extends StatelessWidget {
  const BottomNavBarItems({
    super.key,
    required this.style,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.shrinkWrap = false,
  });

  final NavBarStyle style;
  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool shrinkWrap;

  static const double _cellWidth = 68;

  Widget _cell(Widget child) => shrinkWrap
      ? SizedBox(width: _cellWidth, child: child)
      : Expanded(child: child);

  Widget _labeledItem(int index, ColorScheme scheme, Color selectedColor) {
    return _LabeledNavItem(
      icon: destinations[index].icon,
      label: destinations[index].label,
      selected: index == selectedIndex,
      onTap: () => onSelected(index),
      selectedColor: selectedColor,
      unselectedColor: scheme.onSurfaceVariant,
    );
  }

  Widget _labeledRow(
    ColorScheme scheme,
    Color selectedColor, {
    bool fill = false,
  }) {
    return Row(
      mainAxisSize: fill || !shrinkWrap ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (var i = 0; i < destinations.length; i++)
          fill
              ? Expanded(child: _labeledItem(i, scheme, selectedColor))
              : _cell(_labeledItem(i, scheme, selectedColor)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return switch (style) {
      NavBarStyle.capsule => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          spacing: shrinkWrap ? 2 : 0,
          children: [
            for (var i = 0; i < destinations.length; i++)
              _CapsuleNavItem(
                icon: destinations[i].icon,
                label: destinations[i].label,
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
                scheme: scheme,
                isDark: isDark,
              ),
          ],
        ),
      ),
      NavBarStyle.pill => _PillNavBar(
        destinationCount: destinations.length,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        child: _labeledRow(scheme, scheme.onPrimaryContainer, fill: true),
      ),
      NavBarStyle.tint => _labeledRow(scheme, scheme.primary),
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
                scheme: scheme,
                isDark: isDark,
              ),
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
    required this.child,
  });

  final int destinationCount;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  State<_PillNavBar> createState() => _PillNavBarState();
}

class _PillNavBarState extends State<_PillNavBar> {
  static const double _indicatorInset = 3;
  static const double _indicatorExtraWidth = 12;
  static const double _contentInset = _indicatorExtraWidth / 2;
  static const double _indicatorHeight = 58;

  int? _dragIndex;
  double? _dragCenter;

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
    return (cellWidth + _indicatorExtraWidth).clamp(0, width).toDouble();
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
    setState(() {
      _dragIndex = null;
      _dragCenter = null;
    });
  }

  Widget _indicator(ColorScheme scheme, bool isDark, double width) {
    return SizedBox(
      width: width,
      height: _indicatorHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _indicatorInset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _indicatorColor(scheme, isDark),
            borderRadius: BorderRadius.circular(999),
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
            : BottomNavBarItems._cellWidth * widget.destinationCount +
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (details) =>
              _startDrag(details.localPosition, width),
          onHorizontalDragUpdate: (details) =>
              _updateDrag(details.localPosition, width),
          onHorizontalDragEnd: (_) => _finishDrag(),
          onHorizontalDragCancel: _resetDrag,
          child: SizedBox(
            width: width,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _dragCenter == null
                    ? AnimatedAlign(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment(indicatorAlignment, 0),
                        child: _indicator(scheme, isDark, indicatorWidth),
                      )
                    : Align(
                        alignment: Alignment(indicatorAlignment, 0),
                        child: _indicator(scheme, isDark, indicatorWidth),
                      ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _contentInset,
                  ),
                  child: widget.child,
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
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 14 : 10,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: selected
                ? _indicatorColor(scheme, isDark)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: fg),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
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
    return GestureDetector(
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
              child: Icon(icon, size: 22, color: fg),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                fontSize: 10,
                color: fg,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
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
    required this.scheme,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final bool isDark;

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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? _indicatorColor(scheme, isDark)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
