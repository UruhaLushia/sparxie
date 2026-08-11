part of 'theme_settings_screen.dart';

class _BackgroundAlbumTile extends StatelessWidget {
  const _BackgroundAlbumTile({
    required this.paths,
    required this.selectedIndex,
    required this.busy,
    required this.onAdd,
    required this.onSelect,
    required this.onRemove,
    required this.onReorder,
    required this.onClear,
  });

  final List<String> paths;
  final int selectedIndex;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  final ReorderCallback onReorder;
  final VoidCallback? onClear;

  static const _spacing = 10.0;
  static const _preferredExtent = 84.0;
  static const _maxExtent = 96.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('相册图片', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            Text(
              '${paths.length} 张',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            if (onClear != null)
              TextButton.icon(
                onPressed: busy ? null : onClear,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('清空'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (paths.isEmpty)
          _BackgroundAlbumAddButton(
            busy: busy,
            expanded: true,
            onPressed: onAdd,
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = math.max(
                1,
                ((constraints.maxWidth + _spacing) /
                        (_preferredExtent + _spacing))
                    .floor(),
              );
              final dimension = math.min(
                (constraints.maxWidth - _spacing * (columns - 1)) / columns,
                _maxExtent,
              );
              return Wrap(
                spacing: _spacing,
                runSpacing: _spacing,
                children: [
                  for (var index = 0; index < paths.length; index++)
                    _BackgroundAlbumDraggableImage(
                      key: ValueKey(paths[index]),
                      path: paths[index],
                      index: index,
                      dimension: dimension,
                      selected: index == selectedIndex,
                      enabled: !busy,
                      onTap: () => onSelect(index),
                      onRemove: () => onRemove(index),
                      onReorder: onReorder,
                    ),
                  _BackgroundAlbumAddButton(
                    busy: busy,
                    dimension: dimension,
                    onPressed: onAdd,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            '点击切换背景，长按拖动调整顺序',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _BackgroundAlbumAddButton extends StatelessWidget {
  const _BackgroundAlbumAddButton({
    required this.busy,
    required this.onPressed,
    this.expanded = false,
    this.dimension = 84,
  });

  final bool busy;
  final VoidCallback onPressed;
  final bool expanded;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: expanded ? double.infinity : dimension,
      height: dimension,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onPressed,
          child: Center(
            child: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expanded ? '从系统相册添加图片' : '添加',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: scheme.primary),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundAlbumDraggableImage extends StatelessWidget {
  const _BackgroundAlbumDraggableImage({
    super.key,
    required this.path,
    required this.index,
    required this.dimension,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onRemove,
    required this.onReorder,
  });

  final String path;
  final int index;
  final double dimension;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final ReorderCallback onReorder;

  Widget _image() => _BackgroundAlbumImage(
    path: path,
    dimension: dimension,
    selected: selected,
    onTap: onTap,
    onRemove: onRemove,
  );

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => enabled && details.data != index,
      onAcceptWithDetails: (details) => onReorder(details.data, index),
      builder: (context, candidates, _) {
        final image = _image();
        final child = enabled
            ? LongPressDraggable<int>(
                data: index,
                feedback: IgnorePointer(
                  child: Material(
                    type: MaterialType.transparency,
                    child: Transform.scale(scale: 1.04, child: _image()),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.28, child: image),
                child: image,
              )
            : image;
        return AnimatedScale(
          scale: candidates.isEmpty ? 1 : 1.04,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
    );
  }
}

class _BackgroundAlbumImage extends StatelessWidget {
  const _BackgroundAlbumImage({
    required this.path,
    required this.dimension,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final String path;
  final double dimension;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '当前背景' : '设为当前背景',
      child: SizedBox.square(
        dimension: dimension,
        child: Material(
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.4 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image: ResizeImage(
                    FileImage(File(path)),
                    width: 256,
                    height: 256,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                ),
                if (selected)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: IconButton(
                      tooltip: '从相册移除',
                      onPressed: onRemove,
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surface.withValues(alpha: 0.9),
                        foregroundColor: scheme.error,
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
