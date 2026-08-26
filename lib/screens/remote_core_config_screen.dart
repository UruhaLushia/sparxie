import 'package:flutter/material.dart';

import '../controller.dart' as ctl;
import '../widgets/basic_config_panel.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

class RemoteCoreConfigScreen extends StatelessWidget {
  const RemoteCoreConfigScreen({super.key, required this.store});

  final ctl.ControllerStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppRouteAppBar(child: AppBar(title: const Text('核心配置'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [AppPanelSurface(child: BasicConfigPanel(store: store))],
      ),
    );
  }
}
