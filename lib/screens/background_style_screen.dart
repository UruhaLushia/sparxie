part of 'theme_settings_screen.dart';

String _backgroundSummary(AppPrefs prefs) {
  final source = switch (prefs.backgroundSource) {
    AppBackgroundSource.theme => '主题背景',
    AppBackgroundSource.image => '相册背景',
  };
  if (prefs.backgroundSource == AppBackgroundSource.theme) return source;
  final count = prefs.backgroundImageReferences.length;
  final rotation = prefs.backgroundRotationEnabled && count > 1
      ? ' · 自动轮换'
      : '';
  final effect = switch (prefs.surfaceEffect) {
    AppSurfaceEffect.solid => '透明表面',
    AppSurfaceEffect.blur => '模糊表面',
    AppSurfaceEffect.acrylic => '亚克力表面',
  };
  return '$source · $count 张$rotation · $effect';
}

class BackgroundStyleScreen extends StatefulWidget {
  const BackgroundStyleScreen({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  State<BackgroundStyleScreen> createState() => _BackgroundStyleScreenState();
}

class _BackgroundStyleScreenState extends State<BackgroundStyleScreen> {
  final _imagePicker = ImagePicker();
  final _scrollController = ScrollController();
  var _selectingImage = false;
  double? _surfaceOpacityDraft;
  double? _surfaceBlurDraft;

  AppPrefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) unawaited(_recoverLostImage());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ActiveListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final custom = prefs.backgroundSource != AppBackgroundSource.theme;
        final blurEnabled = prefs.surfaceEffect != AppSurfaceEffect.solid;
        final surfaceOpacity = _surfaceOpacityDraft ?? prefs.surfaceOpacity;
        final surfaceBlur = _surfaceBlurDraft ?? prefs.surfaceBlur;
        final previewSurfaceTheme = AppSurfaceTheme.of(
          context,
        ).copyWith(opacity: surfaceOpacity, blurSigma: surfaceBlur);
        return Scaffold(
          appBar: AppRouteAppBar(
            child: AppBar(
              leading: AppRouteAppBar.leadingOf(context),
              automaticallyImplyLeading: false,
              title: const Text('背景与表面'),
              flexibleSpace: const DesktopAppBarDragArea(),
              actions: [
                TextButton(onPressed: _reset, child: const Text('重置')),
                const SizedBox(width: 8),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth > 792
                    ? (constraints.maxWidth - 760) / 2
                    : 16.0;
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        16,
                        horizontal,
                        0,
                      ),
                      child: RepaintBoundary(
                        child: SizedBox(
                          height: 124,
                          child: _BackgroundPreview(
                            prefs: prefs,
                            surfaceTheme: previewSurfaceTheme,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          0,
                          horizontal,
                          16 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: _BackgroundSettingsScroller(
                          controller: _scrollController,
                          background: _backgroundControls(context),
                          surface: _surfaceControls(
                            context,
                            enabled: custom,
                            blurEnabled: blurEnabled,
                            surfaceOpacity: surfaceOpacity,
                            surfaceBlur: surfaceBlur,
                          ),
                          surfaceEnabled: custom,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _backgroundControls(BuildContext context) {
    return Column(
      children: [
        CompactSegmentedButton<AppBackgroundSource>(
          expanded: true,
          segments: const [
            ButtonSegment(value: AppBackgroundSource.theme, label: Text('主题')),
            ButtonSegment(value: AppBackgroundSource.image, label: Text('相册')),
          ],
          selected: {prefs.backgroundSource},
          onSelectionChanged: (selection) => _setSource(selection.first),
        ),
        if (prefs.backgroundSource == AppBackgroundSource.image) ...[
          const Divider(height: 24),
          _BackgroundAlbumTile(
            paths: prefs.backgroundImagePaths,
            selectedIndex: prefs.backgroundImageIndex,
            busy: _selectingImage,
            onAdd: _selectImages,
            onSelect: prefs.selectBackgroundImage,
            onRemove: _removeImage,
            onReorder: _reorderImage,
            onClear: prefs.backgroundImageReferences.isEmpty
                ? null
                : _clearImages,
          ),
          const Divider(height: 28),
          CompactSwitch.tile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动轮换'),
            subtitle: Text(
              prefs.backgroundImageReferences.length > 1
                  ? '在设定的触发时机切换背景，默认关闭'
                  : '至少添加两张图片后可用',
            ),
            value:
                prefs.backgroundRotationEnabled &&
                prefs.backgroundImageReferences.length > 1,
            onChanged: prefs.backgroundImageReferences.length > 1
                ? prefs.setBackgroundRotationEnabled
                : null,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child:
                prefs.backgroundRotationEnabled &&
                    prefs.backgroundImageReferences.length > 1
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _backgroundRotationControls(context),
                  )
                : const SizedBox.shrink(),
          ),
          const Divider(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('显示方式', style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          CompactSegmentedButton<AppBackgroundFit>(
            expanded: true,
            segments: [
              const ButtonSegment(
                value: AppBackgroundFit.cover,
                label: Text('居中填充'),
              ),
              ButtonSegment(
                value: AppBackgroundFit.focalPoint,
                label: Text(isMobilePlatform ? '框选区域' : '视觉中心'),
              ),
            ],
            selected: {prefs.backgroundFit},
            onSelectionChanged: (selection) =>
                prefs.setBackgroundFit(selection.first),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: prefs.backgroundFit == AppBackgroundFit.focalPoint
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _BackgroundFocalPointTile(
                      path: prefs.backgroundImagePath,
                      mobile: isMobilePlatform,
                      focalPoint: Alignment(
                        prefs.backgroundFocalX,
                        prefs.backgroundFocalY,
                      ),
                      zoom: prefs.backgroundZoom,
                      onTap: () => _editFocalPoint(context),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }

  Widget _backgroundRotationControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('触发条件', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        CompactSegmentedButton<BackgroundRotationTrigger>(
          expanded: true,
          segments: [
            const ButtonSegment(
              value: BackgroundRotationTrigger.appLaunch,
              icon: Icon(Icons.restart_alt_rounded),
              label: Text('重新启动'),
            ),
            ButtonSegment(
              value: BackgroundRotationTrigger.appResume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(isDesktopPlatform ? '最小化恢复' : '恢复前台'),
            ),
          ],
          selected: {prefs.backgroundRotationTrigger},
          onSelectionChanged: (selection) =>
              prefs.setBackgroundRotationTrigger(selection.first),
        ),
        const SizedBox(height: 14),
        Text('轮换顺序', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        CompactSegmentedButton<BackgroundRotationOrder>(
          expanded: true,
          segments: const [
            ButtonSegment(
              value: BackgroundRotationOrder.sequential,
              icon: Icon(Icons.arrow_forward_rounded),
              label: Text('相册顺序'),
            ),
            ButtonSegment(
              value: BackgroundRotationOrder.random,
              icon: Icon(Icons.shuffle_rounded),
              label: Text('随机顺序'),
            ),
          ],
          selected: {prefs.backgroundRotationOrder},
          onSelectionChanged: (selection) =>
              prefs.setBackgroundRotationOrder(selection.first),
        ),
      ],
    );
  }

  Widget _surfaceControls(
    BuildContext context, {
    required bool enabled,
    required bool blurEnabled,
    required double surfaceOpacity,
    required double surfaceBlur,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          children: [
            CompactSegmentedButton<AppSurfaceEffect>(
              expanded: true,
              segments: const [
                ButtonSegment(value: AppSurfaceEffect.solid, label: Text('透明')),
                ButtonSegment(value: AppSurfaceEffect.blur, label: Text('模糊')),
                ButtonSegment(
                  value: AppSurfaceEffect.acrylic,
                  label: Text('亚克力'),
                ),
              ],
              selected: {prefs.surfaceEffect},
              onSelectionChanged: (selection) =>
                  prefs.setSurfaceEffect(selection.first),
            ),
            const SizedBox(height: 14),
            _StyleSlider(
              label: '组件透明度',
              valueLabel: '${((1 - surfaceOpacity) * 100).round()}%',
              value: 1 - surfaceOpacity,
              min: 0,
              max: 0.95,
              divisions: 95,
              onChanged: (value) =>
                  setState(() => _surfaceOpacityDraft = 1 - value),
              onChangeEnd: (value) => _commitSurfaceOpacity(1 - value),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: blurEnabled
                  ? _StyleSlider(
                      label: '模糊强度',
                      valueLabel: surfaceBlur.round().toString(),
                      value: surfaceBlur,
                      min: 0,
                      max: 40,
                      divisions: 40,
                      onChanged: (value) =>
                          setState(() => _surfaceBlurDraft = value),
                      onChangeEnd: _commitSurfaceBlur,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setSource(AppBackgroundSource source) async {
    if (source == AppBackgroundSource.image &&
        prefs.backgroundImagePath.isEmpty) {
      await _selectImages();
      return;
    }
    await prefs.setBackgroundSource(source);
  }

  Future<void> _commitSurfaceOpacity(double value) async {
    await prefs.setSurfaceOpacity(value);
    if (mounted) setState(() => _surfaceOpacityDraft = null);
  }

  Future<void> _commitSurfaceBlur(double value) async {
    await prefs.setSurfaceBlur(value);
    if (mounted) setState(() => _surfaceBlurDraft = null);
  }

  Future<void> _editFocalPoint(BuildContext context) async {
    final initial = Alignment(prefs.backgroundFocalX, prefs.backgroundFocalY);
    final initialZoom = prefs.backgroundZoom;
    final windowSize = MediaQuery.sizeOf(context);
    final targetAspectRatio = windowSize.aspectRatio;
    final scheme = Theme.of(context).colorScheme;
    final _BackgroundViewport? result;
    if (isMobilePlatform) {
      result = await showModalBottomSheet<_BackgroundViewport>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: scheme.surfaceContainerHigh,
        barrierColor: Colors.black.withValues(alpha: 0.56),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => SizedBox(
          height: windowSize.height * 0.88,
          child: _BackgroundFocalPointEditor(
            path: prefs.backgroundImagePath,
            initial: initial,
            initialZoom: initialZoom,
            mobile: true,
            targetAspectRatio: targetAspectRatio,
          ),
        ),
      );
    } else {
      result = await showDialog<_BackgroundViewport>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.56),
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: scheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: (windowSize.height - 48).clamp(0, 600),
            ),
            child: _BackgroundFocalPointEditor(
              path: prefs.backgroundImagePath,
              initial: initial,
              initialZoom: initialZoom,
              mobile: false,
              targetAspectRatio: targetAspectRatio,
            ),
          ),
        ),
      );
    }
    if (result == null || !mounted) return;
    await prefs.setBackgroundViewport(
      result.focalPoint.x,
      result.focalPoint.y,
      result.zoom,
    );
  }

  Future<void> _selectImages() async {
    if (_selectingImage) return;
    setState(() => _selectingImage = true);
    try {
      final files = isMobilePlatform
          ? await _imagePicker.pickMultiImage(requestFullMetadata: false)
          : await openFiles(
              acceptedTypeGroups: const [
                XTypeGroup(
                  label: 'Images',
                  extensions: [
                    'bmp',
                    'gif',
                    'heic',
                    'heif',
                    'jpeg',
                    'jpg',
                    'png',
                    'webp',
                  ],
                  uniformTypeIdentifiers: ['public.image'],
                ),
              ],
            );
      if (files.isEmpty || !mounted) return;
      await _importImages(files);
    } catch (error) {
      _showImageImportError(error);
    } finally {
      if (mounted) setState(() => _selectingImage = false);
    }
  }

  Future<void> _recoverLostImage() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty || !mounted) return;
      final files = response.files;
      if (files == null || files.isEmpty) {
        throw response.exception ?? StateError('无法恢复上次选择的图片');
      }
      setState(() => _selectingImage = true);
      await _importImages(files);
    } catch (error) {
      _showImageImportError(error);
    } finally {
      if (mounted && _selectingImage) {
        setState(() => _selectingImage = false);
      }
    }
  }

  Future<void> _importImages(Iterable<XFile> files) async {
    final imported = <String>[];
    try {
      for (final file in files) {
        final path = await BackgroundImageStore.importStream(
          file.name,
          file.openRead(),
        );
        imported.add(path);
        await BackgroundImageStore.imageSize(path);
      }
      await prefs.useBackgroundImages(imported);
    } catch (_) {
      await _deleteManagedImages(imported);
      rethrow;
    }
  }

  void _showImageImportError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('背景图片导入失败：$error')));
  }

  Future<void> _removeImage(int index) async {
    if (index < 0 || index >= prefs.backgroundImageReferences.length) return;
    final confirmed = await _confirmDestructiveAction(
      title: '移除背景图片',
      message: '确定从背景相册中移除这张图片吗？\n已导入的图片文件也会被删除，此操作无法撤销。',
      action: '移除',
    );
    if (!confirmed || !mounted) return;
    final paths = prefs.backgroundImagePaths;
    if (index < 0 || index >= paths.length) return;
    final path = paths[index];
    await prefs.removeBackgroundImage(index);
    await BackgroundImageStore.deleteManaged(path);
  }

  Future<void> _reorderImage(int oldIndex, int newIndex) =>
      prefs.reorderBackgroundImage(oldIndex, newIndex);

  Future<void> _clearImages() async {
    final count = prefs.backgroundImageReferences.length;
    if (count == 0) return;
    final confirmed = await _confirmDestructiveAction(
      title: '清空背景相册',
      message: '确定清空全部 $count 张背景图片吗？\n已导入的图片文件也会被删除，此操作无法撤销。',
      action: '清空',
    );
    if (!confirmed || !mounted) return;
    final paths = prefs.backgroundImagePaths;
    await prefs.clearBackgroundImage();
    await _deleteManagedImages(paths);
  }

  Future<bool> _confirmDestructiveAction({
    required String title,
    required String message,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteManagedImages(Iterable<String> paths) async {
    for (final path in paths) {
      await BackgroundImageStore.deleteManaged(path);
    }
  }

  Future<void> _reset() async {
    final paths = prefs.backgroundImagePaths;
    if (paths.isNotEmpty) {
      final confirmed = await _confirmDestructiveAction(
        title: '重置背景与表面',
        message: '确定重置所有背景与表面设置吗？\n背景相册中的 ${paths.length} 张图片也会被删除，此操作无法撤销。',
        action: '重置',
      );
      if (!confirmed || !mounted) return;
    }
    _surfaceOpacityDraft = null;
    _surfaceBlurDraft = null;
    await prefs.resetBackgroundStyle();
    await _deleteManagedImages(paths);
  }
}

class _BackgroundSettingsScroller extends StatefulWidget {
  const _BackgroundSettingsScroller({
    required this.controller,
    required this.background,
    required this.surface,
    required this.surfaceEnabled,
  });

  final ScrollController controller;
  final Widget background;
  final Widget surface;
  final bool surfaceEnabled;

  @override
  State<_BackgroundSettingsScroller> createState() =>
      _BackgroundSettingsScrollerState();
}

class _BackgroundSettingsScrollerState
    extends State<_BackgroundSettingsScroller> {
  static const _headerExtent = 62.0;
  static const _sectionGap = 16.0;

  final _backgroundKey = GlobalKey();
  double _backgroundExtent = 0;
  var _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  double _heightOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size.height : 0;
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final backgroundExtent = _heightOf(_backgroundKey);
      if ((backgroundExtent - _backgroundExtent).abs() < 0.5) {
        return;
      }
      setState(() => _backgroundExtent = backgroundExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaceTheme = AppSurfaceTheme.of(context);
    final headerColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: surfaceTheme.enabled ? 0.14 : 0.08),
      scheme.surfaceContainerHigh.withValues(alpha: 1),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _scheduleMeasure();
              return false;
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView(
                controller: widget.controller,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.zero,
                children: [
                  _SettingsSectionCard(
                    title: '背景',
                    icon: Icons.wallpaper_outlined,
                    headerColor: headerColor,
                    body: SizeChangedLayoutNotifier(
                      child: Padding(
                        key: _backgroundKey,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                        child: widget.background,
                      ),
                    ),
                  ),
                  const SizedBox(height: _sectionGap),
                  _SettingsSectionCard(
                    title: '上层组件',
                    icon: Icons.layers_outlined,
                    headerColor: headerColor,
                    enabled: widget.surfaceEnabled,
                    body: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      child: widget.surface,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: _headerExtent,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final offset = widget.controller.hasClients
                    ? widget.controller.offset
                    : 0.0;
                final transitionStart = _backgroundExtent + _sectionGap;
                final progress = _backgroundExtent <= 0
                    ? 0.0
                    : ((offset - transitionStart) / _headerExtent).clamp(
                        0.0,
                        1.0,
                      );
                final elevation = (offset / 20).clamp(0.0, 1.0);
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.translate(
                        offset: Offset(0, -_headerExtent * progress),
                        child: CompactSettingsPanelHeader(
                          title: '背景',
                          icon: Icons.wallpaper_outlined,
                          backgroundColor: headerColor,
                          elevation: elevation,
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, _headerExtent * (1 - progress)),
                        child: CompactSettingsPanelHeader(
                          title: '上层组件',
                          icon: Icons.layers_outlined,
                          backgroundColor: headerColor,
                          elevation: elevation,
                          enabled: widget.surfaceEnabled,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.icon,
    required this.headerColor,
    required this.body,
    this.enabled = true,
  });

  final String title;
  final IconData icon;
  final Color headerColor;
  final Widget body;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final surfaceTheme = AppSurfaceTheme.of(context);
    return CompactSettingsPanel(
      surfaceTheme: surfaceTheme,
      header: CompactSettingsPanelHeader(
        title: title,
        icon: icon,
        backgroundColor: headerColor,
        enabled: enabled,
      ),
      child: body,
    );
  }
}

class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.prefs, required this.surfaceTheme});

  final AppPrefs prefs;
  final AppSurfaceTheme surfaceTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(22));
    return ClipRRect(
      borderRadius: radius,
      child: AppBackgroundFrame(
        source: prefs.backgroundSource,
        imagePath: prefs.backgroundImagePath,
        fit: prefs.backgroundFit,
        focalPoint: Alignment(prefs.backgroundFocalX, prefs.backgroundFocalY),
        zoom: prefs.backgroundZoom,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              AppSurfaceBackdrop(
                borderRadius: BorderRadius.circular(12),
                surfaceTheme: surfaceTheme,
                grouped: true,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: surfaceTheme.surfaceColor(
                      scheme.surfaceContainerHigh,
                      0.03,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.palette_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('表面效果预览'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _PreviewCard(
                        surfaceTheme: surfaceTheme,
                        color: surfaceTheme.surfaceColor(
                          scheme.primaryContainer,
                          0.08,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PreviewCard(
                        surfaceTheme: surfaceTheme,
                        color: surfaceTheme.surfaceColor(
                          scheme.surfaceContainerHighest,
                          0.06,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.color, required this.surfaceTheme});

  final Color color;
  final AppSurfaceTheme surfaceTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurfaceBackdrop(
      borderRadius: BorderRadius.circular(14),
      surfaceTheme: surfaceTheme,
      grouped: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: surfaceTheme.outlineBorder(scheme.outlineVariant),
        ),
        child: const Center(child: Icon(Icons.widgets_outlined)),
      ),
    );
  }
}
