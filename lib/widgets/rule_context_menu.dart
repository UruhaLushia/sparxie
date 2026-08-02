import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust_api.dart' as rust;
import 'rule_details_panel.dart';

const _previewRadius = BorderRadius.all(Radius.circular(12));
const _menuRadius = BorderRadius.all(Radius.circular(16));
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
      child: AnimatedScale(
        scale: _pressing ? 1.015 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
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
    );
  }
}

enum _RuleContextSlot { preview, menu }

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

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(animation.value);
        final menuProgress = const Interval(
          0.12,
          1,
          curve: Curves.easeOutCubic,
        ).transform(animation.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 6 * progress,
                  sigmaY: 6 * progress,
                ),
                child: ColoredBox(
                  color: scheme.scrim.withValues(alpha: 0.22 * progress),
                ),
              ),
            ),
            CustomMultiChildLayout(
              delegate: _RuleContextLayoutDelegate(
                sourceRect: sourceRect,
                safePadding: safePadding,
                progress: progress,
                menuBelow: menuBelow,
              ),
              children: [
                LayoutId(
                  id: _RuleContextSlot.preview,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: _previewRadius,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: 0.2 * progress,
                            ),
                            blurRadius: 18 * progress,
                            offset: Offset(0, 4 * progress),
                          ),
                        ],
                      ),
                      child: preview,
                    ),
                  ),
                ),
                LayoutId(
                  id: _RuleContextSlot.menu,
                  child: Opacity(
                    opacity: menuProgress,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        (menuBelow ? -10 : 10) * (1 - menuProgress),
                      ),
                      child: Transform.scale(
                        scale: 0.96 + 0.04 * menuProgress,
                        alignment: menuBelow
                            ? Alignment.topCenter
                            : Alignment.bottomCenter,
                        child: DecoratedBox(
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
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RuleContextLayoutDelegate extends MultiChildLayoutDelegate {
  _RuleContextLayoutDelegate({
    required this.sourceRect,
    required this.safePadding,
    required this.progress,
    required this.menuBelow,
  });

  final Rect sourceRect;
  final EdgeInsets safePadding;
  final double progress;
  final bool menuBelow;

  static const _screenInset = 16.0;
  static const _menuGap = 12.0;
  static const _maxMenuWidth = 320.0;

  @override
  void performLayout(Size size) {
    final safeLeft = safePadding.left + _screenInset;
    final safeTop = safePadding.top + _screenInset;
    final safeRight = size.width - safePadding.right - _screenInset;
    final safeBottom = size.height - safePadding.bottom - _screenInset;
    final availableWidth = math.max(0.0, safeRight - safeLeft);
    final availableHeight = math.max(0.0, safeBottom - safeTop);

    final targetPreviewWidth = math.min(
      sourceRect.width * 1.02,
      availableWidth,
    );
    final targetPreviewHeight = math.min(
      sourceRect.height * 1.02,
      availableHeight,
    );
    final menuWidth = math.min(_maxMenuWidth, availableWidth);
    final maxMenuHeight = math.max(
      0.0,
      availableHeight - targetPreviewHeight - _menuGap,
    );
    final menuSize = layoutChild(
      _RuleContextSlot.menu,
      BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
        maxHeight: maxMenuHeight,
      ),
    );

    final previewLeft = _clamp(
      sourceRect.center.dx - targetPreviewWidth / 2,
      safeLeft,
      safeRight - targetPreviewWidth,
    );
    late final double previewTop;
    late final double menuTop;
    if (menuBelow) {
      final groupHeight = targetPreviewHeight + _menuGap + menuSize.height;
      previewTop = _clamp(sourceRect.top, safeTop, safeBottom - groupHeight);
      menuTop = previewTop + targetPreviewHeight + _menuGap;
    } else {
      previewTop = _clamp(
        sourceRect.top,
        safeTop + menuSize.height + _menuGap,
        safeBottom - targetPreviewHeight,
      );
      menuTop = previewTop - _menuGap - menuSize.height;
    }

    final targetPreviewRect = Rect.fromLTWH(
      previewLeft,
      previewTop,
      targetPreviewWidth,
      targetPreviewHeight,
    );
    final previewRect = Rect.lerp(sourceRect, targetPreviewRect, progress)!;
    layoutChild(
      _RuleContextSlot.preview,
      BoxConstraints.tight(previewRect.size),
    );
    positionChild(_RuleContextSlot.preview, previewRect.topLeft);

    final menuLeft = _clamp(
      targetPreviewRect.center.dx - menuSize.width / 2,
      safeLeft,
      safeRight - menuSize.width,
    );
    positionChild(_RuleContextSlot.menu, Offset(menuLeft, menuTop));
  }

  double _clamp(double value, double lower, double upper) {
    if (upper <= lower) return lower;
    return value.clamp(lower, upper).toDouble();
  }

  @override
  bool shouldRelayout(covariant _RuleContextLayoutDelegate oldDelegate) {
    return sourceRect != oldDelegate.sourceRect ||
        safePadding != oldDelegate.safePadding ||
        progress != oldDelegate.progress ||
        menuBelow != oldDelegate.menuBelow;
  }
}
