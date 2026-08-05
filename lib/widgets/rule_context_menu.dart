import 'package:flutter/material.dart';

import '../rust_api.dart' as rust;
import 'anchored_details_trigger.dart';
import 'rule_details_panel.dart';

class RuleContextMenu extends StatelessWidget {
  const RuleContextMenu({
    super.key,
    required this.rule,
    required this.child,
    this.excludedTopRightSize = Size.zero,
  });

  final rust.RuleEntry rule;
  final Widget child;
  final Size excludedTopRightSize;

  @override
  Widget build(BuildContext context) {
    return AnchoredDetailsTrigger(
      barrierLabel: '关闭规则详情',
      semanticsHint: '长按查看规则详情',
      excludedTopRightSize: excludedTopRightSize,
      excludeChildFocus: true,
      previewInteractive: true,
      detailsBuilder: (_) => RuleDetailsPanel(rule: rule),
      child: child,
    );
  }
}
