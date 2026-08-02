import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_prefs.dart';
import '../background_image_store.dart';
import '../platform_capabilities.dart';
import '../widgets/app_background.dart';
import '../widgets/app_page_route.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/color_palette_picker.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

part 'background_style_screen.dart';
part 'background_crop_editor.dart';
part 'component_style_screen.dart';
part 'theme_settings_controls.dart';

/// Global theme and per-component appearance settings.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('主题设置'),
          flexibleSpace: const DesktopAppBarDragArea(),
        ),
      ),
      body: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          final automaticColor = prefs.automaticColor;
          final wallpaperColorAvailable =
              prefs.backgroundSource == AppBackgroundSource.image &&
              prefs.backgroundImagePath.isNotEmpty;
          final wallpaperColor =
              wallpaperColorAvailable &&
              prefs.automaticColorSource == AutomaticColorSource.wallpaper;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              SectionPanel(
                title: '主题',
                icon: Icons.palette_outlined,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '主题模式',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ThemeModeSelector(
                      value: prefs.appThemeMode,
                      onChanged: prefs.setAppThemeMode,
                    ),
                    if (supportsCustomTitleBar) ...[
                      const Divider(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '窗口标题栏',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CompactSegmentedButton<DesktopTitleBarMode>(
                        expanded: true,
                        segments: const [
                          ButtonSegment(
                            value: DesktopTitleBarMode.system,
                            label: Text('系统'),
                            icon: Icon(Icons.web_asset_outlined),
                          ),
                          ButtonSegment(
                            value: DesktopTitleBarMode.custom,
                            label: Text('自绘'),
                            icon: Icon(Icons.dashboard_customize_outlined),
                          ),
                          ButtonSegment(
                            value: DesktopTitleBarMode.hidden,
                            label: Text('完全隐藏'),
                            icon: Icon(Icons.visibility_off_outlined),
                          ),
                        ],
                        selected: {prefs.desktopTitleBarMode},
                        onSelectionChanged: (selection) =>
                            prefs.setDesktopTitleBarMode(selection.first),
                      ),
                    ],
                    const Divider(height: 24),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动取色'),
                      subtitle: Text(
                        automaticColor && wallpaperColor
                            ? '基于背景图片生成配色'
                            : '自动生成配色',
                      ),
                      value: automaticColor,
                      onChanged: prefs.setAutomaticColor,
                    ),
                    if (automaticColor && wallpaperColorAvailable) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '取色来源',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CompactSegmentedButton<AutomaticColorSource>(
                        expanded: true,
                        segments: const [
                          ButtonSegment(
                            value: AutomaticColorSource.system,
                            label: Text('系统'),
                            icon: Icon(Icons.devices_outlined),
                          ),
                          ButtonSegment(
                            value: AutomaticColorSource.wallpaper,
                            label: Text('壁纸'),
                            icon: Icon(Icons.wallpaper_outlined),
                          ),
                        ],
                        selected: {prefs.automaticColorSource},
                        onSelectionChanged: (selection) =>
                            prefs.setAutomaticColorSource(selection.first),
                      ),
                    ],
                    const Divider(height: 16),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('纯黑模式'),
                      subtitle: const Text('深色模式下使用 OLED 纯黑背景'),
                      value: prefs.pureBlackMode,
                      onChanged: prefs.setPureBlackMode,
                    ),
                    const Divider(height: 16),
                    CompactSwitch.tile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示分割线'),
                      subtitle: const Text('区分列表和设置项'),
                      value: prefs.showDividers,
                      onChanged: prefs.setShowDividers,
                    ),
                    const Divider(height: 16),
                    _ColorTile(
                      title: '全局主题色',
                      color: Color(prefs.globalThemeColor),
                      enabled: !automaticColor,
                      onTap: () => _pickGlobalColor(context),
                    ),
                    const Divider(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.wallpaper_outlined),
                      title: const Text('背景与表面'),
                      subtitle: Text(_backgroundSummary(prefs)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push<void>(
                        context,
                        AppPageRoute<void>(
                          builder: (_) => BackgroundStyleScreen(prefs: prefs),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: '导航',
                icon: Icons.navigation_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompactSegmentedButton<NavLayout>(
                      expanded: true,
                      segments: const [
                        ButtonSegment(
                          value: NavLayout.cards,
                          label: Text('卡片'),
                          icon: Icon(Icons.dashboard_outlined),
                        ),
                        ButtonSegment(
                          value: NavLayout.standard,
                          label: Text('标准'),
                          icon: Icon(Icons.view_sidebar_outlined),
                        ),
                        ButtonSegment(
                          value: NavLayout.floating,
                          label: Text('悬浮'),
                          icon: Icon(Icons.panorama_fish_eye_outlined),
                        ),
                      ],
                      selected: {prefs.navLayout},
                      onSelectionChanged: (selection) =>
                          prefs.setNavLayout(selection.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '卡片使用页面入口；标准使用底栏或侧栏；悬浮使用圆角悬浮底栏。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionPanel(
                title: '组件',
                icon: Icons.widgets_outlined,
                child: Column(
                  children: [
                    for (
                      var i = 0;
                      i < CompactControlKind.values.length;
                      i++
                    ) ...[
                      _ComponentTile(
                        kind: CompactControlKind.values[i],
                        color: Color(
                          prefs.effectiveCompactThemeColor(
                            CompactControlKind.values[i],
                          ),
                        ),
                        colorEnabled: !automaticColor,
                        followsGlobal: prefs.compactColorFollowsGlobal(
                          CompactControlKind.values[i],
                        ),
                        onTap: () => Navigator.push<void>(
                          context,
                          AppPageRoute<void>(
                            builder: (_) => ComponentStyleScreen(
                              prefs: prefs,
                              kind: CompactControlKind.values[i],
                            ),
                          ),
                        ),
                      ),
                      if (i != CompactControlKind.values.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickGlobalColor(BuildContext context) async {
    final result = await showColorPalettePicker(
      context,
      title: '全局主题色',
      color: Color(prefs.globalThemeColor),
    );
    if (result != null) {
      await prefs.setGlobalThemeColor(result.toARGB32());
    }
  }
}
