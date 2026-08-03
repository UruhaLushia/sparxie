import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust_api.dart' as rust;
import 'transient_animation.dart';
import 'rule_details_panel.dart';

const _previewRadius = BorderRadius.all(Radius.circular(12));
const _menuRadius = BorderRadius.all(Radius.circular(16));
final _contextBlur = ImageFilter.blur(sigmaX: 6, sigmaY: 6);
const _longPressDelay = Duration(milliseconds: 750);
const _pressFeedbackDelay = Duration(milliseconds: 220);

class RuleContextMenu extends StatefulWidget {
  const RuleContextMenu({
    super.key,
    required this.rule,
    required this.child,
    this.excludedTopRightSize = Size.zero,
  });

  final rust.RuleEntry rule;
  final Widget child;
  final Size excludedTopRightSize;

  @override
  State<RuleContextMenu> createState() => _RuleContextMenuState();
}

class _RuleContextMenuState extends State<RuleContextMenu> {
  final GlobalKey _childKey = GlobalKey();
  Timer? _pressTimer;
  bool _open = false;
  bool _pressing = false;

  @override
  void dispose() {
    _pressTimer?.cancel();
    super.dispose();
  }

  Future<void> _showMenu() async {
    if (_open) return;
    final childBox = _childKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (childBox == null || overlayBox == null || !childBox.hasSize) return;
    final sourceRect = Rect.fromPoints(
      childBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      childBox.localToGlobal(
        childBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    unawaited(_triggerHaptic());
    if (!mounted) return;
    _pressTimer?.cancel();
    _pressTimer = null;
    setState(() {
      _open = true;
      _pressing = false;
    });
    try {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        barrierLabel: '关闭规则详情',
        transitionDuration: const Duration(milliseconds: 240),
        transitionBuilder: (_, _, _, child) => child,
        pageBuilder: (dialogContext, animation, _) => _RuleContextOverlay(
          animation: animation,
          sourceRect: sourceRect,
          rule: widget.rule,
          preview: widget.child,
          onDismiss: () =>
              Navigator.of(dialogContext, rootNavigator: true).pop(),
        ),
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  Future<void> _triggerHaptic() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Haptics are optional on desktop platforms.
    }
  }

  void _setPressing(bool value) {
    if (_open || _pressing == value) return;
    setState(() => _pressing = value);
  }

  void _handlePressDown(LongPressDownDetails _) {
    _pressTimer?.cancel();
    _pressTimer = Timer(_pressFeedbackDelay, () {
      _pressTimer = null;
      if (mounted) _setPressing(true);
    });
  }

  void _cancelPress() {
    _pressTimer?.cancel();
    _pressTimer = null;
    _setPressing(false);
  }

  Widget _gestureRegion() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onSecondaryTap: _showMenu,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: _longPressDelay,
                  debugOwner: this,
                  allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
                ),
                (recognizer) => recognizer
                  ..onLongPressDown = _handlePressDown
                  ..onLongPressCancel = _cancelPress
                  ..onLongPress = _showMenu
                  ..onLongPressEnd = (_) => _cancelPress(),
              ),
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _gestureRegions() {
    final excluded = widget.excludedTopRightSize;
    if (excluded == Size.zero) {
      return Positioned.fill(child: _gestureRegion());
    }
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(right: excluded.width, child: _gestureRegion()),
          Positioned(
            top: excluded.height,
            right: 0,
            bottom: 0,
            width: excluded.width,
            child: _gestureRegion(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: '长按查看规则详情',
      onLongPress: _showMenu,
      child: TransientAnimatedScale(
        scale: _pressing ? 1.015 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: RepaintBoundary(
          child: KeyedSubtree(
            key: _childKey,
            child: IgnorePointer(
              ignoring: _open,
              child: Opacity(
                opacity: _open ? 0 : 1,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [widget.child, _gestureRegions()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleContextOverlay extends StatelessWidget {
  const _RuleContextOverlay({
    required this.animation,
    required this.sourceRect,
    required this.rule,
    required this.preview,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final rust.RuleEntry rule;
  final Widget preview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final usableCenter =
        (safePadding.top + size.height - safePadding.bottom) / 2;
    final menuBelow = sourceRect.center.dy <= usableCenter;
    final menu = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _menuRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _menuRadius,
        child: RuleDetailsPanel(rule: rule),
      ),
    );
    final elevatedPreview = DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: _previewRadius,
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: preview,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: BackdropFilter(
            filter: _contextBlur,
            child: const SizedBox.expand(),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, _) {
              final progress = Curves.easeOutCubic.transform(animation.value);
              return ColoredBox(
                color: scheme.scrim.withValues(alpha: 0.22 * progress),
              );
            },
          ),
        ),
        Flow(
          delegate: _RuleContextFlowDelegate(
            animation: animation,
            sourceRect: sourceRect,
            safePadding: safePadding,
            menuBelow: menuBelow,
          ),
          children: [
            IgnorePointer(child: RepaintBoundary(child: elevatedPreview)),
            RepaintBoundary(child: menu),
          ],
        ),
      ],
    );
  }
}

class _RuleContextFlowDelegate extends FlowDelegate {
  _RuleContextFlowDelegate({
    required this.animation,
    required this.sourceRect,
    required this.safePadding,
    required this.menuBelow,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Rect sourceRect;
  final EdgeInsets safePadding;
  final bool menuBelow;

  static const _screenInset = 16.0;
  static const _menuGap = 12.0;
  static const _maxMenuWidth = 320.0;

  Size _availableSize(Size size) => Size(
    math.max(0.0, size.width - safePadding.horizontal - 2 * _screenInset),
    math.max(0.0, size.height - safePadding.vertical - 2 * _screenInset),
  );

  Size _previewSize(Size size) {
    final available = _availableSize(size);
    return Size(
      math.min(sourceRect.width * 1.02, available.width),
      math.min(sourceRect.height * 1.02, available.height),
    );
  }

  @override
  BoxConstraints getConstraintsForChild(int index, BoxConstraints constraints) {
    final size = constraints.biggest;
    final available = _availableSize(size);
    final previewSize = _previewSize(size);
    if (index == 0) return BoxConstraints.tight(previewSize);
    final width = math.min(_maxMenuWidth, available.width);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(
        0.0,
        available.height - previewSize.height - _menuGap,
      ),
    );
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final size = context.size;
    final safeLeft = safePadding.left + _screenInset;
    final safeTop = safePadding.top + _screenInset;
    final safeRight = size.width - safePadding.right - _screenInset;
    final safeBottom = size.height - safePadding.bottom - _screenInset;
    final targetPreviewSize = context.getChildSize(0)!;
    final menuSize = context.getChildSize(1)!;

    final previewLeft = _clamp(
      sourceRect.center.dx - targetPreviewSize.width / 2,
      safeLeft,
      safeRight - targetPreviewSize.width,
    );
    late final double previewTop;
    late final double menuTop;
    if (menuBelow) {
      final groupHeight = targetPreviewSize.height + _menuGap + menuSize.height;
      previewTop = _clamp(sourceRect.top, safeTop, safeBottom - groupHeight);
      menuTop = previewTop + targetPreviewSize.height + _menuGap;
    } else {
      previewTop = _clamp(
        sourceRect.top,
        safeTop + menuSize.height + _menuGap,
        safeBottom - targetPreviewSize.height,
      );
      menuTop = previewTop - _menuGap - menuSize.height;
    }

    final targetPreviewRect =
        Offset(previewLeft, previewTop) & targetPreviewSize;
    final progress = Curves.easeOutCubic.transform(animation.value);
    final previewRect = Rect.lerp(sourceRect, targetPreviewRect, progress)!;
    final previewTransform = Matrix4.identity()
      ..translateByDouble(previewRect.left, previewRect.top, 0, 1)
      ..scaleByDouble(
        previewRect.width / targetPreviewSize.width,
        previewRect.height / targetPreviewSize.height,
        1,
        1,
      );
    context.paintChild(0, transform: previewTransform);

    final menuLeft = _clamp(
      targetPreviewRect.center.dx - menuSize.width / 2,
      safeLeft,
      safeRight - menuSize.width,
    );
    final menuProgress = const Interval(
      0.12,
      1,
      curve: Curves.easeOutCubic,
    ).transform(animation.value);
    final scale = 0.96 + 0.04 * menuProgress;
    final alignmentY = menuBelow ? 0.0 : menuSize.height;
    final offsetY = (menuBelow ? -10.0 : 10.0) * (1 - menuProgress);
    final menuTransform = Matrix4.identity()
      ..translateByDouble(
        menuLeft + menuSize.width / 2,
        menuTop + alignmentY + offsetY,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-menuSize.width / 2, -alignmentY, 0, 1);
    context.paintChild(1, transform: menuTransform, opacity: menuProgress);
  }

  @override
  bool shouldRelayout(covariant _RuleContextFlowDelegate oldDelegate) {
    return sourceRect != oldDelegate.sourceRect ||
        safePadding != oldDelegate.safePadding ||
        menuBelow != oldDelegate.menuBelow;
  }

  double _clamp(double value, double lower, double upper) {
    if (upper <= lower) return lower;
    return value.clamp(lower, upper).toDouble();
  }

  @override
  bool shouldRepaint(covariant _RuleContextFlowDelegate oldDelegate) {
    return sourceRect != oldDelegate.sourceRect ||
        safePadding != oldDelegate.safePadding ||
        menuBelow != oldDelegate.menuBelow ||
        animation != oldDelegate.animation;
  }
}
