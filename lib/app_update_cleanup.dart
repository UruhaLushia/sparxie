import 'dart:io';

abstract final class AppUpdateCleanup {
  static const _directoryPrefix = 'sparxie-update-';
  static const _markerName = '.cleanup-pending';
  static const _retryDelay = Duration(seconds: 1);
  static const _maxAttempts = 120;

  static Future<void> markPending(Directory directory) async {
    await File(
      '${directory.path}${Platform.pathSeparator}$_markerName',
    ).create();
  }

  static Future<void> removePending() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;

    List<FileSystemEntity> entries;
    try {
      entries = await Directory.systemTemp
          .list(followLinks: false)
          .where((entry) => entry is Directory && _isUpdateDirectory(entry))
          .toList();
    } on FileSystemException {
      return;
    }
    final pending = await Future.wait(
      entries.cast<Directory>().map((directory) async {
        final marker = File(
          '${directory.path}${Platform.pathSeparator}$_markerName',
        );
        try {
          return await marker.exists() ? directory : null;
        } on FileSystemException {
          return null;
        }
      }),
    );
    await Future.wait(pending.whereType<Directory>().map(_removeWithRetry));
  }

  static bool _isUpdateDirectory(FileSystemEntity entry) {
    final name = entry.path.split(Platform.pathSeparator).last;
    return name.startsWith(_directoryPrefix);
  }

  static Future<void> _removeWithRetry(Directory directory) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        if (!await directory.exists()) return;
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        if (!await directory.exists()) return;
        await Future<void>.delayed(_retryDelay);
      }
    }
  }
}
