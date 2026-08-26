import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_color_utilities/hct/hct.dart';

import '../gamepad_navigation.dart';
import '../controller_view_state.dart';
import '../utils.dart';
import 'active_listenable_builder.dart';
import 'app_background.dart';
import 'pressable_scale.dart';
import 'proxy_avatar.dart';
import 'proxy_node_context_menu.dart';
import 'transient_animation.dart';
import 'transition_snapshot.dart';

const _gradientHueOffsets = <double>[
  -60,
  -52,
  -44,
  -36,
  -28,
  -20,
  -12,
  -4,
  4,
  12,
  20,
  28,
  36,
  44,
  52,
  60,
];
const _cardFlightEdge = 1 / 6;
const _cardFlightCurve = Interval(
  _cardFlightEdge,
  1 - _cardFlightEdge,
  curve: Curves.fastOutSlowIn,
);
const _cardFlightDepartureCurve = Interval(
  0,
  _cardFlightEdge,
  curve: Curves.easeInOutCubic,
);
const _cardFlightDetailCurve = Interval(
  _cardFlightEdge,
  1 - _cardFlightEdge,
  curve: Curves.easeInOutCubic,
);
// A non-zero opacity makes Impeller prepaint the route card before the source
// and route swap visibility on the following frame.
const _cardPrepaintOpacity = 0.001;

(int, bool, Hct, List<LinearGradient?>)? _gradientCache;

BoxDecoration _lerpBoxDecoration(
  BoxDecoration begin,
  BoxDecoration end,
  double progress,
) => BoxDecoration.lerp(begin, end, progress)!;

LinearGradient _themeGradient(
  Hct source,
  double offset, {
  required bool translucent,
}) {
  final hue = (source.hue + offset + 360) % 360;
  final chroma = source.chroma < 8
      ? source.chroma
      : source.chroma.clamp(24.0, 48.0).toDouble();
  final opacity = translucent ? 0.84 : 1.0;
  Color tone(double hueOffset, double chromaScale, double value) =>
      Color(Hct.from(hue + hueOffset, chroma * chromaScale, value).toInt())
          .withValues(alpha: opacity);

  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: translucent
        ? [tone(-8, 0.9, 34), tone(0, 1, 22), tone(10, 0.82, 10)]
        : [tone(-8, 0.9, 48), tone(0, 1, 33), tone(10, 0.82, 17)],
    stops: const [0, 0.46, 1],
  );
}

LinearGradient _gradientFor(
  Color primary,
  String name, {
  required bool translucent,
}) {
  var hash = 0;
  for (var i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.codeUnitAt(i)) & 0x7fffffff;
  }
  hash ^= hash >> 11;
  final key = primary.toARGB32();
  var cached = _gradientCache;
  if (cached == null || cached.$1 != key || cached.$2 != translucent) {
    cached = (
      key,
      translucent,
      Hct.fromInt(key),
      List<LinearGradient?>.filled(_gradientHueOffsets.length, null),
    );
    _gradientCache = cached;
  }
  final index = hash % _gradientHueOffsets.length;
  return cached.$4[index] ??= _themeGradient(
    cached.$3,
    _gradientHueOffsets[index],
    translucent: translucent,
  );
}

class _CardStyle {
  const _CardStyle({
    this.gradient,
    this.background,
    this.cardBorder,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tileBg,
    required this.tileSelectedBg,
    required this.tileBorder,
    required this.tileSelectedBorder,
    required this.tileTitle,
    required this.tileSubtitle,
    required this.pillUntested,
  });

  final Gradient? gradient;
  final Color? background;
  final Color? cardBorder;
  final Color title;
  final Color subtitle;
  final Color icon;
  final Color tileBg;
  final Color tileSelectedBg;
  final Color tileBorder;
  final Color tileSelectedBorder;
  final Color tileTitle;
  final Color tileSubtitle;
  final Color pillUntested;
}

_CardStyle _styleFor(BuildContext context, String name, bool colored) {
  final scheme = Theme.of(context).colorScheme;
  final surfaceTheme = AppSurfaceTheme.of(context);
  if (colored) {
    return _CardStyle(
      gradient: _gradientFor(
        scheme.primary,
        name,
        translucent: surfaceTheme.enabled,
      ),
      background: surfaceTheme.enabled
          ? surfaceTheme.surfaceColor(scheme.surfaceContainerHigh)
          : null,
      title: Colors.white,
      subtitle: Colors.white70,
      icon: Colors.white,
      tileBg: Colors.black.withValues(alpha: 0.22),
      tileSelectedBg: Colors.black.withValues(alpha: 0.35),
      tileBorder: Colors.white12,
      tileSelectedBorder: Colors.white,
      tileTitle: Colors.white,
      tileSubtitle: Colors.white60,
      pillUntested: Colors.white24,
    );
  }
  return _CardStyle(
    background: surfaceTheme.surfaceColor(scheme.surfaceContainerHigh),
    cardBorder: surfaceTheme.enabled
        ? null
        : scheme.outlineVariant.withValues(alpha: 0.5),
    title: scheme.onSurface,
    subtitle: scheme.onSurfaceVariant,
    icon: scheme.onSurfaceVariant,
    tileBg: surfaceTheme.surfaceColor(
      scheme.surfaceContainerHighest.withValues(alpha: 0.7),
      0.05,
    ),
    tileSelectedBg: surfaceTheme.surfaceColor(
      scheme.primaryContainer.withValues(alpha: 0.7),
      0.12,
    ),
    tileBorder: surfaceTheme.outlineColor(
      scheme.outlineVariant.withValues(alpha: 0.4),
    ),
    tileSelectedBorder: scheme.primary.withValues(alpha: 0.6),
    tileTitle: scheme.onSurface,
    tileSubtitle: scheme.onSurfaceVariant,
    pillUntested: scheme.outline,
  );
}

const _cardSurfaceBorderWidth = 1.0;

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.style,
    required this.radius,
    required this.child,
    this.groupBackdrop = false,
    this.localBackdrop = false,
    this.focused = false,
  });

  final _CardStyle style;
  final double radius;
  final Widget child;
  final bool groupBackdrop;
  final bool localBackdrop;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final focusColor = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.18),
      scheme.primary,
    );
    final card = Container(
      decoration: BoxDecoration(
        gradient: style.gradient,
        color: focused && style.gradient == null
            ? Color.alphaBlend(
                focusColor.withValues(alpha: 0.14),
                style.background ?? Colors.transparent,
              )
            : style.background,
        borderRadius: BorderRadius.circular(radius),
        border: focused
            ? Border.all(color: focusColor, width: 3)
            : style.cardBorder == null
            ? null
            : Border.all(
                color: style.cardBorder!,
                width: _cardSurfaceBorderWidth,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
    return AppSurfaceBackdrop(
      borderRadius: BorderRadius.circular(radius),
      grouped: groupBackdrop,
      local: localBackdrop,
      child: card,
    );
  }
}

typedef ProxyGroupCardTap = Future<void> Function(
  FocusNode sourceFocusNode,
  ValueChanged<bool> setFlightActive,
  double openingScale,
);

class ProxyGroupCard extends StatefulWidget {
  const ProxyGroupCard({
    super.key,
    required this.group,
    required this.showIcon,
    required this.colored,
    required this.showDelay,
    required this.onTap,
  });

  final ProxyGroup group;
  final bool showIcon;
  final bool colored;
  final bool showDelay;
  final ProxyGroupCardTap onTap;

  @override
  State<ProxyGroupCard> createState() => _ProxyGroupCardState();
}

class _ProxyGroupCardState extends State<ProxyGroupCard> {
  final _focusNode = FocusNode();
  bool _activationInProgress = false;
  bool _flightActive = false;
  bool _holdPress = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    directionalNavigationMode.addListener(_handleDirectionalModeChange);
    FocusManager.instance.addHighlightModeListener(_handleHighlightModeChange);
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  void _handleDirectionalModeChange() {
    if (mounted && _focusNode.hasFocus) setState(() {});
  }

  void _handleHighlightModeChange(FocusHighlightMode _) {
    if (mounted && _focusNode.hasFocus) setState(() {});
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(
      _handleHighlightModeChange,
    );
    directionalNavigationMode.removeListener(_handleDirectionalModeChange);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _activate({required bool fromPointer}) async {
    if (_activationInProgress) return;
    _activationInProgress = true;
    if (fromPointer) setState(() => _holdPress = true);
    try {
      _focusNode.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      await Future<void>.value();
      if (!mounted) return;
      await widget.onTap(
        _focusNode,
        _setFlightActive,
        fromPointer ? PressableScale.pressedScale : 1,
      );
    } finally {
      _activationInProgress = false;
      if (mounted) {
        if (_holdPress) setState(() => _holdPress = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focusNode.canRequestFocus) {
            _focusNode.requestFocus();
          }
        });
      }
    }
  }

  void _setFlightActive(bool active) {
    if (!mounted) return;
    final releasePress = active && _holdPress;
    if (_flightActive == active && !releasePress) return;
    setState(() {
      _flightActive = active;
      if (active) _holdPress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(context, widget.group.name, widget.colored);
    final showFocus =
        _focusNode.hasFocus &&
        isDirectionalNavigationActive &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return FocusableActionDetector(
      focusNode: _focusNode,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            unawaited(_activate(fromPointer: false));
            return null;
          },
        ),
      },
      child: RepaintBoundary(
        child: Opacity(
          opacity: _flightActive ? 0 : 1,
          child: PressableScale(
            holdPressed: _holdPress,
            child: _CardSurface(
              style: style,
              radius: 16,
              groupBackdrop: true,
              focused: showFocus,
              child: InkWell(
                canRequestFocus: false,
                onTap: () => unawaited(_activate(fromPointer: true)),
                child: _flightSourceContent(
                  widget.group,
                  widget.showIcon,
                  widget.showDelay,
                  style,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _subtitle(ProxyGroup group, String now) {
  final displayNow = group.hidesExactNow ? '*' : now;
  return displayNow.isEmpty ? group.type : '${group.type} · $displayNow';
}

Widget _collapsedChrome(
  ProxyGroup group,
  bool showIcon,
  bool showDelay,
  _CardStyle style,
) {
  if (showIcon && !showDelay) return const SizedBox.expand();
  return _compactCollapsedChrome(group, style, reserveIconSpace: showIcon);
}

Widget _flightSourceContent(
  ProxyGroup group,
  bool showIcon,
  bool showDelay,
  _CardStyle style,
) {
  return LayoutBuilder(
    builder: (_, constraints) {
      final sourceSize = constraints.biggest;
      return Stack(
        fit: StackFit.expand,
        children: [
          _collapsedChrome(group, showIcon, showDelay, style),
          _CardFlightIdentity(
            animation: kAlwaysDismissedAnimation,
            group: group,
            style: style,
            showIcon: showIcon,
            showDelay: showDelay,
            sourceSize: sourceSize,
            detailSize: sourceSize,
          ),
        ],
      );
    },
  );
}

Widget _compactCollapsedChrome(
  ProxyGroup group,
  _CardStyle style, {
  required bool reserveIconSpace,
}) {
  return ActiveValueListenableBuilder<String>(
    valueListenable: group.now,
    builder: (_, now, _) {
      final displayNow = group.hidesExactNow ? '*' : (now.isEmpty ? '-' : now);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 22),
                        const Spacer(),
                        Text(
                          group.type.toUpperCase(),
                          style: TextStyle(
                            color: style.subtitle,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (reserveIconSpace)
                        const SizedBox.square(dimension: 28)
                      else ...[
                        Text(
                          '${group.memberCount}',
                          style: TextStyle(
                            color: style.title,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '节点',
                          style: TextStyle(color: style.subtitle, fontSize: 8),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayNow,
                    style: TextStyle(
                      color: style.title,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!group.hidesExactNow && now.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _DelayPill(
                    delay: group.nowDelay,
                    untestedColor: style.pillUntested,
                    onTap: null,
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    },
  );
}

Widget _headerRow(bool showIcon, Widget trailing) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
    child: Row(
      children: [
        if (showIcon) ...[
          const SizedBox.square(dimension: 44),
          const SizedBox(width: 12),
        ],
        const Spacer(),
        trailing,
      ],
    ),
  );
}

Widget _groupDelayButton(
  _CardStyle style, {
  bool testing = false,
  VoidCallback? onPressed,
}) {
  return IconButton(
    tooltip: onPressed == null ? null : '组内延迟测试',
    onPressed: testing ? null : onPressed,
    icon: testing
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: style.icon),
          )
        : Icon(Icons.speed_rounded, color: style.icon),
  );
}

Widget _detailBody(
  ProxyGroup group,
  bool showIcon,
  _CardStyle style,
  Widget trailing, {
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onToggleFixed,
  Future<void> Function(String)? onTestNode,
  Future<String> Function(String)? loadNodeDetails,
  ValueChanged<int>? onMissingMember,
  ScrollController? scrollController,
  bool scrollable = true,
}) {
  final members = ActiveValueListenableBuilder<int>(
    valueListenable: group.membersVersion,
    builder: (_, _, _) => _memberGrid(
      group,
      style,
      onSelect: onSelect,
      onToggleFixed: onToggleFixed,
      onTestNode: onTestNode,
      loadNodeDetails: loadNodeDetails,
      onMissingMember: onMissingMember,
      scrollController: scrollController,
      scrollable: scrollable,
    ),
  );
  return Column(
    children: [
      _headerRow(showIcon, trailing),
      Expanded(child: members),
    ],
  );
}

Widget _memberGrid(
  ProxyGroup group,
  _CardStyle style, {
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onToggleFixed,
  Future<void> Function(String)? onTestNode,
  Future<String> Function(String)? loadNodeDetails,
  ValueChanged<int>? onMissingMember,
  ScrollController? scrollController,
  bool scrollable = true,
}) {
  if (group.memberCount == 0) {
    return Center(
      child: Text('暂无节点', style: TextStyle(color: style.subtitle)),
    );
  }
  final sections = group.memberSections;
  if (sections.isNotEmpty) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _memberGridColumns(constraints.maxWidth);
        final items = _groupedMemberItems(group, columns);
        return ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.zero,
          physics: scrollable ? null : const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemExtentBuilder: (index, _) => items[index].extent,
          itemBuilder: (context, index) => _groupedMemberItem(
            context,
            group,
            items[index],
            columns,
            style,
            onSelect: onSelect,
            onToggleFixed: onToggleFixed,
            onTestNode: onTestNode,
            loadNodeDetails: loadNodeDetails,
            onMissingMember: onMissingMember,
          ),
        );
      },
    );
  }
  return GridView.builder(
    controller: scrollController,
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    physics: scrollable ? null : const NeverScrollableScrollPhysics(),
    gridDelegate: _cardMemberGridDelegate,
    itemCount: group.memberCount,
    itemBuilder: (context, index) => _memberTile(
      context,
      group,
      index,
      style,
      onSelect: onSelect,
      onToggleFixed: onToggleFixed,
      onTestNode: onTestNode,
      loadNodeDetails: loadNodeDetails,
      onMissingMember: onMissingMember,
    ),
  );
}

const _cardMemberGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: _cardMemberMaxCrossAxisExtent,
  mainAxisSpacing: _cardMemberSpacing,
  crossAxisSpacing: _cardMemberSpacing,
  mainAxisExtent: _cardMemberExtent,
);

const _cardMemberMaxCrossAxisExtent = 260.0;
const _cardMemberExtent = 64.0;
const _cardMemberSpacing = 8.0;
const _cardDetailHeaderExtent = 68.0;

typedef _GroupedMemberItem = ({
  String? header,
  int offset,
  int count,
  double extent,
});

List<_GroupedMemberItem> _groupedMemberItems(ProxyGroup group, int columns) {
  final items = <_GroupedMemberItem>[];
  final sections = group.memberSections;
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final section = sections[sectionIndex];
    final range = _memberSectionRange(
      section.offset,
      section.count,
      group.memberCount,
    );
    if (range.count == 0) continue;
    items.add((
      header: section.provider,
      offset: 0,
      count: 0,
      extent: _memberSectionHeaderExtent(sectionIndex, section.provider),
    ));
    final rows = (range.count + columns - 1) ~/ columns;
    for (var row = 0; row < rows; row++) {
      final offset = range.offset + row * columns;
      final count = (range.count - row * columns).clamp(0, columns).toInt();
      items.add((
        header: null,
        offset: offset,
        count: count,
        extent: row + 1 == rows
            ? _cardMemberExtent
            : _cardMemberExtent + _cardMemberSpacing,
      ));
    }
  }
  items.add((header: '', offset: 0, count: 0, extent: 12));
  return items;
}

Widget _groupedMemberItem(
  BuildContext context,
  ProxyGroup group,
  _GroupedMemberItem item,
  int columns,
  _CardStyle style, {
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onToggleFixed,
  Future<void> Function(String)? onTestNode,
  Future<String> Function(String)? loadNodeDetails,
  ValueChanged<int>? onMissingMember,
}) {
  final header = item.header;
  if (header != null) {
    if (header.isEmpty) return SizedBox(height: item.extent);
    return SizedBox(
      height: item.extent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, item.extent > 32 ? 14 : 4, 12, 8),
        child: Text(
          header,
          style: TextStyle(
            color: style.title,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  return SizedBox(
    height: item.extent,
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: _cardMemberExtent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: _cardMemberSpacing),
                Expanded(
                  child: column < item.count
                      ? _memberTile(
                          context,
                          group,
                          item.offset + column,
                          style,
                          onSelect: onSelect,
                          onToggleFixed: onToggleFixed,
                          onTestNode: onTestNode,
                          loadNodeDetails: loadNodeDetails,
                          onMissingMember: onMissingMember,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

({int offset, int count}) _memberSectionRange(
  int offset,
  int count,
  int memberCount,
) {
  final clampedOffset = offset.clamp(0, memberCount).toInt();
  return (
    offset: clampedOffset,
    count: count.clamp(0, memberCount - clampedOffset).toInt(),
  );
}

double _memberSectionHeaderExtent(int index, String provider) {
  if (provider.isEmpty) return index == 0 ? 4 : 14;
  return index == 0 ? 32 : 42;
}

double _memberTopOffset(ProxyGroup group, int memberIndex, int columns) {
  final sections = group.memberSections;
  if (sections.isEmpty) {
    return 4 +
        (memberIndex ~/ columns) * (_cardMemberExtent + _cardMemberSpacing);
  }

  var offset = 0.0;
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final section = sections[sectionIndex];
    final range = _memberSectionRange(
      section.offset,
      section.count,
      group.memberCount,
    );
    if (range.count == 0) continue;
    offset += _memberSectionHeaderExtent(sectionIndex, section.provider);
    if (memberIndex >= range.offset &&
        memberIndex < range.offset + range.count) {
      return offset +
          ((memberIndex - range.offset) ~/ columns) *
              (_cardMemberExtent + _cardMemberSpacing);
    }
    offset += _memberGridExtent(range.count, columns);
  }
  return 0;
}

double _memberGridExtent(int count, int columns) {
  final rows = (count + columns - 1) ~/ columns;
  if (rows == 0) return 0;
  return rows * _cardMemberExtent + (rows - 1) * _cardMemberSpacing;
}

double _memberContentExtent(ProxyGroup group, int columns) {
  final sections = group.memberSections;
  if (sections.isEmpty) {
    return 16 + _memberGridExtent(group.memberCount, columns);
  }

  var extent = 12.0;
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final section = sections[sectionIndex];
    final range = _memberSectionRange(
      section.offset,
      section.count,
      group.memberCount,
    );
    if (range.count == 0) continue;
    extent += _memberSectionHeaderExtent(sectionIndex, section.provider);
    extent += _memberGridExtent(range.count, columns);
  }
  return extent;
}

int _memberGridColumns(double detailWidth) {
  final gridWidth = (detailWidth - 24).clamp(0.0, double.infinity);
  return (gridWidth / (_cardMemberMaxCrossAxisExtent + _cardMemberSpacing))
      .ceil()
      .clamp(1, 4)
      .toInt();
}

Widget _memberTile(
  BuildContext context,
  ProxyGroup group,
  int index,
  _CardStyle style, {
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onToggleFixed,
  Future<void> Function(String)? onTestNode,
  Future<String> Function(String)? loadNodeDetails,
  ValueChanged<int>? onMissingMember,
}) {
  final member = group.memberAt(index);
  if (member == null) {
    if (!isUiFastScrolling(context)) onMissingMember?.call(index);
    return _CardNodePlaceholder(style: style);
  }
  return _CardNodeTile(
    key: ValueKey('${group.name}::${member.name}'),
    group: group,
    member: member,
    style: style,
    loadDetails: loadNodeDetails == null
        ? null
        : () => loadNodeDetails(member.name),
    onSelect: onSelect == null ? null : () => onSelect(member.name),
    onToggleFixed: onToggleFixed == null
        ? null
        : () => onToggleFixed(member.name),
    onTestDelay: onTestNode == null ? null : () => onTestNode(member.name),
  );
}

class _CardNodePlaceholder extends StatelessWidget {
  const _CardNodePlaceholder({required this.style});

  final _CardStyle style;

  @override
  Widget build(BuildContext context) {
    final mark = style.tileSubtitle.withValues(alpha: 0.2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.tileBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.tileBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.56,
                    child: _CardPlaceholderMark(height: 8, color: mark),
                  ),
                  const SizedBox(height: 7),
                  FractionallySizedBox(
                    widthFactor: 0.3,
                    child: _CardPlaceholderMark(height: 6, color: mark),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _CardPlaceholderMark(width: 30, height: 8, color: mark),
          ],
        ),
      ),
    );
  }
}

class _CardPlaceholderMark extends StatelessWidget {
  const _CardPlaceholderMark({
    this.width,
    required this.height,
    required this.color,
  });

  final double? width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    ),
  );
}

class _ProxyGroupCardDetailRoute extends PageRouteBuilder<void>
    implements FocusRestorationRoute {
  _ProxyGroupCardDetailRoute({
    required this.sourceFocusNode,
    required this.onPopStarted,
    required super.pageBuilder,
  }) : super(
         opaque: false,
         allowSnapshotting: false,
         barrierDismissible: true,
         barrierLabel: '关闭',
         barrierColor: Colors.black.withValues(alpha: 0.45),
         transitionDuration: const Duration(milliseconds: 450),
         reverseTransitionDuration: const Duration(milliseconds: 360),
       );

  @override
  final FocusNode? sourceFocusNode;
  final VoidCallback onPopStarted;

  bool _closing = false;
  bool _removalScheduled = false;
  bool _removing = false;
  bool _disposed = false;

  @override
  Curve get barrierCurve => _cardFlightDepartureCurve;

  void _beginClosing() {
    if (_closing || _removing || _disposed) return;
    final animationController = controller;
    if (animationController == null) return;
    _closing = true;
    onPopStarted();
    animationController.reverse();
  }

  bool reopen() {
    if (!_closing || _removing || _disposed) return false;
    final animationController = controller;
    if (animationController == null) return false;
    _closing = false;
    _armDismissal();
    animationController.forward();
    return true;
  }

  void _armDismissal() {
    addLocalHistoryEntry(
      LocalHistoryEntry(impliesAppBarDismissal: false, onRemove: _beginClosing),
    );
  }

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_handleStatus);
    _armDismissal();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !_closing || _removalScheduled) {
      return;
    }
    _removalScheduled = true;
    scheduleMicrotask(() {
      _removalScheduled = false;
      if (!_closing ||
          !isActive ||
          animation?.status != AnimationStatus.dismissed) {
        return;
      }
      _removing = true;
      navigator?.removeRoute(this);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    animation?.removeStatusListener(_handleStatus);
    super.dispose();
  }
}

Future<void> showProxyGroupCardDetail(
  BuildContext context, {
  required ControllerViewState session,
  required ProxyGroup group,
  required bool showIcon,
  required bool colored,
  required bool showDelay,
  required bool autoLocate,
  required Future<void> Function() onTestGroup,
  required ValueChanged<String> onSelect,
  required ValueChanged<String> onToggleFixed,
  required Future<void> Function(String) onTestNode,
  required Future<String> Function(String) loadNodeDetails,
  required FocusNode sourceFocusNode,
  required ValueChanged<bool> setFlightActive,
  required double openingScale,
}) async {
  final navigator = Navigator.of(context);
  final sourceRect = _boundsInOverlay(sourceFocusNode, navigator);
  OverlayEntry? inputGuard;

  void removeInputGuard() {
    inputGuard?.remove();
    inputGuard?.dispose();
    inputGuard = null;
  }

  late final _ProxyGroupCardDetailRoute route;
  void guardReturningFlight() {
    if (inputGuard != null) return;
    final overlay = navigator.overlay;
    if (overlay == null) return;
    inputGuard = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (!_sourceContains(sourceFocusNode, event.position)) return;
            if (!route.reopen()) {
              removeInputGuard();
              setFlightActive(false);
              return;
            }
            removeInputGuard();
            setFlightActive(true);
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    overlay.insert(inputGuard!);
  }

  route = _ProxyGroupCardDetailRoute(
    sourceFocusNode: sourceFocusNode,
    onPopStarted: guardReturningFlight,
    pageBuilder: (_, _, _) => _ProxyGroupCardDetail(
      session: session,
      group: group,
      showIcon: showIcon,
      colored: colored,
      showDelay: showDelay,
      autoLocate: autoLocate,
      onTestGroup: onTestGroup,
      onSelect: onSelect,
      onToggleFixed: onToggleFixed,
      onTestNode: onTestNode,
      loadNodeDetails: loadNodeDetails,
      flightTimeline: route.animation ?? kAlwaysDismissedAnimation,
      sourceRect: sourceRect,
      openingScale: openingScale,
      onFlightReady: () => setFlightActive(true),
    ),
  );
  final popped = navigator.push(route);
  final animation = route.animation;
  void handleRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) setFlightActive(false);
  }

  animation?.addStatusListener(handleRouteStatus);
  try {
    await popped;
    await route.completed;
  } finally {
    animation?.removeStatusListener(handleRouteStatus);
    removeInputGuard();
    setFlightActive(false);
    session.proxies.releaseGroupMembers(group.name);
  }
  final sourceContext = sourceFocusNode.context;
  if (sourceContext != null &&
      sourceContext.mounted &&
      sourceFocusNode.canRequestFocus) {
    sourceFocusNode.requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }
}

bool _sourceContains(FocusNode source, Offset position) {
  return _globalBounds(source.context)?.contains(position) ?? false;
}

Rect? _globalBounds(BuildContext? context) {
  final renderObject = context?.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.attached ||
      !renderObject.hasSize) {
    return null;
  }
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

Rect _boundsInOverlay(FocusNode source, NavigatorState navigator) {
  final sourceBox = source.context?.findRenderObject();
  final overlayBox = navigator.overlay?.context.findRenderObject();
  if (sourceBox is RenderBox &&
      overlayBox is RenderBox &&
      sourceBox.attached &&
      sourceBox.hasSize) {
    return MatrixUtils.transformRect(
      sourceBox.getTransformTo(overlayBox),
      Offset.zero & sourceBox.size,
    );
  }
  return _globalBounds(source.context) ?? const Rect.fromLTWH(0, 0, 180, 96);
}

class _ProxyGroupCardDetail extends StatefulWidget {
  const _ProxyGroupCardDetail({
    required this.session,
    required this.group,
    required this.showIcon,
    required this.colored,
    required this.showDelay,
    required this.autoLocate,
    required this.onTestGroup,
    required this.onSelect,
    required this.onToggleFixed,
    required this.onTestNode,
    required this.loadNodeDetails,
    required this.flightTimeline,
    required this.sourceRect,
    required this.openingScale,
    required this.onFlightReady,
  });

  final ControllerViewState session;
  final ProxyGroup group;
  final bool showIcon;
  final bool colored;
  final bool showDelay;
  final bool autoLocate;
  final Future<void> Function() onTestGroup;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggleFixed;
  final Future<void> Function(String) onTestNode;
  final Future<String> Function(String) loadNodeDetails;
  final Animation<double> flightTimeline;
  final Rect sourceRect;
  final double openingScale;
  final VoidCallback onFlightReady;

  @override
  State<_ProxyGroupCardDetail> createState() => _ProxyGroupCardDetailState();
}

class _CardFlightIdentity extends StatelessWidget {
  const _CardFlightIdentity({
    required this.animation,
    required this.group,
    required this.style,
    required this.showIcon,
    required this.showDelay,
    required this.sourceSize,
    required this.detailSize,
  });

  final Animation<double> animation;
  final ProxyGroup group;
  final _CardStyle style;
  final bool showIcon;
  final bool showDelay;
  final Size sourceSize;
  final Size detailSize;

  static double _lerp(double begin, double end, double progress) =>
      begin + (end - begin) * progress;

  @override
  Widget build(BuildContext context) {
    final iconLayout = showIcon && !showDelay;
    final sourceTitleWidth =
        (sourceSize.width -
                (iconLayout
                    ? 20
                    : showIcon
                    ? 58
                    : 54))
            .clamp(0.0, double.infinity);
    final sourceSubtitleWidth = (sourceSize.width - 24).clamp(
      0.0,
      double.infinity,
    );
    final detailTextLeft = showIcon ? 70.0 : 14.0;
    final detailTextWidth = (detailSize.width - detailTextLeft - 56).clamp(
      0.0,
      double.infinity,
    );
    final sourceAvatar = iconLayout
        ? const Rect.fromLTWH(10, 10, 32, 32)
        : Rect.fromLTWH(sourceSize.width - 38, 10, 28, 28);
    final sourceTitle = Rect.fromLTWH(
      iconLayout ? 10 : 12,
      iconLayout ? sourceSize.height - 41 : 10,
      sourceTitleWidth,
      22,
    );
    final sourceSubtitle = Rect.fromLTWH(
      iconLayout ? 10 : 12,
      sourceSize.height - 23,
      sourceSubtitleWidth,
      16,
    );
    final detailAvatar = const Rect.fromLTWH(14, 14, 44, 44);
    final detailTitle = Rect.fromLTWH(detailTextLeft, 18, detailTextWidth, 22);
    final detailSubtitle = Rect.fromLTWH(
      detailTextLeft,
      40,
      detailTextWidth,
      16,
    );

    return ActiveValueListenableBuilder<String>(
      valueListenable: group.now,
      builder: (_, now, _) => AnimatedBuilder(
        animation: animation,
        builder: (_, _) {
          final timeline = animation.value.clamp(0.0, 1.0);
          final motion = _cardFlightCurve.transform(timeline);

          Widget movingText(
            String text,
            double sourceFontSize,
            double detailFontSize,
            FontWeight? weight,
          ) {
            return Text(
              text,
              style: TextStyle(
                color: weight == null ? style.subtitle : style.title,
                fontSize: _lerp(sourceFontSize, detailFontSize, motion),
                fontWeight: weight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              if (showIcon)
                Positioned.fromRect(
                  rect: Rect.lerp(sourceAvatar, detailAvatar, motion)!,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox.square(
                      dimension: 44,
                      child: ProxyAvatar(name: group.name, icon: group.icon),
                    ),
                  ),
                ),
              Positioned.fromRect(
                rect: Rect.lerp(sourceTitle, detailTitle, motion)!,
                child: movingText(
                  group.name,
                  iconLayout ? 15 : 18,
                  18,
                  FontWeight.w700,
                ),
              ),
              if (iconLayout || motion > 0)
                Positioned.fromRect(
                  rect: Rect.lerp(sourceSubtitle, detailSubtitle, motion)!,
                  child: Opacity(
                    opacity: iconLayout ? 1 : motion,
                    child: movingText(
                      _subtitle(group, now),
                      iconLayout ? 11 : 12,
                      12,
                      null,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProxyGroupCardDetailState extends State<_ProxyGroupCardDetail> {
  ScrollController? _memberScroll;
  bool _testing = false;
  bool _initialOpening = true;
  bool _handoffComplete = false;
  int _pendingFirst = -1;
  int _pendingLast = -1;
  bool _loadScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.session.proxies.addListener(_guard);
    widget.flightTimeline.addStatusListener(_handleFlightStatus);
    WidgetsBinding.instance.addPostFrameCallback(_completeFlightHandoff);
  }

  void _completeFlightHandoff(Duration _) {
    if (!mounted || _handoffComplete) return;
    final status = widget.flightTimeline.status;
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      return;
    }
    setState(() => _handoffComplete = true);
    widget.onFlightReady();
  }

  void _handleFlightStatus(AnimationStatus status) {
    if (!_initialOpening ||
        (status != AnimationStatus.reverse &&
            status != AnimationStatus.completed)) {
      return;
    }
    if (mounted) setState(() => _initialOpening = false);
  }

  @override
  void dispose() {
    widget.flightTimeline.removeStatusListener(_handleFlightStatus);
    widget.session.proxies.removeListener(_guard);
    _memberScroll?.dispose();
    super.dispose();
  }

  ScrollController _memberScrollController(int columns, double detailHeight) {
    final existing = _memberScroll;
    if (existing != null) return existing;

    final group = widget.group;
    if (!widget.autoLocate || group.hidesExactNow || group.now.value.isEmpty) {
      return _memberScroll = ScrollController();
    }
    final memberIndex = group.locatedMemberIndex;
    if (memberIndex == null || memberIndex < 0) {
      return _memberScroll = ScrollController();
    }
    final viewportHeight = (detailHeight - _cardDetailHeaderExtent).clamp(
      0.0,
      double.infinity,
    );
    final memberTop = _memberTopOffset(group, memberIndex, columns);
    final initialOffset =
        memberTop + _cardMemberExtent / 2 - viewportHeight / 2;
    final maxOffset = (_memberContentExtent(group, columns) - viewportHeight)
        .clamp(0.0, double.infinity);
    return _memberScroll = ScrollController(
      initialScrollOffset: initialOffset.clamp(0.0, maxOffset).toDouble(),
    );
  }

  // The catalog can drop (and dispose) this group on refresh; keeping the
  // route open would leave it listening to dead notifiers.
  void _guard() {
    if (widget.session.proxies.groups.contains(widget.group)) return;
    if (mounted) Navigator.of(context).pop();
  }

  void _queueMemberLoad(int index) {
    if (_pendingFirst < 0) {
      _pendingFirst = index;
      _pendingLast = index;
    } else {
      if (index < _pendingFirst) _pendingFirst = index;
      if (index > _pendingLast) _pendingLast = index;
    }
    if (_loadScheduled) return;
    _loadScheduled = true;
    scheduleMicrotask(() {
      _loadScheduled = false;
      if (!mounted) return;
      final first = _pendingFirst;
      final last = _pendingLast;
      _pendingFirst = -1;
      _pendingLast = -1;
      if (first < 0) return;
      unawaited(
        widget.session.ensureProxyGroupMembers(widget.group.name, first, last),
      );
    });
  }

  Future<void> _runTest() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      await widget.onTestGroup();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final style = _styleFor(context, group.name, widget.colored);
    final safePadding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableRect = Rect.fromLTRB(
          safePadding.left + 16,
          safePadding.top + 16,
          constraints.maxWidth - safePadding.right - 16,
          constraints.maxHeight - safePadding.bottom - 16,
        );
        final width = availableRect.width.clamp(0.0, 480.0);
        final cols = _memberGridColumns(width);
        final maxHeight = availableRect.height.clamp(0.0, 520.0);
        final contentHeight = group.memberCount == 0
            ? 148.0
            : _cardDetailHeaderExtent + _memberContentExtent(group, cols);
        final height = contentHeight.clamp(0.0, maxHeight);
        final detailSize = Size(width, height);
        final targetRect = Alignment.center.inscribe(detailSize, availableRect);
        final memberScroll = _memberScrollController(cols, height);

        final collapsedLayer = RepaintBoundary(
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: widget.sourceRect.size,
              child: _collapsedChrome(
                group,
                widget.showIcon,
                widget.showDelay,
                style,
              ),
            ),
          ),
        );
        final detailLayer = RepaintBoundary(
          child: HighRefreshTransitionSnapshot(
            animation: widget.flightTimeline,
            child: _detailBody(
              group,
              widget.showIcon,
              style,
              _groupDelayButton(style, testing: _testing, onPressed: _runTest),
              onSelect: widget.onSelect,
              onToggleFixed: widget.onToggleFixed,
              onTestNode: widget.onTestNode,
              loadNodeDetails: widget.loadNodeDetails,
              onMissingMember: _queueMemberLoad,
              scrollController: memberScroll,
            ),
          ),
        );
        final cardContent = AnimatedBuilder(
          animation: widget.flightTimeline,
          child: detailLayer,
          builder: (_, detailLayer) {
            final progress = widget.flightTimeline.value.clamp(0.0, 1.0);
            final departure = _cardFlightDepartureCurve.transform(progress);
            final detail = _cardFlightDetailCurve.transform(progress);
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: 1 - departure, child: collapsedLayer),
                Opacity(opacity: detail, child: detailLayer),
              ],
            );
          },
        );
        final card = _CardSurface(
          style: style,
          radius: 16,
          localBackdrop: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(size: detailSize, child: cardContent),
              ),
              _CardFlightIdentity(
                animation: widget.flightTimeline,
                group: group,
                style: style,
                showIcon: widget.showIcon,
                showDelay: widget.showDelay,
                sourceSize: widget.sourceRect.size,
                detailSize: detailSize,
              ),
            ],
          ),
        );
        return AnimatedBuilder(
          animation: widget.flightTimeline,
          child: card,
          builder: (_, card) {
            final timeline = widget.flightTimeline.value.clamp(0.0, 1.0);
            final motion = _cardFlightCurve.transform(timeline);
            final departure = _cardFlightDepartureCurve.transform(timeline);
            final openingScale = _initialOpening
                ? widget.openingScale + (1 - widget.openingScale) * departure
                : 1.0;
            final rect = Rect.lerp(widget.sourceRect, targetRect, motion)!;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: _handoffComplete ? 1 : _cardPrepaintOpacity,
                    child: Transform.scale(
                      scale: openingScale,
                      child: IgnorePointer(ignoring: timeline < 1, child: card),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CardNodeTile extends StatelessWidget {
  const _CardNodeTile({
    super.key,
    required this.group,
    required this.member,
    required this.style,
    required this.loadDetails,
    required this.onSelect,
    required this.onToggleFixed,
    required this.onTestDelay,
  });

  final ProxyGroup group;
  final ProxyMember member;
  final _CardStyle style;
  final Future<String> Function()? loadDetails;
  final VoidCallback? onSelect;
  final VoidCallback? onToggleFixed;
  final Future<void> Function()? onTestDelay;

  @override
  Widget build(BuildContext context) {
    return ProxyNodeContextMenu(
      group: group,
      member: member,
      loadDetails: loadDetails,
      onTestDelay: onTestDelay,
      onToggleFixed: onToggleFixed,
      onActivate: group.canSelectOnTap ? onSelect : null,
      requireFullyVisible: true,
      child: ActiveValueListenableSelector<String, bool>(
        valueListenable: group.now,
        selector: (now) => !group.hidesExactNow && now == member.name,
        builder: (_, selected, _) {
          return ActiveValueListenableSelector<String, bool>(
            valueListenable: group.fixed,
            selector: (fixed) => group.canFixMembers && fixed == member.name,
            builder: (_, pinned, _) {
              const pinnedColor = Color(0xfff97316);
              final titleColor = pinned ? Colors.white : style.tileTitle;
              final subtitleColor = pinned
                  ? Colors.white70
                  : style.tileSubtitle;
              final decoration = BoxDecoration(
                color: pinned
                    ? pinnedColor
                    : selected
                    ? style.tileSelectedBg
                    : style.tileBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: pinned
                      ? pinnedColor
                      : selected
                      ? style.tileSelectedBorder
                      : style.tileBorder,
                  width: selected || pinned ? 1.6 : 1,
                ),
              );
              return TransientAnimatedValue<BoxDecoration>(
                value: decoration,
                duration: const Duration(milliseconds: 150),
                lerp: _lerpBoxDecoration,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    canRequestFocus: false,
                    onTap: group.canSelectOnTap ? onSelect : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (pinned) ...[
                                const Icon(
                                  Icons.push_pin,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  member.name,
                                  style: TextStyle(
                                    color: titleColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  member.type,
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _DelayPill(
                                delay: member.delay,
                                untestedColor: style.pillUntested,
                                onTap: onTestDelay == null
                                    ? null
                                    : () => unawaited(onTestDelay!()),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                builder: (_, decoration, child) =>
                    Container(decoration: decoration, child: child),
              );
            },
          );
        },
      ),
    );
  }
}

class _DelayPill extends StatelessWidget {
  const _DelayPill({
    required this.delay,
    required this.untestedColor,
    required this.onTap,
  });

  final ValueNotifier<int> delay;
  final Color untestedColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActiveValueListenableBuilder<int>(
      valueListenable: delay,
      pauseWhileScrolling: true,
      builder: (_, ms, _) {
        final color = switch (classifyDelay(ms)) {
          DelayBucket.untested => untestedColor,
          DelayBucket.timeout => const Color(0xffef4444),
          DelayBucket.fast => const Color(0xff22c55e),
          DelayBucket.slow => const Color(0xfff59e0b),
        };
        final radius = BorderRadius.circular(999);
        return AppFocusHighlight(
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color, borderRadius: radius),
              child: Text(
                delayLabel(ms),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
