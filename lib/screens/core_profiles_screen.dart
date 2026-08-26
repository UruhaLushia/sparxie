import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../rust_api.dart' as rust;
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

class CoreProfilesScreen extends StatefulWidget {
  const CoreProfilesScreen({super.key});

  @override
  State<CoreProfilesScreen> createState() => _CoreProfilesScreenState();
}

class _CoreProfilesScreenState extends State<CoreProfilesScreen> {
  List<rust.CoreConfigProfile> _profiles = const [];
  String _loadError = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final profiles = await rust.coreConfigList();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _loadError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('配置管理'),
          flexibleSpace: const DesktopAppBarDragArea(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            MaxWidthContent(
              maxWidth: 720,
              child: SectionPanel(
                title: '内核配置',
                icon: Icons.tune_outlined,
                trailing: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _import(context),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('导入'),
                ),
                child: _profileList(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileList(BuildContext context) {
    if (_profiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          _loadError.isEmpty ? '暂无配置' : '读取失败：$_loadError',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _profiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _ProfileTile(
            profile: _profiles[i],
            onActivate: _profiles[i].active
                ? null
                : () => _activate(_profiles[i].id),
            onRename: _profiles[i].kind == rust.CoreProfileKind.imported
                ? () => _edit(_profiles[i])
                : null,
            onUpdate: _profiles[i].sourceUrl.isNotEmpty
                ? () => _update(_profiles[i])
                : null,
            onDelete: _profiles[i].kind == rust.CoreProfileKind.imported
                ? () => _delete(_profiles[i])
                : null,
          ),
        ],
      ],
    );
  }

  Future<void> _import(BuildContext context) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final uaController = TextEditingController();
    var sourceType = 'remote';
    var fileContent = '';
    var fileName = '';
    final result =
        await showDialog<({String url, String text, String name, String ua})>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final segmentedStyle = CompactControlTheme.segmentedOf(
                context,
              ).copyWith(backgroundColor: Colors.transparent);
              final fileButtonStyle = CompactControlTheme.buttonOf(
                context,
              ).copyWith(foregroundColor: theme.colorScheme.primary);
              final cancelButtonStyle = CompactControlTheme.buttonOf(
                context,
              ).copyWith(backgroundColor: Colors.transparent);
              final importButtonStyle = CompactControlTheme.buttonOf(context)
                  .copyWith(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  );
              final canImport = sourceType != 'local' || fileContent.isNotEmpty;
              return AlertDialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                constraints: const BoxConstraints.tightFor(width: 420),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                scrollable: true,
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                title: const Text('导入内核配置'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    CompactSegmentedButton<String>(
                      expanded: true,
                      style: segmentedStyle,
                      segments: const [
                        ButtonSegment(value: 'local', label: Text('本地')),
                        ButtonSegment(value: 'remote', label: Text('远程')),
                      ],
                      selected: {sourceType},
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          setDialogState(() => sourceType = selection.first);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (sourceType == 'remote')
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: '订阅地址 (URL)',
                          hintText: 'https://example.com/sub.yaml',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    if (sourceType == 'local') ...[
                      Row(
                        children: [
                          CompactButton(
                            semanticLabel: '选择文件',
                            outlined: true,
                            style: fileButtonStyle,
                            onPressed: () async {
                              final file = await openFile(
                                acceptedTypeGroups: const [
                                  XTypeGroup(
                                    label: 'Config files',
                                    extensions: ['yaml', 'yml', 'txt', 'conf'],
                                  ),
                                  XTypeGroup(label: 'All files'),
                                ],
                              );
                              if (file == null) return;
                              final content = await file.readAsString();
                              if (!context.mounted) return;
                              setDialogState(() {
                                fileContent = content;
                                fileName = file.name;
                              });
                            },
                            icon: const Icon(Icons.folder_open),
                            label: '选择文件',
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              fileName.isEmpty ? '未选择文件' : fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (sourceType == 'remote')
                      TextField(
                        controller: uaController,
                        decoration: const InputDecoration(
                          labelText: '下载 UA',
                          hintText: '留空使用默认 (clash.meta/版本)',
                        ),
                      ),
                  ],
                ),
                actions: [
                  CompactButton(
                    semanticLabel: '取消导入',
                    style: cancelButtonStyle,
                    onPressed: () => Navigator.of(context).pop(),
                    label: '取消',
                  ),
                  CompactButton(
                    semanticLabel: '导入配置',
                    style: importButtonStyle,
                    onPressed: canImport
                        ? () => Navigator.of(context).pop((
                            url: urlController.text.trim(),
                            text: sourceType == 'local' ? fileContent : '',
                            name: nameController.text.trim(),
                            ua: uaController.text.trim(),
                          ))
                        : null,
                    label: '导入',
                  ),
                ],
              );
            },
          ),
        );
    nameController.dispose();
    urlController.dispose();
    uaController.dispose();
    if (result == null) return;
    try {
      await rust.coreConfigImport(
        url: result.url,
        text: result.text,
        name: result.name,
        userAgent: result.ua,
      );
      await _reload();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  Future<void> _activate(String id) async {
    try {
      await rust.coreConfigSetActive(id: id);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('切换失败：$e')));
      }
    }
  }

  Future<void> _edit(rust.CoreConfigProfile profile) async {
    final nameController = TextEditingController(text: profile.name);
    final urlController = TextEditingController(text: profile.sourceUrl);
    final uaController = TextEditingController(text: profile.userAgent);
    final result = await showDialog<({String name, String url, String ua})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '订阅地址 (URL)',
                hintText: '留空则仅保存名称',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: uaController,
              decoration: const InputDecoration(
                labelText: '下载 UA',
                hintText: '留空使用默认 (clash.meta/版本)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              name: nameController.text.trim(),
              url: urlController.text.trim(),
              ua: uaController.text.trim(),
            )),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameController.dispose();
    urlController.dispose();
    uaController.dispose();
    if (result == null || result.name.isEmpty) return;
    try {
      await rust.coreConfigEdit(
        id: profile.id,
        name: result.name,
        url: result.url,
        userAgent: result.ua,
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('修改失败：$e')));
      }
    }
  }

  Future<void> _update(rust.CoreConfigProfile profile) async {
    try {
      await rust.coreConfigUpdate(id: profile.id);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配置已更新')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失败：$e')));
      }
    }
  }

  Future<void> _delete(rust.CoreConfigProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定删除“${profile.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await rust.coreConfigDelete(id: profile.id);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.onActivate,
    required this.onRename,
    required this.onUpdate,
    required this.onDelete,
  });

  final rust.CoreConfigProfile profile;
  final VoidCallback? onActivate;
  final VoidCallback? onRename;
  final VoidCallback? onUpdate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final builtin = profile.kind == rust.CoreProfileKind.builtin;
    return ListTile(
      dense: true,
      minTileHeight: 60,
      minLeadingWidth: 36,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 2),
      tileColor: profile.active
          ? scheme.primaryContainer.withValues(alpha: 0.22)
          : scheme.surfaceContainerHigh.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(
        profile.active
            ? Icons.check_circle_rounded
            : builtin
            ? Icons.lock_outline_rounded
            : Icons.layers_outlined,
        size: 22,
        color: profile.active ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        profile.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: profile.active ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: profile.sourceUrl.isNotEmpty
          ? Text(
              profile.sourceUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : builtin
          ? Text(
              '内置',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: PopupMenuButton<String>(
        tooltip: '操作',
        onSelected: (action) {
          switch (action) {
            case 'edit':
              onRename?.call();
            case 'update':
              onUpdate?.call();
            case 'delete':
              onDelete?.call();
          }
        },
        itemBuilder: (context) => [
          if (onRename != null)
            const PopupMenuItem(value: 'edit', child: Text('编辑信息')),
          if (onUpdate != null)
            const PopupMenuItem(value: 'update', child: Text('更新配置')),
          if (onDelete != null)
            const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
        icon: Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: onActivate,
    );
  }
}
