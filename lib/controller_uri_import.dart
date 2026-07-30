import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'screens/settings_screen.dart';

class ControllerUriImporter {
  ControllerUriImporter(
    this._appLinks, {
    required this.store,
    required this.navigatorKey,
  });

  final AppLinks _appLinks;
  final ControllerStore store;
  final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<Uri>? _subscription;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  void start() {
    _subscription ??= _appLinks.uriLinkStream.listen(
      _enqueue,
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) debugPrint('URI Scheme 接收失败：$error');
      },
    );
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _enqueue(Uri uri) {
    if (_disposed) return;
    if (uri.scheme.toLowerCase() != ControllerImportRequest.scheme) return;
    _queue = _queue.then((_) => _handle(uri)).catchError((Object error) {
      if (kDebugMode) debugPrint('URI Scheme 导入失败：$error');
    });
  }

  Future<void> _handle(Uri uri) async {
    ControllerImportRequest request;
    try {
      request = ControllerImportRequest.fromUri(uri);
    } on FormatException catch (error) {
      await _showError(error.message);
      return;
    }

    final navigator = await _navigatorState();
    if (navigator == null || !navigator.mounted) return;
    final draft = await showControllerEditorDialog(
      navigator.context,
      initial: request.draft,
      importMode: true,
    );
    if (draft == null || _disposed) return;

    try {
      await store.addDraft(draft);
    } catch (error) {
      await _showError('保存目标服务失败：$error');
      return;
    }
    if (_disposed) return;
    final currentNavigator = navigatorKey.currentState;
    if (currentNavigator == null || !currentNavigator.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(currentNavigator.context);
    final scheme = Theme.of(currentNavigator.context).colorScheme;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          content: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('已导入目标服务“${draft.name}”')),
            ],
          ),
        ),
      );
  }

  Future<void> _showError(String message) async {
    final navigator = await _navigatorState();
    if (navigator == null || !navigator.mounted) return;
    await showDialog<void>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: const Text('无法导入目标服务'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<NavigatorState?> _navigatorState() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_disposed) return null;
      final navigator = navigatorKey.currentState;
      if (navigator != null) return navigator;
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }
}
