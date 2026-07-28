import 'dart:async';

import 'package:flutter/material.dart';

import '../session.dart';
import '../utils.dart';
import 'pressable_scale.dart';
import 'proxy_avatar.dart';

// Same-hue deep gradients (roughly tailwind 600 → 900) so any two adjacent
// cards stay harmonious and white text keeps contrast.
const _gradients = <(Color, Color)>[
  (Color(0xff2563eb), Color(0xff1e3a8a)),
  (Color(0xff0891b2), Color(0xff164e63)),
  (Color(0xff0d9488), Color(0xff134e4a)),
  (Color(0xff059669), Color(0xff064e3b)),
  (Color(0xff4f46e5), Color(0xff312e81)),
  (Color(0xff7c3aed), Color(0xff4c1d95)),
  (Color(0xffea580c), Color(0xff7c2d12)),
  (Color(0xff475569), Color(0xff1e293b)),
];

LinearGradient _gradientFor(String name) {
  final hash = name.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
  final (start, end) = _gradients[hash % _gradients.length];
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color.lerp(start, Colors.white, 0.12)!, start, end],
    stops: const [0, 0.3, 1],
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
  if (colored) {
    return _CardStyle(
      gradient: _gradientFor(name),
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
  final scheme = Theme.of(context).colorScheme;
  return _CardStyle(
    background: scheme.surfaceContainerHigh,
    cardBorder: scheme.outlineVariant.withValues(alpha: 0.5),
    title: scheme.onSurface,
    subtitle: scheme.onSurfaceVariant,
    icon: scheme.onSurfaceVariant,
    tileBg: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
    tileSelectedBg: scheme.primaryContainer.withValues(alpha: 0.7),
    tileBorder: scheme.outlineVariant.withValues(alpha: 0.4),
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
  });

  final _CardStyle style;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: style.gradient,
        color: style.background,
        borderRadius: BorderRadius.circular(radius),
        border: style.cardBorder == null
            ? null
            : Border.all(color: style.cardBorder!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class ProxyGroupCard extends StatelessWidget {
  const ProxyGroupCard({
    super.key,
    required this.group,
    required this.showIcon,
    required this.colored,
    required this.onTap,
  });

  final ProxyGroup group;
  final bool showIcon;
  final bool colored;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(context, group.name, colored);
    return PressableScale(
      child: Hero(
        tag: 'proxy-group-card-${group.name}',
        child: _CardSurface(
          style: style,
          radius: showIcon ? 20 : 16,
          child: InkWell(
            onTap: onTap,
            child: _collapsedContent(group, showIcon, style),
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

Widget _collapsedContent(ProxyGroup group, bool showIcon, _CardStyle style) {
  if (!showIcon) return _compactCollapsedContent(group, style);
  return Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProxyAvatar(name: group.name, icon: group.icon, size: 32),
        const Spacer(),
        ValueListenableBuilder<String>(
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

Widget _compactCollapsedContent(ProxyGroup group, _CardStyle style) {
  return ValueListenableBuilder<String>(
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
          child: ValueListenableBuilder<String>(
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
  ValueChanged<String>? onTestNode,
  ValueChanged<int>? onMissingMember,
  bool scrollable = true,
}) {
  return Column(
    children: [
      _headerRow(group, showIcon, style, trailing),
      Expanded(
        child: ValueListenableBuilder<int>(
          valueListenable: group.membersVersion,
          builder: (_, _, _) => _memberGrid(
            group,
            style,
            onSelect: onSelect,
            onTestNode: onTestNode,
            onMissingMember: onMissingMember,
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
  ValueChanged<String>? onTestNode,
  ValueChanged<int>? onMissingMember,
  bool scrollable = true,
}) {
  if (group.memberCount == 0) {
    return Center(
      child: Text('暂无节点', style: TextStyle(color: style.subtitle)),
    );
  }
  return GridView.builder(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    physics: scrollable ? null : const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 260,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      mainAxisExtent: 64,
    ),
    itemCount: group.memberCount,
    itemBuilder: (context, index) {
      final member = group.memberAt(index);
      if (member == null) {
        onMissingMember?.call(index);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: style.tileBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: style.tileBorder),
          ),
        );
      }
      return _CardNodeTile(
        key: ValueKey('${group.name}::${member.name}'),
        group: group,
        member: member,
        style: style,
        onSelect: onSelect == null ? null : () => onSelect(member.name),
        onTestDelay: onTestNode == null ? null : () => onTestNode(member.name),
      );
    },
  );
}

Future<void> showProxyGroupCardDetail(
  BuildContext context, {
  required MihomoSession session,
  required ProxyGroup group,
  required bool showIcon,
  required bool colored,
  required Future<void> Function() onTestGroup,
  required ValueChanged<String> onSelect,
  required ValueChanged<String> onTestNode,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      allowSnapshotting: false,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => _ProxyGroupCardDetail(
        session: session,
        group: group,
        showIcon: showIcon,
        colored: colored,
        onTestGroup: onTestGroup,
        onSelect: onSelect,
        onTestNode: onTestNode,
      ),
    ),
  );
}

class _ProxyGroupCardDetail extends StatefulWidget {
  const _ProxyGroupCardDetail({
    required this.session,
    required this.group,
    required this.showIcon,
    required this.colored,
    required this.onTestGroup,
    required this.onSelect,
    required this.onTestNode,
  });

  final MihomoSession session;
  final ProxyGroup group;
  final bool showIcon;
  final bool colored;
  final Future<void> Function() onTestGroup;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onTestNode;

  @override
  State<_ProxyGroupCardDetail> createState() => _ProxyGroupCardDetailState();
}

class _ProxyGroupCardDetailState extends State<_ProxyGroupCardDetail> {
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
            child: _detailBody(
              group,
              widget.showIcon,
              style,
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.speed_rounded, color: style.icon),
              ),
              scrollable: false,
            ),
          ),
        ),
      );
    }
    return _CardSurface(
      style: style,
      radius: 22,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: ReverseAnimation(animation),
              child: _collapsedContent(group, widget.showIcon, style),
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
    super.dispose();
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
            final cols = ((width - 24) / 260).ceil().clamp(1, 4);
            final count = group.memberCount;
            final rows = count == 0 ? 1 : (count + cols - 1) ~/ cols;
            final maxHeight = constraints.maxHeight.clamp(0.0, 520.0);
            final height = (rows * 72.0 + 76).clamp(0.0, maxHeight);
            _detailSize = Size(width, height);
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: Hero(
                  tag: 'proxy-group-card-${group.name}',
                  flightShuttleBuilder: _shuttle,
                  child: _CardSurface(
                    style: style,
                    radius: 24,
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
                      onTestNode: widget.onTestNode,
                      onMissingMember: _queueMemberLoad,
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
  const _FlightSnapshot({required this.child});

  final Widget child;

  @override
  State<_FlightSnapshot> createState() => _FlightSnapshotState();
}

class _FlightSnapshotState extends State<_FlightSnapshot>
    with WidgetsBindingObserver {
  late final SnapshotController _controller;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _controller = SnapshotController(
      allowSnapshotting:
          lifecycleState == null || lifecycleState == AppLifecycleState.resumed,
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotWidget(
      controller: _controller,
      mode: SnapshotMode.permissive,
      child: widget.child,
    );
  }
}

class _CardNodeTile extends StatelessWidget {
  const _CardNodeTile({
    super.key,
    required this.group,
    required this.member,
    required this.style,
    required this.onSelect,
    required this.onTestDelay,
  });

  final ProxyGroup group;
  final ProxyMember member;
  final _CardStyle style;
  final VoidCallback? onSelect;
  final VoidCallback? onTestDelay;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: group.now,
      builder: (_, now, _) {
        final selected = !group.hidesExactNow && now == member.name;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? style.tileSelectedBg : style.tileBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? style.tileSelectedBorder : style.tileBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: group.canSelectMembers ? onSelect : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: TextStyle(
                        color: style.tileTitle,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.type,
                            style: TextStyle(
                              color: style.tileSubtitle,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _DelayPill(
                          delay: member.delay,
                          untestedColor: style.pillUntested,
                          onTap: onTestDelay,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
    return ValueListenableBuilder<int>(
      valueListenable: delay,
      builder: (_, ms, _) {
        final color = switch (classifyDelay(ms)) {
          DelayBucket.untested => untestedColor,
          DelayBucket.timeout => const Color(0xffef4444),
          DelayBucket.fast => const Color(0xff22c55e),
          DelayBucket.slow => const Color(0xfff59e0b),
        };
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
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
        );
      },
    );
  }
}
