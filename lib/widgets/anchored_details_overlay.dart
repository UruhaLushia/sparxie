import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'transition_snapshot.dart';

const anchoredDetailsBlurSigma = 6.0;
final _backgroundBlur = ui.ImageFilter.blur(
  sigmaX: anchoredDetailsBlurSigma,
  sigmaY: anchoredDetailsBlurSigma,
);

enum AnchoredPreviewPlacement { automatic, above, below }

/// Captures and pre-blurs the current Flutter view at logical-pixel
/// resolution. Blur hides the downsampling while keeping the transient image
/// small enough to release immediately with the overlay route.
Future<ui.Image?> _captureAnchoredDetailsBackground(
  BuildContext context,
) async {
  ui.Image? source;
  ui.Picture? picture;
  try {
    final flutterView = View.of(context);
    final renderView = RendererBinding.instance.renderViews
        .where((candidate) => candidate.flutterView == flutterView)
        .firstOrNull;
    // RenderView owns the root layer; capturing it is the only way to include
    // the already-painted route without wrapping the whole app in a boundary.
    // ignore: invalid_use_of_protected_member
    final rootLayer = renderView?.layer;
    if (renderView == null || rootLayer is! OffsetLayer) return null;

    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    final physicalSize = flutterView.physicalSize;
    final devicePixelRatio = flutterView.devicePixelRatio;
    if (overlayBox == null ||
        !overlayBox.hasSize ||
        physicalSize.isEmpty ||
        devicePixelRatio <= 0) {
      return null;
    }
    final overlayOrigin = overlayBox.localToGlobal(Offset.zero);
    final logicalCaptureRect = overlayOrigin & overlayBox.size;
    final physicalCaptureRect = Rect.fromLTRB(
      logicalCaptureRect.left * devicePixelRatio,
      logicalCaptureRect.top * devicePixelRatio,
      logicalCaptureRect.right * devicePixelRatio,
      logicalCaptureRect.bottom * devicePixelRatio,
    ).intersect(Offset.zero & physicalSize);
    if (physicalCaptureRect.isEmpty) return null;
    source = await rootLayer.toImage(
      physicalCaptureRect,
      pixelRatio: 1 / devicePixelRatio,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(
      source,
      Offset.zero,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: anchoredDetailsBlurSigma,
          sigmaY: anchoredDetailsBlurSigma,
          tileMode: TileMode.clamp,
        ),
    );
    picture = recorder.endRecording();
    return await picture.toImage(source.width, source.height);
  } catch (_) {
    return null;
  } finally {
    source?.dispose();
    picture?.dispose();
  }
}

Future<void> showAnchoredDetailsOverlay({
  required BuildContext context,
  required Rect sourceRect,
  required Widget preview,
  required WidgetBuilder detailsBuilder,
  required String barrierLabel,
  AnchoredPreviewPlacement previewPlacement =
      AnchoredPreviewPlacement.automatic,
  bool preserveSourcePosition = false,
  double maxDetailsWidth = 320,
}) async {
  final backgroundImage = await _captureAnchoredDetailsBackground(context);
  if (!context.mounted) {
    backgroundImage?.dispose();
    return;
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  final route = RawDialogRoute<void>(
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    barrierLabel: barrierLabel,
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (_, _, _, child) => child,
    pageBuilder: (dialogContext, animation, _) => AnchoredDetailsOverlay(
      animation: animation,
      sourceRect: sourceRect,
      preview: preview,
      previewPlacement: previewPlacement,
      preserveSourcePosition: preserveSourcePosition,
      backgroundImage: backgroundImage,
      maxDetailsWidth: maxDetailsWidth,
      details: detailsBuilder(dialogContext),
      onDismiss: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
    ),
  );
  try {
    final popped = navigator.push<void>(route);
    await route.completed;
    await popped;
  } finally {
    backgroundImage?.dispose();
  }
}

/// Positions a source preview and a details card around the source rect.
/// During the transition only the two isolated layers are transformed.
class AnchoredDetailsOverlay extends StatelessWidget {
  const AnchoredDetailsOverlay({
    super.key,
    required this.animation,
    required this.sourceRect,
    required this.preview,
    required this.details,
    required this.onDismiss,
    this.maxDetailsWidth = 320,
    this.previewPlacement = AnchoredPreviewPlacement.automatic,
    this.preserveSourcePosition = false,
    this.backgroundImage,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Widget preview;
  final Widget details;
  final VoidCallback onDismiss;
  final double maxDetailsWidth;
  final AnchoredPreviewPlacement previewPlacement;
  final bool preserveSourcePosition;
  final ui.Image? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final usableCenter =
        (safePadding.top + size.height - safePadding.bottom) / 2;
    final detailsBelow = switch (previewPlacement) {
      AnchoredPreviewPlacement.automatic =>
        sourceRect.center.dy <= usableCenter,
      AnchoredPreviewPlacement.above => true,
      AnchoredPreviewPlacement.below => false,
    };
    final background = backgroundImage;

    final transitioningPreview = DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        boxShadow: [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 16,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: HighRefreshTransitionSnapshot(
        animation: animation,
        child: Material(type: MaterialType.transparency, child: preview),
      ),
    );
    final elevatedDetails = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: HighRefreshTransitionSnapshot(
          animation: animation,
          child: details,
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: background == null
              ? BackdropFilter(
                  filter: _backgroundBlur,
                  child: const SizedBox.expand(),
                )
              : RawImage(
                  image: background,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
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
          delegate: _AnchoredDetailsFlowDelegate(
            animation: animation,
            sourceRect: sourceRect,
            safePadding: safePadding,
            detailsBelow: detailsBelow,
            preserveSourcePosition: preserveSourcePosition,
            maxDetailsWidth: maxDetailsWidth,
          ),
          children: [
            IgnorePointer(child: RepaintBoundary(child: transitioningPreview)),
            RepaintBoundary(child: elevatedDetails),
          ],
        ),
      ],
    );
  }
}

class _AnchoredDetailsFlowDelegate extends FlowDelegate {
  _AnchoredDetailsFlowDelegate({
    required this.animation,
    required this.sourceRect,
    required this.safePadding,
    required this.detailsBelow,
    required this.preserveSourcePosition,
    required this.maxDetailsWidth,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Rect sourceRect;
  final EdgeInsets safePadding;
  final bool detailsBelow;
  final bool preserveSourcePosition;
  final double maxDetailsWidth;

  static const _screenInset = 16.0;
  static const _desktopShadowInset = 24.0;
  static const _detailsGap = 12.0;
  static const _minimumVisibleDetailsHeight = 240.0;

  double get _edgeInset =>
      preserveSourcePosition ? _desktopShadowInset : _screenInset;

  Size _availableSize(Size size) => Size(
    math.max(0.0, size.width - safePadding.horizontal - 2 * _edgeInset),
    math.max(0.0, size.height - safePadding.vertical - 2 * _edgeInset),
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
    final available = _availableSize(constraints.biggest);
    final previewSize = _previewSize(constraints.biggest);
    if (index == 0) return BoxConstraints.tight(previewSize);
    final width = math.min(maxDetailsWidth, available.width);
    final fullHeight = math.max(
      0.0,
      available.height - previewSize.height - _detailsGap,
    );
    var maxHeight = fullHeight;
    if (preserveSourcePosition && fullHeight > 0) {
      final size = constraints.biggest;
      final safeTop = safePadding.top + _edgeInset;
      final safeBottom = size.height - safePadding.bottom - _edgeInset;
      final previewTop = _clamp(
        sourceRect.top,
        safeTop,
        safeBottom - previewSize.height,
      );
      final adjacentHeight = detailsBelow
          ? safeBottom - previewTop - previewSize.height - _detailsGap
          : previewTop - safeTop - _detailsGap;
      final minimumHeight = math.min(_minimumVisibleDetailsHeight, fullHeight);
      maxHeight = math.min(fullHeight, math.max(adjacentHeight, minimumHeight));
    }
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: maxHeight,
    );
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final size = context.size;
    final safeLeft = safePadding.left + _edgeInset;
    final safeTop = safePadding.top + _edgeInset;
    final safeRight = size.width - safePadding.right - _edgeInset;
    final safeBottom = size.height - safePadding.bottom - _edgeInset;
    final targetPreviewSize = context.getChildSize(0)!;
    final detailsSize = context.getChildSize(1)!;

    final previewLeft = _clamp(
      sourceRect.center.dx - targetPreviewSize.width / 2,
      safeLeft,
      safeRight - targetPreviewSize.width,
    );
    late final double previewTop;
    late final double detailsTop;
    if (detailsBelow) {
      final groupHeight =
          targetPreviewSize.height + _detailsGap + detailsSize.height;
      previewTop = _clamp(sourceRect.top, safeTop, safeBottom - groupHeight);
      detailsTop = previewTop + targetPreviewSize.height + _detailsGap;
    } else {
      previewTop = _clamp(
        sourceRect.top,
        safeTop + detailsSize.height + _detailsGap,
        safeBottom - targetPreviewSize.height,
      );
      detailsTop = previewTop - _detailsGap - detailsSize.height;
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

    final detailsLeft = _clamp(
      targetPreviewRect.center.dx - detailsSize.width / 2,
      safeLeft,
      safeRight - detailsSize.width,
    );
    final detailsProgress = const Interval(
      0.12,
      1,
      curve: Curves.easeOutCubic,
    ).transform(animation.value);
    final scale = 0.96 + 0.04 * detailsProgress;
    final alignmentY = detailsBelow ? 0.0 : detailsSize.height;
    final offsetY = (detailsBelow ? -10.0 : 10.0) * (1 - detailsProgress);
    final detailsTransform = Matrix4.identity()
      ..translateByDouble(
        detailsLeft + detailsSize.width / 2,
        detailsTop + alignmentY + offsetY,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-detailsSize.width / 2, -alignmentY, 0, 1);
    context.paintChild(
      1,
      transform: detailsTransform,
      opacity: detailsProgress,
    );
  }

  @override
  bool shouldRelayout(covariant _AnchoredDetailsFlowDelegate oldDelegate) {
    return sourceRect != oldDelegate.sourceRect ||
        safePadding != oldDelegate.safePadding ||
        detailsBelow != oldDelegate.detailsBelow ||
        preserveSourcePosition != oldDelegate.preserveSourcePosition ||
        maxDetailsWidth != oldDelegate.maxDetailsWidth;
  }

  double _clamp(double value, double lower, double upper) {
    if (upper <= lower) return lower;
    return value.clamp(lower, upper).toDouble();
  }

  @override
  bool shouldRepaint(covariant _AnchoredDetailsFlowDelegate oldDelegate) {
    return sourceRect != oldDelegate.sourceRect ||
        safePadding != oldDelegate.safePadding ||
        detailsBelow != oldDelegate.detailsBelow ||
        preserveSourcePosition != oldDelegate.preserveSourcePosition ||
        maxDetailsWidth != oldDelegate.maxDetailsWidth ||
        animation != oldDelegate.animation;
  }
}
