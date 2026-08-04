import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../platform_capabilities.dart';
import '../session.dart';
import 'anchored_details_overlay.dart';
import 'connection_detail_sheet.dart';

typedef ConnectionPreviewBuilder =
    Widget Function(ConnectionRow row, ValueListenable<int> timeTicks);

Future<void> showConnectionDetailsOverlay({
  required BuildContext context,
  required BuildContext sourceContext,
  required MihomoSession session,
  required ConnectionRow row,
  required ConnectionPreviewBuilder previewBuilder,
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

  final liveRow = ConnectionRow.detached(row);
  final updater = _LiveConnectionUpdater(session: session, row: liveRow)
    ..start();
  try {
    await showAnchoredDetailsOverlay(
      context: context,
      sourceRect: sourceRect,
      preview: previewBuilder(liveRow, updater.timeTicks),
      previewAlwaysAbove: isMobilePlatform,
      preserveSourcePosition: !isMobilePlatform,
      maxDetailsWidth: 760,
      barrierLabel: '关闭连接详情',
      detailsBuilder: (dialogContext) => ConnectionDetailsPanel(
        row: liveRow,
        timeTicks: updater.timeTicks,
        showConnectionLog: showConnectionLog,
        onClose: onClose == null
            ? null
            : () {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                onClose();
              },
      ),
    );
  } finally {
    updater.dispose();
    liveRow.dispose();
  }
}

class _LiveConnectionUpdater with WidgetsBindingObserver {
  _LiveConnectionUpdater({required this.session, required this.row});

  final MihomoSession session;
  final ConnectionRow row;
  final ValueNotifier<int> _timeTicks = ValueNotifier(0);

  Timer? _refreshTimer;
  Timer? _clockTimer;
  var _fetching = false;
  var _disposed = false;

  ValueListenable<int> get timeTicks => _timeTicks;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_canUpdate) _timeTicks.value++;
    });
    _refreshTimer = Timer.periodic(
      Duration(milliseconds: session.connectionsIntervalMs),
      (_) => unawaited(_refresh()),
    );
    unawaited(_refresh());
  }

  bool get _canUpdate {
    if (_disposed) return false;
    return switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
      _ => true,
    };
  }

  Future<void> _refresh() async {
    if (!_canUpdate || _fetching) return;
    _fetching = true;
    try {
      final stats = await session.fetchConnectionStats(row.id);
      if (!_disposed && stats != null) row.updateStats(stats);
    } catch (_) {
      // The next connection frame retries; transient controller changes are
      // not surfaced as a modal error.
    } finally {
      _fetching = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_canUpdate) return;
    _timeTicks.value++;
    unawaited(_refresh());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _timeTicks.dispose();
  }
}
