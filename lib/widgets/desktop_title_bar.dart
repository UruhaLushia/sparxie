import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../platform_capabilities.dart';
import 'app_background.dart';

class DesktopTitleBarFrame extends StatefulWidget {
  const DesktopTitleBarFrame({
    super.key,
    required this.showTitleBar,
    required this.enableContentDragging,
    required this.child,
  });

  final bool showTitleBar;
  final bool enableContentDragging;
  final Widget child;

  @override
  State<DesktopTitleBarFrame> createState() => _DesktopTitleBarFrameState();
}

class _DesktopTitleBarFrameState extends State<DesktopTitleBarFrame>
    with WindowListener {
  var _maximized = false;
  var _fullScreen = false;
  var _listening = false;

  @override
  void initState() {
    super.initState();
    _updateListener();
  }

  @override
  void didUpdateWidget(DesktopTitleBarFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showTitleBar != widget.showTitleBar ||
        oldWidget.enableContentDragging != widget.enableContentDragging) {
      _updateListener();
    }
  }

  @override
  void dispose() {
    if (_listening) windowManager.removeListener(this);
    super.dispose();
  }

  void _updateListener() {
    final shouldListen =
        supportsCustomTitleBar &&
        (widget.showTitleBar || widget.enableContentDragging);
    if (shouldListen == _listening) return;
    _listening = shouldListen;
    if (shouldListen) {
      windowManager.addListener(this);
      unawaited(_syncWindowState());
    } else {
      windowManager.removeListener(this);
    }
  }

  Future<void> _syncWindowState() async {
    final (maximized, fullScreen) = await (
      windowManager.isMaximized(),
      windowManager.isFullScreen(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _maximized = maximized;
      _fullScreen = fullScreen;
    });
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowEnterFullScreen() => setState(() => _fullScreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullScreen = false);

  @override
  Widget build(BuildContext context) {
    final contentDragging =
        supportsCustomTitleBar && widget.enableContentDragging && !_fullScreen;
    final content =
        !supportsCustomTitleBar || !widget.showTitleBar || _fullScreen
        ? widget.child
        : isMacOSPlatform
        ? _MacCustomTitleBar(child: widget.child)
        : _CustomTitleBar(maximized: _maximized, child: widget.child);
    return _DesktopTitleBarScope(
      contentDragging: contentDragging,
      child: content,
    );
  }
}

class _MacCustomTitleBar extends StatefulWidget {
  const _MacCustomTitleBar({required this.child});

  final Widget child;

  @override
  State<_MacCustomTitleBar> createState() => _MacCustomTitleBarState();
}

class _MacCustomTitleBarState extends State<_MacCustomTitleBar> {
  static const _fallbackHeight = 28.0;

  var _height = _fallbackHeight;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTitleBarHeight());
  }

  Future<void> _loadTitleBarHeight() async {
    try {
      final height = await windowManager.getTitleBarHeight();
      if (!mounted || height <= 0) return;
      setState(() => _height = height.toDouble());
    } catch (_) {
      // Keep the standard logical-point fallback if native sizing is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: AppSurfaceBackdrop(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceTheme.chromeColor(scheme.surface),
                border: Border(
                  bottom: surfaceTheme.outlineSide(
                    scheme.outlineVariant.withValues(alpha: 0.65),
                  ),
                ),
              ),
              child: SizedBox.expand(
                child: DragToMoveArea(
                  child: Padding(
                    // Leave the native traffic lights a clear hit target.
                    padding: const EdgeInsets.only(left: 88, right: 16),
                    child: Center(
                      child: Text(
                        'Sparxie',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Route transitions and composited background followers may transform
        // beyond their layout bounds. Keep them below the window chrome.
        Expanded(child: ClipRect(child: widget.child)),
      ],
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
  const _CustomTitleBar({required this.maximized, required this.child});

  final bool maximized;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final brightness = theme.brightness;
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: AppSurfaceBackdrop(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceTheme.chromeColor(scheme.surface),
                border: Border(
                  bottom: surfaceTheme.outlineSide(
                    scheme.outlineVariant.withValues(alpha: 0.65),
                  ),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DragToMoveArea(
                      child: Center(
                        child: Text(
                          'Sparxie',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WindowCaptionButton.minimize(
                          brightness: brightness,
                          onPressed: windowManager.minimize,
                        ),
                        if (maximized)
                          WindowCaptionButton.unmaximize(
                            brightness: brightness,
                            onPressed: windowManager.unmaximize,
                          )
                        else
                          WindowCaptionButton.maximize(
                            brightness: brightness,
                            onPressed: windowManager.maximize,
                          ),
                        WindowCaptionButton.close(
                          brightness: brightness,
                          onPressed: windowManager.close,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Route transitions and composited background followers may transform
        // beyond their layout bounds. Keep them below the window chrome.
        Expanded(child: ClipRect(child: child)),
      ],
    );
  }
}

/// Place behind an AppBar's toolbar so only its unused area starts dragging.
class DesktopAppBarDragArea extends StatelessWidget {
  const DesktopAppBarDragArea({super.key});

  @override
  Widget build(BuildContext context) {
    final child = _DesktopTitleBarScope.contentDraggingOf(context)
        ? const DragToMoveArea(child: SizedBox.expand())
        : const SizedBox.expand();
    return AppSurfaceBackdrop(child: child);
  }
}

class _DesktopTitleBarScope extends InheritedWidget {
  const _DesktopTitleBarScope({
    required this.contentDragging,
    required super.child,
  });

  final bool contentDragging;

  static bool contentDraggingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_DesktopTitleBarScope>()
          ?.contentDragging ??
      false;

  @override
  bool updateShouldNotify(_DesktopTitleBarScope oldWidget) =>
      contentDragging != oldWidget.contentDragging;
}
