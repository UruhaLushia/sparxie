import 'package:flutter/material.dart';

import '../controller.dart';

class BackendSwitcher extends StatelessWidget {
  const BackendSwitcher({
    super.key,
    required this.store,
    this.textStyle,
    this.typeStyle,
    this.iconColor,
    this.showType = true,
  });

  final ControllerStore store;
  final TextStyle? textStyle;
  final TextStyle? typeStyle;
  final Color? iconColor;
  final bool showType;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final controllers = store.controllers;
        final active = store.active;
        final canSwitch = controllers.length > 1;
        final label = _BackendSwitchLabel(
          controller: active,
          canSwitch: canSwitch,
          textStyle: textStyle,
          typeStyle: typeStyle,
          iconColor: iconColor,
          showType: showType,
        );
        if (!canSwitch) return label;
        return PopupMenuButton<String>(
          tooltip: '切换后端',
          initialValue: active?.id,
          onSelected: (id) {
            if (id != active?.id) store.activate(id);
          },
          itemBuilder: (context) => [
            for (final c in controllers)
              CheckedPopupMenuItem<String>(
                value: c.id,
                checked: c.id == active?.id,
                child: _BackendMenuItem(controller: c),
              ),
          ],
          child: label,
        );
      },
    );
  }
}

class _BackendSwitchLabel extends StatelessWidget {
  const _BackendSwitchLabel({
    required this.controller,
    required this.canSwitch,
    required this.textStyle,
    required this.typeStyle,
    required this.iconColor,
    required this.showType,
  });

  final Controller? controller;
  final bool canSwitch;
  final TextStyle? textStyle;
  final TextStyle? typeStyle;
  final Color? iconColor;
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = controller;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            c?.name ?? '未连接',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        if (showType && c != null) ...[
          const SizedBox(width: 8),
          Text(
            c.type.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                typeStyle ??
                Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (canSwitch) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: iconColor ?? scheme.onSurfaceVariant,
          ),
        ],
      ],
    );
  }
}

class _BackendMenuItem extends StatelessWidget {
  const _BackendMenuItem({required this.controller});

  final Controller controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(controller.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          '${controller.type.label}  ${controller.baseUrl}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
