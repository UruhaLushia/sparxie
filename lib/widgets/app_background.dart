import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../background_image_store.dart';
import '../platform_capabilities.dart';

@immutable
class AppSurfaceTheme extends ThemeExtension<AppSurfaceTheme> {
  static const compactAcrylicBlurScale = 0.65;
  static const compactAcrylicVeil = 0.06;
  static const minimumModalOpacity = 0.94;

  const AppSurfaceTheme({
    required this.enabled,
    required this.effect,
    required this.blurSigma,
    required this.opacity,
    required this.tintColor,
    this.blurScale = 1,
    this.acrylicVeil = 0.18,
  });

  const AppSurfaceTheme.disabled()
    : enabled = false,
      effect = AppSurfaceEffect.solid,
      blurSigma = 0,
      opacity = 1,
      tintColor = Colors.transparent,
      blurScale = 1,
      acrylicVeil = 0.18;

  final bool enabled;
  final AppSurfaceEffect effect;
  final double blurSigma;
  final double opacity;
  final Color tintColor;
  final double blurScale;
  final double acrylicVeil;

  double get effectiveBlur => !enabled || effect == AppSurfaceEffect.solid
      ? 0
      : blurSigma * (effect == AppSurfaceEffect.acrylic ? 1.15 : 1) * blurScale;

  double effectiveSurfaceOpacity([double lift = 0]) {
    final requested = (opacity + lift).clamp(0.05, 1.0).toDouble();
    return effect == AppSurfaceEffect.acrylic
        ? requested + (1 - requested) * acrylicVeil
        : requested;
  }

  Color surfaceColor(Color base, [double lift = 0]) {
    if (!enabled) return base;
    final tinted = effect == AppSurfaceEffect.acrylic
        ? Color.alphaBlend(tintColor.withValues(alpha: 0.055), base)
        : base;
    // Acrylic keeps a small luminosity veil in addition to its tint. Scale it
    // with the remaining transparency so low-opacity surfaces do not turn
    // nearly black over dark image regions, while high opacity barely changes.
    return tinted.withValues(alpha: effectiveSurfaceOpacity(lift));
  }

  Color modalSurfaceColor(Color base) {
    final lift = math.max(0.0, minimumModalOpacity - opacity);
    return surfaceColor(base, lift);
  }

  Color pageColor(Color fallback) => enabled ? Colors.transparent : fallback;

  Color chromeColor(Color fallback) => surfaceColor(fallback, -0.03);

  Color outlineColor(Color fallback) => enabled ? Colors.transparent : fallback;

  BorderSide outlineSide(Color color, {double width = 1}) =>
      enabled ? BorderSide.none : BorderSide(color: color, width: width);

  BoxBorder? outlineBorder(Color color, {double width = 1}) =>
      enabled ? null : Border.all(color: color, width: width);

  static AppSurfaceTheme of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaceTheme>() ??
      const AppSurfaceTheme.disabled();

  @override
  AppSurfaceTheme copyWith({
    bool? enabled,
    AppSurfaceEffect? effect,
    double? blurSigma,
    double? opacity,
    Color? tintColor,
    double? blurScale,
    double? acrylicVeil,
  }) => AppSurfaceTheme(
    enabled: enabled ?? this.enabled,
    effect: effect ?? this.effect,
    blurSigma: blurSigma ?? this.blurSigma,
    opacity: opacity ?? this.opacity,
    tintColor: tintColor ?? this.tintColor,
    blurScale: blurScale ?? this.blurScale,
    acrylicVeil: acrylicVeil ?? this.acrylicVeil,
  );

  @override
  AppSurfaceTheme lerp(covariant AppSurfaceTheme? other, double t) {
    if (other == null) return this;
    return AppSurfaceTheme(
      enabled: t < 0.5 ? enabled : other.enabled,
      effect: t < 0.5 ? effect : other.effect,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t)!,
      opacity: lerpDouble(opacity, other.opacity, t)!,
      tintColor: Color.lerp(tintColor, other.tintColor, t)!,
      blurScale: lerpDouble(blurScale, other.blurScale, t)!,
      acrylicVeil: lerpDouble(acrylicVeil, other.acrylicVeil, t)!,
    );
  }
}

@immutable
class AppBackgroundLayout {
  const AppBackgroundLayout({
    required this.imageRect,
    required this.focalPoint,
  });

  final Rect imageRect;
  final Alignment focalPoint;

  static AppBackgroundLayout resolve({
    required Size sourceSize,
    required Size targetSize,
    required Alignment focalPoint,
    required double zoom,
  }) {
    if (sourceSize.isEmpty || targetSize.isEmpty) {
      return const AppBackgroundLayout(
        imageRect: Rect.zero,
        focalPoint: Alignment.center,
      );
    }
    final safeZoom = zoom.isFinite
        ? zoom
              .clamp(AppPrefs.defaultBackgroundZoom, AppPrefs.maxBackgroundZoom)
              .toDouble()
        : AppPrefs.defaultBackgroundZoom;
    final scale =
        math.max(
          targetSize.width / sourceSize.width,
          targetSize.height / sourceSize.height,
        ) *
        safeZoom;
    final displaySize = Size(
      sourceSize.width * scale,
      sourceSize.height * scale,
    );
    final maxX = math.max(0.0, 1 - targetSize.width / displaySize.width);
    final maxY = math.max(0.0, 1 - targetSize.height / displaySize.height);
    final clampedFocalPoint = Alignment(
      focalPoint.x.clamp(-maxX, maxX).toDouble(),
      focalPoint.y.clamp(-maxY, maxY).toDouble(),
    );
    final focalOffset = Offset(
      (clampedFocalPoint.x + 1) * displaySize.width / 2,
      (clampedFocalPoint.y + 1) * displaySize.height / 2,
    );
    return AppBackgroundLayout(
      imageRect: Rect.fromLTWH(
        targetSize.width / 2 - focalOffset.dx,
        targetSize.height / 2 - focalOffset.dy,
        displaySize.width,
        displaySize.height,
      ),
      focalPoint: clampedFocalPoint,
    );
  }
}

@immutable
class AppBackgroundConfig {
  const AppBackgroundConfig({
    required this.source,
    required this.imagePath,
    required this.fit,
    required this.focalPoint,
    required this.zoom,
  });

  final AppBackgroundSource source;
  final String imagePath;
  final AppBackgroundFit fit;
  final Alignment focalPoint;
  final double zoom;

  Object get transitionKey => switch (source) {
    AppBackgroundSource.theme => source,
    AppBackgroundSource.image => (source, imagePath),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBackgroundConfig &&
          source == other.source &&
          imagePath == other.imagePath &&
          fit == other.fit &&
          focalPoint == other.focalPoint &&
          zoom == other.zoom;

  @override
  int get hashCode => Object.hash(source, imagePath, fit, focalPoint, zoom);
}

class AppBackgroundScope extends InheritedWidget {
  const AppBackgroundScope({
    super.key,
    required this.config,
    required this.viewportSize,
    required super.child,
  });

  final AppBackgroundConfig config;
  final Size viewportSize;

  static AppBackgroundScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppBackgroundScope>();

  @override
  bool updateShouldNotify(AppBackgroundScope oldWidget) =>
      config != oldWidget.config || viewportSize != oldWidget.viewportSize;
}

class AppBackgroundFrame extends StatefulWidget {
  const AppBackgroundFrame({
    super.key,
    required this.source,
    required this.imagePath,
    required this.fit,
    this.focalPoint = Alignment.center,
    this.zoom = AppPrefs.defaultBackgroundZoom,
    required this.child,
  });

  final AppBackgroundSource source;
  final String imagePath;
  final AppBackgroundFit fit;
  final Alignment focalPoint;
  final double zoom;
  final Widget child;

  @override
  State<AppBackgroundFrame> createState() => _AppBackgroundFrameState();
}

class _AppBackgroundFrameState extends State<AppBackgroundFrame> {
  final _backdropKey = BackdropKey();

  @override
  Widget build(BuildContext context) {
    final image = widget.source == AppBackgroundSource.image;
    final focalPoint = image && widget.fit == AppBackgroundFit.focalPoint;
    final config = AppBackgroundConfig(
      source: widget.source,
      imagePath: image ? widget.imagePath : '',
      fit: image ? widget.fit : AppBackgroundFit.cover,
      focalPoint: focalPoint ? widget.focalPoint : Alignment.center,
      zoom: focalPoint ? widget.zoom : AppPrefs.defaultBackgroundZoom,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppBackgroundScope(
          config: config,
          viewportSize: constraints.biggest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      fit: StackFit.expand,
                      children: [...previousChildren, ?currentChild],
                    ),
                    child: SizedBox.expand(
                      key: ValueKey(config.transitionKey),
                      child: _AppBackgroundVisual(config: config),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: BackdropGroup(
                  backdropKey: _backdropKey,
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppBackgroundVisual extends StatelessWidget {
  const _AppBackgroundVisual({required this.config});

  final AppBackgroundConfig config;

  @override
  Widget build(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.surface.withValues(alpha: 1);
    return switch (config.source) {
      AppBackgroundSource.theme => ColoredBox(color: fallback),
      AppBackgroundSource.image => _BackgroundImage(
        path: config.imagePath,
        fallback: fallback,
        fit: config.fit,
        focalPoint: config.focalPoint,
        zoom: config.zoom,
      ),
    };
  }
}

/// Gives a pushed translucent route its own moving copy of the app background.
///
/// A desktop route is shorter than the root viewport because the custom title
/// bar stays outside the navigator. Bottom-aligning a full-viewport copy keeps
/// the crop identical without pinning the image against route translation.
class AppRouteBackground extends StatefulWidget {
  const AppRouteBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AppRouteBackground> createState() => _AppRouteBackgroundState();
}

class _AppRouteBackgroundState extends State<AppRouteBackground> {
  final _backdropKey = BackdropKey();

  @override
  Widget build(BuildContext context) {
    final scope = AppBackgroundScope.maybeOf(context);
    if (scope == null ||
        scope.config.source == AppBackgroundSource.theme ||
        scope.viewportSize.isEmpty) {
      return widget.child;
    }
    final viewportSize = scope.viewportSize;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minWidth: viewportSize.width,
              maxWidth: viewportSize.width,
              minHeight: viewportSize.height,
              maxHeight: viewportSize.height,
              child: SizedBox.fromSize(
                size: viewportSize,
                child: _AppBackgroundVisual(config: scope.config),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropGroup(
              backdropKey: _backdropKey,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

ImageProvider<Object> backgroundImageProvider({
  required String path,
  required Size sourceSize,
  required Size displaySize,
  required double devicePixelRatio,
}) {
  final fileImage = FileImage(File(path));
  if (sourceSize.isEmpty || displaySize.isEmpty || devicePixelRatio <= 0) {
    return fileImage;
  }

  const decodeBucket = 256;
  int bucket(double value) =>
      (value / decodeBucket).ceil().clamp(1, 1 << 20) * decodeBucket;

  final width = math.min(
    sourceSize.width.ceil(),
    bucket(displaySize.width * devicePixelRatio),
  );
  final height = math.min(
    sourceSize.height.ceil(),
    bucket(displaySize.height * devicePixelRatio),
  );
  if (width >= sourceSize.width && height >= sourceSize.height) {
    return fileImage;
  }
  return ResizeImage(
    fileImage,
    width: width,
    height: height,
    policy: ResizeImagePolicy.fit,
  );
}

class _BackgroundImage extends StatefulWidget {
  const _BackgroundImage({
    required this.path,
    required this.fallback,
    required this.fit,
    required this.focalPoint,
    required this.zoom,
  });

  final String path;
  final Color fallback;
  final AppBackgroundFit fit;
  final Alignment focalPoint;
  final double zoom;

  @override
  State<_BackgroundImage> createState() => _BackgroundImageState();
}

class _BackgroundImageState extends State<_BackgroundImage> {
  Size? _sourceSize;
  var _loadFailed = false;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _BackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _resolveImage();
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

  @override
  Widget build(BuildContext context) {
    final source = _sourceSize;
    if (source == null || _loadFailed) {
      return ColoredBox(color: widget.fallback);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppBackgroundLayout.resolve(
          sourceSize: source,
          targetSize: constraints.biggest,
          focalPoint: widget.fit == AppBackgroundFit.focalPoint
              ? widget.focalPoint
              : Alignment.center,
          zoom: widget.fit == AppBackgroundFit.focalPoint
              ? widget.zoom
              : AppPrefs.defaultBackgroundZoom,
        );
        final provider = backgroundImageProvider(
          path: widget.path,
          sourceSize: source,
          displaySize: layout.imageRect.size,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        return ColoredBox(
          color: widget.fallback,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fromRect(
                rect: layout.imageRect,
                child: Image(
                  image: provider,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AppBackdropGroup extends StatefulWidget {
  const AppBackdropGroup({super.key, required this.child});

  final Widget child;

  @override
  State<AppBackdropGroup> createState() => _AppBackdropGroupState();
}

class _AppBackdropGroupState extends State<AppBackdropGroup> {
  final _backdropKey = BackdropKey();

  @override
  Widget build(BuildContext context) =>
      BackdropGroup(backdropKey: _backdropKey, child: widget.child);
}

class AppSurfaceBackdrop extends StatelessWidget {
  const AppSurfaceBackdrop({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.surfaceTheme,
    this.grouped = false,
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final AppSurfaceTheme? surfaceTheme;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final sigma = (surfaceTheme ?? AppSurfaceTheme.of(context)).effectiveBlur;
    if (sigma <= 0) return child;
    final filterConfig = ImageFilterConfig.blur(sigmaX: sigma, sigmaY: sigma);
    // Keep mobile filters local so moving surfaces do not share a stale
    // backdrop snapshot. Page bodies no longer use an opacity layer, so the
    // platform-safe srcOver blend is also the correct choice while scrolling.
    final filtered = isMobilePlatform && !grouped
        ? BackdropFilter(filterConfig: filterConfig, child: child)
        : BackdropFilter.grouped(filterConfig: filterConfig, child: child);
    if (borderRadius == BorderRadius.zero) return ClipRect(child: filtered);
    return ClipRRect(borderRadius: borderRadius, child: filtered);
  }
}
