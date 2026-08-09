import 'package:flutter/material.dart';

import '../session.dart';
import 'anchored_details_trigger.dart';
import 'proxy_node_details_panel.dart';

class ProxyNodeContextMenu extends StatelessWidget {
  const ProxyNodeContextMenu({
    super.key,
    this.group,
    required this.member,
    this.loadDetails,
    this.onTestDelay,
    this.onToggleFixed,
    this.onActivate,
    this.requireFullyVisible = false,
    required this.child,
  });

  final ProxyGroup? group;
  final ProxyMember member;
  final ProxyNodeDetailsLoader? loadDetails;
  final Future<void> Function()? onTestDelay;
  final VoidCallback? onToggleFixed;
  final VoidCallback? onActivate;
  final bool requireFullyVisible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canFix = (group?.canFixMembers ?? false) && onToggleFixed != null;
    return AnchoredDetailsTrigger(
      barrierLabel: '关闭节点详情',
      semanticsHint: '长按打开节点菜单',
      onActivate: onActivate,
      requireFullyVisible: requireFullyVisible,
      detailsBuilder: (dialogContext) => ProxyNodeDetailsPanel(
        group: group,
        member: member,
        loadDetails: loadDetails,
        onTestDelay: onTestDelay,
        onToggleFixed: canFix
            ? () {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                onToggleFixed!();
              }
            : null,
      ),
      child: ExcludeFocus(child: child),
    );
  }
}
