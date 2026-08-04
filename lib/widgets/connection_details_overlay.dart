import 'package:flutter/material.dart';

import '../platform_capabilities.dart';
import '../session.dart';
import 'anchored_details_overlay.dart';
import 'connection_detail_sheet.dart';

Future<void> showConnectionDetailsOverlay({
  required BuildContext context,
  required BuildContext sourceContext,
  required ConnectionRow row,
  required Widget preview,
  required bool showConnectionLog,
  required VoidCallback? onClose,
}) async {
  final sourceBox = sourceContext.findRenderObject() as RenderBox?;
  final overlayBox =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()
          as RenderBox?;
  if (sourceBox == null || overlayBox == null || !sourceBox.hasSize) return;

  final sourceRect = Rect.fromPoints(
    sourceBox.localToGlobal(Offset.zero, ancestor: overlayBox),
    sourceBox.localToGlobal(
      sourceBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    ),
  );

  await showAnchoredDetailsOverlay(
    context: context,
    sourceRect: sourceRect,
    preview: preview,
    previewAlwaysAbove: isMobilePlatform,
    preserveSourcePosition: !isMobilePlatform,
    maxDetailsWidth: 760,
    barrierLabel: '关闭连接详情',
    detailsBuilder: (dialogContext) => ConnectionDetailsPanel(
      row: row,
      showConnectionLog: showConnectionLog,
      onClose: onClose == null
          ? null
          : () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
              onClose();
            },
    ),
  );
}
