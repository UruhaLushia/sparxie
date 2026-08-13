import 'package:flutter/material.dart';

import '../controller.dart';
import 'named_avatar.dart';

class BackendAvatar extends StatelessWidget {
  const BackendAvatar({super.key, required this.controller, this.size = 40});

  final Controller controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return NamedAvatar(
      name: controller.name,
      icon: controller.icon,
      size: size,
      fallback: _BackendTypeIcon(type: controller.type, size: size),
      decodeScale: 2.5,
    );
  }
}

class _BackendTypeIcon extends StatelessWidget {
  const _BackendTypeIcon({required this.type, required this.size});

  final BackendType type;
  final double size;

  String get _asset => switch (type) {
    BackendType.clash => 'assets/backend_icons/clash.png',
    BackendType.surge => 'assets/backend_icons/surge.png',
    BackendType.surgeController => 'assets/backend_icons/surge.png',
    BackendType.singBox => 'assets/backend_icons/sing_box.png',
  };

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
