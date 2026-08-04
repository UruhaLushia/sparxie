import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust_api.dart' as rust;
import 'anchored_details_overlay.dart';
import 'rule_details_panel.dart';
import 'transient_animation.dart';

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
      await showAnchoredDetailsOverlay(
        context: context,
        sourceRect: sourceRect,
        preview: widget.child,
        barrierLabel: '关闭规则详情',
        detailsBuilder: (_) => RuleDetailsPanel(rule: widget.rule),
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
