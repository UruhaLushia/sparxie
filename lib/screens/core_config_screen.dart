import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../controller.dart' as ctl;
import '../widgets/basic_config_panel.dart';

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
      appBar: AppBar(title: const Text('内核配置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
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
