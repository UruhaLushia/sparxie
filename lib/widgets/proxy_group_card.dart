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
  Color tone(double hueOffset, double chromaScale, double value) => Color(
    Hct.from(hue + hueOffset, chroma * chromaScale, value).toInt(),
  ).withValues(alpha: opacity);

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

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.style,
    required this.radius,
    required this.child,
    this.groupBackdrop = false,
    this.focused = false,
  });

  final _CardStyle style;
  final double radius;
  final Widget child;
  final bool groupBackdrop;
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
            : Border.all(color: style.cardBorder!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
    return AppSurfaceBackdrop(
      borderRadius: BorderRadius.circular(radius),
      grouped: groupBackdrop,
      child: card,
    );
  }
}

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
  final Future<void> Function(FocusNode sourceFocusNode) onTap;

  @override
  State<ProxyGroupCard> createState() => _ProxyGroupCardState();
}

class _ProxyGroupCardState extends State<ProxyGroupCard> {
  final _focusNode = FocusNode();

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

  Future<void> _activate() async {
    _focusNode.requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    await Future<void>.value();
    if (!mounted) return;
    try {
      await widget.onTap(_focusNode);
    } finally {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focusNode.canRequestFocus) {
            _focusNode.requestFocus();
          }
        });
      }
    }
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
            unawaited(_activate());
            return null;
          },
        ),
      },
      child: PressableScale(
        child: RepaintBoundary(
          child: Hero(
            tag: 'proxy-group-card-${widget.group.name}',
            child: _CardSurface(
              style: style,
              radius: 16,
              groupBackdrop: true,
              focused: showFocus,
              child: InkWell(
                canRequestFocus: false,
                onTap: () => unawaited(_activate()),
                child: _collapsedContent(
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

Widget _collapsedContent(
  ProxyGroup group,
  bool showIcon,
  bool showDelay,
  _CardStyle style,
) {
  if (!showIcon) return _compactCollapsedContent(group, style);
  if (!showDelay) return _iconCollapsedContent(group, style);
  return _compactCollapsedContent(group, style, showIcon: true);
}

Widget _iconCollapsedContent(ProxyGroup group, _CardStyle style) {
  return Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProxyAvatar(name: group.name, icon: group.icon, size: 32),
        const Spacer(),
        ActiveValueListenableBuilder<String>(
          valueListenable: group.now,
          builder: (_, now, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.name,
                style: TextStyle(
                  color: style.title,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _subtitle(group, now),
                style: TextStyle(color: style.subtitle, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _compactCollapsedContent(
  ProxyGroup group,
  _CardStyle style, {
  bool showIcon = false,
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
                        Text(
                          group.name,
                          style: TextStyle(
                            color: style.title,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                      if (showIcon)
                        ProxyAvatar(
                          name: group.name,
                          icon: group.icon,
                          size: 28,
                        )
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

Widget _headerRow(
  ProxyGroup group,
  bool showIcon,
  _CardStyle style,
  Widget trailing,
) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
    child: Row(
      children: [
        if (showIcon) ...[
          ProxyAvatar(name: group.name, icon: group.icon),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: ActiveValueListenableBuilder<String>(
            valueListenable: group.now,
            builder: (_, now, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.name,
                  style: TextStyle(
                    color: style.title,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _subtitle(group, now),
                  style: TextStyle(color: style.subtitle, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        trailing,
      ],
    ),
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
  return Column(
    children: [
      _headerRow(group, showIcon, style, trailing),
      Expanded(
        child: ActiveValueListenableBuilder<int>(
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
        ),
      ),
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
    required super.pageBuilder,
  }) : super(
         opaque: false,
         allowSnapshotting: false,
         barrierDismissible: true,
         barrierLabel: '关闭',
         barrierColor: Colors.black.withValues(alpha: 0.45),
         transitionDuration: const Duration(milliseconds: 300),
         reverseTransitionDuration: const Duration(milliseconds: 240),
       );

  @override
  final FocusNode? sourceFocusNode;
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
}) async {
  final navigator = Navigator.of(context);
  final route = _ProxyGroupCardDetailRoute(
    sourceFocusNode: sourceFocusNode,
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
    ),
  );
  final popped = navigator.push(route);
  await popped;
  final sourceContext = sourceFocusNode.context;
  if (sourceContext != null &&
      sourceContext.mounted &&
      sourceFocusNode.canRequestFocus) {
    sourceFocusNode.requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }
  await route.completed;
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

  @override
  State<_ProxyGroupCardDetail> createState() => _ProxyGroupCardDetailState();
}

class _ProxyGroupCardDetailState extends State<_ProxyGroupCardDetail> {
  ScrollController? _memberScroll;
  bool _testing = false;
  Size _detailSize = Size.zero;

  // Flying the real detail card would relayout its member grid every frame;
  // the shuttle lays the detail content out once at its final size (recorded
  // by build below — reading context.size during a build is forbidden) and
  // scales that raster to the flying rect, so nodes ride along smoothly.
  Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final group = widget.group;
    final style = _styleFor(flightContext, group.name, widget.colored);
    final detailSize = _detailSize;
    final memberScroll = _memberScroll;
    final memberOffset = memberScroll == null
        ? 0.0
        : memberScroll.hasClients
        ? memberScroll.offset
        : memberScroll.initialScrollOffset;
    Widget detailLayer = const SizedBox.shrink();
    if (detailSize.width > 0) {
      // FittedBox scales at paint time so the grid lays out once at its final
      // size; the snapshot turns it into a single texture — without it the
      // whole grid re-rasterizes every frame because the scale keeps changing.
      detailLayer = FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topLeft,
        clipBehavior: Clip.none,
        child: SizedBox.fromSize(
          size: detailSize,
          child: _FlightSnapshot(
            initialScrollOffset: memberOffset,
            builder: (scrollController) => _detailBody(
              group,
              widget.showIcon,
              style,
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.speed_rounded, color: style.icon),
              ),
              scrollController: scrollController,
              scrollable: false,
            ),
          ),
        ),
      );
    }
    return _CardSurface(
      style: style,
      radius: 16,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: ReverseAnimation(animation),
              child: _collapsedContent(
                group,
                widget.showIcon,
                widget.showDelay,
                style,
              ),
            ),
          ),
          Positioned.fill(
            child: FadeTransition(opacity: animation, child: detailLayer),
          ),
        ],
      ),
    );
  }

  int _pendingFirst = -1;
  int _pendingLast = -1;
  bool _loadScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.session.proxies.addListener(_guard);
  }

  @override
  void dispose() {
    widget.session.proxies.removeListener(_guard);
    widget.session.proxies.releaseGroupMembers(widget.group.name);
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.clamp(0.0, 480.0);
            final cols = _memberGridColumns(width);
            final maxHeight = constraints.maxHeight.clamp(0.0, 520.0);
            final contentHeight = group.memberCount == 0
                ? 148.0
                : _cardDetailHeaderExtent + _memberContentExtent(group, cols);
            final height = contentHeight.clamp(0.0, maxHeight);
            _detailSize = Size(width, height);
            final memberScroll = _memberScrollController(cols, height);
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: Hero(
                  tag: 'proxy-group-card-${group.name}',
                  flightShuttleBuilder: _shuttle,
                  child: _CardSurface(
                    style: style,
                    radius: 16,
                    child: _detailBody(
                      group,
                      widget.showIcon,
                      style,
                      IconButton(
                        tooltip: '组内延迟测试',
                        onPressed: _testing ? null : _runTest,
                        icon: _testing
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: style.icon,
                                ),
                              )
                            : Icon(Icons.speed_rounded, color: style.icon),
                      ),
                      onSelect: widget.onSelect,
                      onToggleFixed: widget.onToggleFixed,
                      onTestNode: widget.onTestNode,
                      loadNodeDetails: widget.loadNodeDetails,
                      onMissingMember: _queueMemberLoad,
                      scrollController: memberScroll,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FlightSnapshot extends StatefulWidget {
  const _FlightSnapshot({
    required this.initialScrollOffset,
    required this.builder,
  });

  final double initialScrollOffset;
  final Widget Function(ScrollController) builder;

  @override
  State<_FlightSnapshot> createState() => _FlightSnapshotState();
}

class _FlightSnapshotState extends State<_FlightSnapshot>
    with WidgetsBindingObserver {
  late final SnapshotController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _controller = SnapshotController(
      allowSnapshotting:
          lifecycleState == null || lifecycleState == AppLifecycleState.resumed,
    );
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialScrollOffset,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.allowSnapshotting = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotWidget(
      controller: _controller,
      mode: SnapshotMode.permissive,
      child: widget.builder(_scrollController),
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
