import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../widgets/basic_config_panel.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

class CoreConfigScreen extends StatelessWidget {
  const CoreConfigScreen({super.key, required this.store, this.prefs});

  final ctl.ControllerStore store;

  /// Optional prefs reference. When provided and the cards layout is active,
  /// the 出站模式 section is hidden because the launcher already exposes it
  /// as a dedicated card.
  final AppPrefs? prefs;

  @override
  Widget build(BuildContext context) {
    final hideMode = prefs?.navLayout == NavLayout.cards;
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('核心配置'),
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
              child: BasicConfigPanel(
                store: store,
                showOutboundMode: !hideMode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
