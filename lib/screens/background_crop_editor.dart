part of 'theme_settings_screen.dart';

class _BackgroundFocalPointTile extends StatelessWidget {
  const _BackgroundFocalPointTile({
    required this.path,
    required this.mobile,
    required this.focalPoint,
    required this.zoom,
    required this.onTap,
  });

  final String path;
  final bool mobile;
  final Alignment focalPoint;
  final double zoom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = path.isNotEmpty;
    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 76,
            height: 52,
            child: enabled
                ? AppBackgroundFrame(
                    source: AppBackgroundSource.image,
                    imagePath: path,
                    fit: AppBackgroundFit.focalPoint,
                    focalPoint: focalPoint,
                    zoom: zoom,
                    child: const SizedBox.shrink(),
                  )
                : ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.image_outlined)),
                  ),
          ),
        ),
        title: Text(mobile ? '裁切区域' : '视觉中心'),
        subtitle: Text(
          mobile ? '拖动和缩放图片调整显示范围' : '点击图片标记窗口优先居中的位置',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

typedef _BackgroundViewport = ({Alignment focalPoint, double zoom});

class _BackgroundFocalPointEditor extends StatefulWidget {
  const _BackgroundFocalPointEditor({
    required this.path,
    required this.initial,
    required this.initialZoom,
    required this.mobile,
    required this.targetAspectRatio,
  });

  final String path;
  final Alignment initial;
  final double initialZoom;
  final bool mobile;
  final double targetAspectRatio;

  @override
  State<_BackgroundFocalPointEditor> createState() =>
      _BackgroundFocalPointEditorState();
}

class _BackgroundFocalPointEditorState
    extends State<_BackgroundFocalPointEditor> {
  late Alignment _draftFocalPoint;
  late double _draftZoom;

  @override
  void initState() {
    super.initState();
    _draftFocalPoint = widget.initial;
    _draftZoom = widget.mobile
        ? widget.initialZoom
        : AppPrefs.defaultBackgroundZoom;
  }

  void _resetViewport() {
    setState(() {
      _draftFocalPoint = Alignment.center;
      _draftZoom = AppPrefs.defaultBackgroundZoom;
    });
  }

  bool get _isDefaultViewport =>
      _draftFocalPoint == Alignment.center &&
      _draftZoom == AppPrefs.defaultBackgroundZoom;

  void _updateViewport(_BackgroundViewport value) {
    final defaultChanged =
        _isDefaultViewport !=
        (value.focalPoint == Alignment.center &&
            value.zoom == AppPrefs.defaultBackgroundZoom);
    _draftFocalPoint = value.focalPoint;
    _draftZoom = value.zoom;
    if (defaultChanged) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, widget.mobile ? 2 : 12, 8, 10),
              child: Row(
                children: [
                  Icon(
                    widget.mobile
                        ? Icons.crop_free_rounded
                        : Icons.center_focus_strong_rounded,
                    size: 22,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.mobile ? '框选背景画面' : '设置视觉中心',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.mobile ? '恢复默认裁切' : '恢复默认中心',
                    onPressed: _isDefaultViewport ? null : _resetViewport,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                  IconButton(
                    tooltip: '取消',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: _BackgroundFocalPointPicker(
                path: widget.path,
                focalPoint: _draftFocalPoint,
                zoom: _draftZoom,
                mobile: widget.mobile,
                targetAspectRatio: widget.targetAspectRatio,
                onChanged: _updateViewport,
              ),
            ),
          ),
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, (
                      focalPoint: _draftFocalPoint,
                      zoom: _draftZoom,
                    )),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundFocalPointPicker extends StatefulWidget {
  const _BackgroundFocalPointPicker({
    required this.path,
    required this.focalPoint,
    required this.zoom,
    required this.mobile,
    required this.targetAspectRatio,
    required this.onChanged,
  });

  final String path;
  final Alignment focalPoint;
  final double zoom;
  final bool mobile;
  final double targetAspectRatio;
  final ValueChanged<_BackgroundViewport> onChanged;

  @override
  State<_BackgroundFocalPointPicker> createState() =>
      _BackgroundFocalPointPickerState();
}

class _BackgroundFocalPointPickerState
    extends State<_BackgroundFocalPointPicker> {
  Size? _sourceSize;
  late Alignment _draftFocalPoint;
  late double _draftZoom;
  var _loadFailed = false;
  var _loadGeneration = 0;
  var _gesturing = false;
  var _gestureStartZoom = AppPrefs.defaultBackgroundZoom;
  var _lastGesturePoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _draftFocalPoint = widget.focalPoint;
    _draftZoom = widget.mobile ? widget.zoom : AppPrefs.defaultBackgroundZoom;
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _BackgroundFocalPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _resolveImage();
    if (!_gesturing) {
      if (oldWidget.focalPoint != widget.focalPoint) {
        _draftFocalPoint = widget.focalPoint;
      }
      if (oldWidget.zoom != widget.zoom) _draftZoom = widget.zoom;
    }
  }

  void _resolveImage() {
    final generation = ++_loadGeneration;
    _sourceSize = BackgroundImageStore.cachedImageSize(widget.path);
    _loadFailed = false;
    if (widget.path.isEmpty || _sourceSize != null) return;
    BackgroundImageStore.imageSize(widget.path).then(
      (size) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() => _sourceSize = size);
      },
      onError: (_, _) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() => _loadFailed = true);
      },
    );
  }

  Size _stageSize(BoxConstraints constraints) {
    const maxWidth = 620.0;
    final maxHeight = widget.mobile ? 840.0 : 480.0;
    final width = constraints.maxWidth.isFinite
        ? math.min(constraints.maxWidth, maxWidth)
        : maxWidth;
    final height = constraints.maxHeight.isFinite
        ? math.min(constraints.maxHeight, maxHeight)
        : maxHeight;
    return Size(math.max(0, width), math.max(0, height));
  }

  Rect _viewportRect(Size stage) {
    if (stage.isEmpty) return Rect.zero;
    final targetAspect =
        widget.targetAspectRatio.isFinite && widget.targetAspectRatio > 0
        ? widget.targetAspectRatio
        : 1.0;
    const margin = 16.0;
    final availableWidth = math.max(1.0, stage.width - margin * 2);
    final availableHeight = math.max(1.0, stage.height - margin * 2);
    var width = availableWidth;
    var height = width / targetAspect;
    if (height > availableHeight) {
      height = availableHeight;
      width = height * targetAspect;
    }
    return Rect.fromCenter(
      center: stage.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  Rect _containedImageRect(Size stage, Size source) {
    if (stage.isEmpty || source.isEmpty) return Rect.zero;
    const margin = 16.0;
    final available = Size(
      math.max(1.0, stage.width - margin * 2),
      math.max(1.0, stage.height - margin * 2),
    );
    final scale = math.min(
      available.width / source.width,
      available.height / source.height,
    );
    return Alignment.center.inscribe(
      Size(source.width * scale, source.height * scale),
      Offset.zero & stage,
    );
  }

  void _emit(Alignment focalPoint, double zoom) {
    setState(() {
      _draftFocalPoint = focalPoint;
      _draftZoom = zoom;
    });
    widget.onChanged((focalPoint: focalPoint, zoom: zoom));
  }

  void _startGesture(
    ScaleStartDetails details,
    Size source,
    Rect viewportRect,
  ) {
    final viewport = viewportRect.size;
    final layout = AppBackgroundLayout.resolve(
      sourceSize: source,
      targetSize: viewport,
      focalPoint: _draftFocalPoint,
      zoom: _draftZoom,
    );
    setState(() {
      _gesturing = true;
      _draftFocalPoint = layout.focalPoint;
      _gestureStartZoom = _draftZoom;
      _lastGesturePoint = details.localFocalPoint - viewportRect.topLeft;
    });
  }

  void _updateGesture(
    ScaleUpdateDetails details,
    Size source,
    Rect viewportRect,
  ) {
    final viewport = viewportRect.size;
    final gesturePoint = details.localFocalPoint - viewportRect.topLeft;
    final currentLayout = AppBackgroundLayout.resolve(
      sourceSize: source,
      targetSize: viewport,
      focalPoint: _draftFocalPoint,
      zoom: _draftZoom,
    );
    if (currentLayout.imageRect.isEmpty) return;
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final sourceAtGesture = Alignment(
      currentLayout.focalPoint.x +
          2 *
              (_lastGesturePoint.dx - center.dx) /
              currentLayout.imageRect.width,
      currentLayout.focalPoint.y +
          2 *
              (_lastGesturePoint.dy - center.dy) /
              currentLayout.imageRect.height,
    );
    final nextZoom = (_gestureStartZoom * details.scale)
        .clamp(AppPrefs.defaultBackgroundZoom, AppPrefs.maxBackgroundZoom)
        .toDouble();
    final nextSize = AppBackgroundLayout.resolve(
      sourceSize: source,
      targetSize: viewport,
      focalPoint: Alignment.center,
      zoom: nextZoom,
    ).imageRect.size;
    final nextFocalPoint = Alignment(
      sourceAtGesture.x - 2 * (gesturePoint.dx - center.dx) / nextSize.width,
      sourceAtGesture.y - 2 * (gesturePoint.dy - center.dy) / nextSize.height,
    );
    final nextLayout = AppBackgroundLayout.resolve(
      sourceSize: source,
      targetSize: viewport,
      focalPoint: nextFocalPoint,
      zoom: nextZoom,
    );
    _lastGesturePoint = gesturePoint;
    _emit(nextLayout.focalPoint, nextZoom);
  }

  void _endGesture() {
    if (!_gesturing) return;
    setState(() => _gesturing = false);
  }

  void _markDesktopFocalPoint(TapDownDetails details, Rect imageRect) {
    if (!imageRect.contains(details.localPosition)) return;
    final point = details.localPosition - imageRect.topLeft;
    _emit(
      Alignment(
        (point.dx / imageRect.width * 2 - 1).clamp(-1.0, 1.0),
        (point.dy / imageRect.height * 2 - 1).clamp(-1.0, 1.0),
      ),
      AppPrefs.defaultBackgroundZoom,
    );
  }

  Widget _buildMobilePicker({
    required ColorScheme scheme,
    required Size sourceSize,
    required Rect viewportRect,
    required AppBackgroundLayout layout,
    required ImageProvider<Object> provider,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        trackpadScrollCausesScale: true,
        onScaleStart: (details) =>
            _startGesture(details, sourceSize, viewportRect),
        onScaleUpdate: (details) =>
            _updateGesture(details, sourceSize, viewportRect),
        onScaleEnd: (_) => _endGesture(),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            ColoredBox(color: scheme.surfaceContainerHighest),
            Positioned.fromRect(
              rect: layout.imageRect.shift(viewportRect.topLeft),
              child: Image(
                image: provider,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _CropViewportPainter(
                  viewport: viewportRect,
                  accent: scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopPicker({
    required ColorScheme scheme,
    required Rect imageRect,
    required ImageProvider<Object> provider,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _markDesktopFocalPoint(details, imageRect),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: scheme.surfaceContainerHighest),
              Positioned.fromRect(
                rect: imageRect,
                child: Image(
                  image: provider,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _FocalPointPainter(
                    imageRect: imageRect,
                    focalPoint: _draftFocalPoint,
                    accent: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceSize = _sourceSize;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stage = _stageSize(constraints);
              final viewportRect = widget.mobile
                  ? _viewportRect(stage)
                  : Rect.zero;
              final viewport = viewportRect.size;
              final mobileLayout =
                  !widget.mobile || sourceSize == null || viewport.isEmpty
                  ? null
                  : AppBackgroundLayout.resolve(
                      sourceSize: sourceSize,
                      targetSize: viewport,
                      focalPoint: _draftFocalPoint,
                      zoom: _draftZoom,
                    );
              final imageRect = sourceSize == null
                  ? Rect.zero
                  : widget.mobile
                  ? mobileLayout!.imageRect.shift(viewportRect.topLeft)
                  : _containedImageRect(stage, sourceSize);
              final provider = sourceSize == null || imageRect.isEmpty
                  ? null
                  : backgroundImageProvider(
                      path: widget.path,
                      sourceSize: sourceSize,
                      displaySize: imageRect.size,
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    );
              return Center(
                child: SizedBox.fromSize(
                  size: stage,
                  child: provider == null || sourceSize == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Center(
                            child: _loadFailed || widget.path.isEmpty
                                ? const Text('无法读取背景图片')
                                : const CircularProgressIndicator(),
                          ),
                        )
                      : widget.mobile
                      ? _buildMobilePicker(
                          scheme: scheme,
                          sourceSize: sourceSize,
                          viewportRect: viewportRect,
                          layout: mobileLayout!,
                          provider: provider,
                        )
                      : _buildDesktopPicker(
                          scheme: scheme,
                          imageRect: imageRect,
                          provider: provider,
                        ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.mobile
              ? '拖动图片调整位置，双指缩放；框内画面就是当前屏幕最终显示范围。'
              : '点击图片标记视觉中心；窗口比例变化时会尽量保持该位置居中。',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CropViewportPainter extends CustomPainter {
  const _CropViewportPainter({required this.viewport, required this.accent});

  final Rect viewport;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rect = viewport.intersect(bounds);
    if (rect.isEmpty) return;
    final viewportRRect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(14),
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds)
      ..addRRect(viewportRRect);
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );

    canvas.save();
    canvas.clipRRect(viewportRRect);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.46)
      ..strokeWidth = 1;
    for (final fraction in const [1 / 3, 2 / 3]) {
      final x = rect.left + rect.width * fraction;
      final y = rect.top + rect.height * fraction;
      canvas
        ..drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid)
        ..drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1.25), const Radius.circular(13)),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CropViewportPainter oldDelegate) =>
      viewport != oldDelegate.viewport || accent != oldDelegate.accent;
}

class _FocalPointPainter extends CustomPainter {
  const _FocalPointPainter({
    required this.imageRect,
    required this.focalPoint,
    required this.accent,
  });

  final Rect imageRect;
  final Alignment focalPoint;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = imageRect.intersect(Offset.zero & size);
    if (rect.isEmpty) return;
    final point = Offset(
      imageRect.left + (focalPoint.x + 1) * imageRect.width / 2,
      imageRect.top + (focalPoint.y + 1) * imageRect.height / 2,
    );
    final halo = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final marker = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final core = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final segment in [
      (Offset(point.dx - 18, point.dy), Offset(point.dx + 18, point.dy)),
      (Offset(point.dx, point.dy - 18), Offset(point.dx, point.dy + 18)),
    ]) {
      canvas
        ..drawLine(segment.$1, segment.$2, halo)
        ..drawLine(segment.$1, segment.$2, marker);
    }
    canvas
      ..drawCircle(point, 11, halo)
      ..drawCircle(point, 11, marker)
      ..drawCircle(point, 7.5, core);
  }

  @override
  bool shouldRepaint(covariant _FocalPointPainter oldDelegate) =>
      imageRect != oldDelegate.imageRect ||
      focalPoint != oldDelegate.focalPoint ||
      accent != oldDelegate.accent;
}
