import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../gamepad_navigation.dart';
import 'anchored_details_overlay.dart';
import 'transient_animation.dart';

const _pressFeedbackDelay = Duration(milliseconds: 220);

class AnchoredDetailsTrigger extends StatefulWidget {
  const AnchoredDetailsTrigger({
    super.key,
    required this.child,
    required this.barrierLabel,
    required this.semanticsHint,
    required this.detailsBuilder,
    this.onActivate,
    this.excludedTopRightSize = Size.zero,
    this.maxDetailsWidth = 320,
    this.requireFullyVisible = false,
    this.excludeChildFocus = false,
    this.previewInteractive = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final Widget child;
  final String barrierLabel;
  final String semanticsHint;
  final WidgetBuilder detailsBuilder;
  final VoidCallback? onActivate;
  final Size excludedTopRightSize;
  final double maxDetailsWidth;
  final bool requireFullyVisible;
  final bool excludeChildFocus;
  final bool previewInteractive;
  final BorderRadius borderRadius;

  @override
  State<AnchoredDetailsTrigger> createState() => _AnchoredDetailsTriggerState();
}

class _AnchoredDetailsTriggerState extends State<AnchoredDetailsTrigger> {
  final GlobalKey _childKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<int> _contentRevision = ValueNotifier(0);
  Timer? _pressTimer;
  ({Rect rect, bool fullyVisible})? _pendingGeometry;
  bool _open = false;
  bool _pressing = false;
  bool _focused = false;
  bool _contentRefreshScheduled = false;

  @override
  void didUpdateWidget(covariant AnchoredDetailsTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_open) _scheduleContentRefresh();
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    _contentRevision.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleContentRefresh() {
    if (_contentRefreshScheduled) return;
    _contentRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentRefreshScheduled = false;
      if (mounted && _open) _contentRevision.value++;
    });
  }

  Future<void> _showDetails() async {
    if (_open) {
      _pendingGeometry = null;
      return;
    }
    final sourceFocus = _focusNode.hasFocus
        ? FocusManager.instance.primaryFocus
        : null;
    final geometry = _pendingGeometry ?? _sourceGeometry();
    _pendingGeometry = null;
    if (geometry == null ||
        (widget.requireFullyVisible && !geometry.fullyVisible)) {
      _cancelPress();
      return;
    }
    final sourceRect = geometry.rect;

    unawaited(_triggerHaptic());
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
        preview: ListenableBuilder(
          listenable: _contentRevision,
          builder: (_, _) => widget.child,
        ),
        barrierLabel: widget.barrierLabel,
        maxDetailsWidth: widget.maxDetailsWidth,
        previewInteractive: widget.previewInteractive,
        detailsBuilder: (context) => ListenableBuilder(
          listenable: _contentRevision,
          builder: (context, _) => widget.detailsBuilder(context),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _open = false);
        if (sourceFocus != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final sourceContext = sourceFocus.context;
            if (!mounted ||
                sourceContext == null ||
                !sourceContext.mounted ||
                !sourceFocus.canRequestFocus) {
              return;
            }
            sourceFocus.requestFocus();
          });
        }
      }
    }
  }

  ({Rect rect, bool fullyVisible})? _sourceGeometry() {
    final childBox = _childKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (childBox == null || overlayBox == null || !childBox.hasSize) {
      return null;
    }
    final sourceRect = Rect.fromPoints(
      childBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      childBox.localToGlobal(
        childBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );
    final viewport = RenderAbstractViewport.maybeOf(childBox);
    final viewportBox = viewport is RenderBox ? viewport as RenderBox : null;
    var fullyVisible = true;
    if (viewportBox != null && viewportBox.hasSize) {
      final viewportRect = Rect.fromPoints(
        viewportBox.localToGlobal(Offset.zero, ancestor: overlayBox),
        viewportBox.localToGlobal(
          viewportBox.size.bottomRight(Offset.zero),
          ancestor: overlayBox,
        ),
      );
      final visibleRect = sourceRect.intersect(viewportRect);
      const tolerance = 0.5;
      fullyVisible =
          !visibleRect.isEmpty &&
          visibleRect.width >= sourceRect.width - tolerance &&
          visibleRect.height >= sourceRect.height - tolerance;
    }
    return (rect: sourceRect, fullyVisible: fullyVisible);
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
    _startPressFeedback();
  }

  void _startPressFeedback() {
    _pressTimer?.cancel();
    _pressTimer = Timer(_pressFeedbackDelay, () {
      _pressTimer = null;
      if (mounted) _setPressing(true);
    });
  }

  bool _allowLongPress(int buttons) {
    if (buttons != kPrimaryButton) return false;
    if (!widget.requireFullyVisible) {
      _pendingGeometry = null;
      return true;
    }
    final geometry = _sourceGeometry();
    if (geometry?.fullyVisible != true) {
      _pendingGeometry = null;
      return false;
    }
    _pendingGeometry = geometry;
    return true;
  }

  void _cancelPress() {
    _pressTimer?.cancel();
    _pressTimer = null;
    _pendingGeometry = null;
    _setPressing(false);
  }

  void _activate() {
    widget.onActivate?.call();
  }

  Widget _gestureDetector({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onSecondaryTap: _showDetails,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: gamepadLongPressDuration,
                  debugOwner: this,
                  allowedButtonsFilter: _allowLongPress,
                ),
                (recognizer) => recognizer
                  ..onLongPressDown = _handlePressDown
                  ..onLongPressCancel = _cancelPress
                  ..onLongPress = _showDetails
                  ..onLongPressEnd = (_) => _cancelPress(),
              ),
        },
        child: child,
      ),
    );
  }

  Widget _interactiveChild() {
    final excluded = widget.excludedTopRightSize;
    if (excluded == Size.zero) {
      return _gestureDetector(child: widget.child);
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          right: excluded.width,
          child: _gestureDetector(child: const SizedBox.expand()),
        ),
        Positioned(
          top: excluded.height,
          right: 0,
          bottom: 0,
          width: excluded.width,
          child: _gestureDetector(child: const SizedBox.expand()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _focusNode,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => _activate(),
        ),
        LongPressActivateIntent: CallbackAction<LongPressActivateIntent>(
          onInvoke: (_) => unawaited(_showDetails()),
        ),
        ActivationPressStartIntent: CallbackAction<ActivationPressStartIntent>(
          onInvoke: (_) => _startPressFeedback(),
        ),
        ActivationPressEndIntent: CallbackAction<ActivationPressEndIntent>(
          onInvoke: (_) => _cancelPress(),
        ),
      },
      onFocusChange: (value) {
        if (mounted && value != _focused) {
          setState(() => _focused = value);
        }
      },
      child: AppFocusHighlight(
        focused: _focused,
        borderRadius: widget.borderRadius,
        child: Semantics(
          hint: widget.semanticsHint,
          onTap: widget.onActivate == null ? null : _activate,
          onLongPress: _showDetails,
          child: TransientAnimatedScale(
            scale: _pressing ? 1.015 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: RepaintBoundary(
              child: KeyedSubtree(
                key: _childKey,
                child: ExcludeFocus(
                  excluding: _open || widget.excludeChildFocus,
                  child: IgnorePointer(
                    ignoring: _open,
                    child: Opacity(
                      opacity: _open ? 0 : 1,
                      child: _interactiveChild(),
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
