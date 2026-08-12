import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_update.dart';
import 'app_update_cleanup.dart';
import 'app_update_http.dart';

enum AppUpdateStage { downloading, verifying, launchingInstaller }

class AppUpdateProgress {
  const AppUpdateProgress(this.stage, {this.fraction});

  final AppUpdateStage stage;
  final double? fraction;
}

enum AppUpdateLaunch { keepRunning, closeApplication }

abstract final class AppUpdateInstaller {
  static const _helperReadyMarker = '.helper-ready';
  static const _helperFailedMarker = '.helper-failed';
  static const _windowsHelperReadyTimeout = Duration(seconds: 5);
  static const _macOSHelperReadyTimeout = Duration(minutes: 5);
  static const _androidInstallerChannel = MethodChannel(
    'zip.atri.sparxie/update_installer',
  );

  static bool get isSupported =>
      Platform.isAndroid || Platform.isWindows || Platform.isMacOS;

  static Future<AppUpdateLaunch> install(
    AppUpdateAsset asset, {
    required void Function(AppUpdateProgress progress) onProgress,
    String githubToken = '',
  }) {
    if (Platform.isAndroid) {
      return _installAndroid(asset, onProgress, githubToken);
    }
    if (Platform.isWindows || Platform.isMacOS) {
      return _installDesktop(asset, onProgress, githubToken);
    }
    throw const AppUpdateException('当前平台暂不支持应用内安装');
  }

  static Future<AppUpdateLaunch> _installAndroid(
    AppUpdateAsset asset,
    void Function(AppUpdateProgress progress) onProgress,
    String githubToken,
  ) async {
    bool? permission;
    try {
      permission = await _androidInstallerChannel.invokeMethod<bool>(
        'requestInstallPermission',
      );
    } on PlatformException catch (error) {
      throw AppUpdateException('无法检查安装权限${_platformErrorDetail(error)}');
    }
    if (permission != true) {
      throw const AppUpdateException('请允许 Sparxie 安装未知来源应用');
    }
    final package = await _download(asset, onProgress, githubToken);
    try {
      onProgress(const AppUpdateProgress(AppUpdateStage.launchingInstaller));
      await _androidInstallerChannel.invokeMethod<void>(
        'installUpdatePackage',
        {'path': package.path},
      );
      return AppUpdateLaunch.keepRunning;
    } on PlatformException catch (error) {
      await _deleteDirectory(package.parent);
      throw AppUpdateException('无法启动系统安装器${_platformErrorDetail(error)}');
    } catch (_) {
      await _deleteDirectory(package.parent);
      rethrow;
    }
  }

  static String _platformErrorDetail(PlatformException error) {
    final message = error.message?.trim();
    return message == null || message.isEmpty ? '' : ': $message';
  }

  static Future<AppUpdateLaunch> _installDesktop(
    AppUpdateAsset asset,
    void Function(AppUpdateProgress progress) onProgress,
    String githubToken,
  ) async {
    final file = await _download(asset, onProgress, githubToken);
    try {
      await AppUpdateCleanup.markPending(file.parent);
      onProgress(const AppUpdateProgress(AppUpdateStage.launchingInstaller));
      if (Platform.isWindows) {
        return await _launchWindowsInstaller(file, asset.sha256);
      }
      return await _launchMacOSInstaller(file, asset.sha256);
    } catch (_) {
      await _deleteDirectory(file.parent);
      rethrow;
    }
  }

  static Future<File> _download(
    AppUpdateAsset asset,
    void Function(AppUpdateProgress progress) onProgress,
    String githubToken,
  ) async {
    final directory = await _createDownloadDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${asset.name}',
    );
    try {
      for (var attempt = 0; attempt < AppUpdateHttp.attempts; attempt++) {
        final client = http.Client();
        var downloaded = 0;
        try {
          final request = http.Request('GET', asset.uri)
            ..headers.addAll(AppUpdateHttp.assetHeaders(githubToken));
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) {
            if (AppUpdateHttp.isTransientStatus(response.statusCode) &&
                attempt + 1 < AppUpdateHttp.attempts) {
              await AppUpdateHttp.waitBeforeRetry(attempt);
              continue;
            }
            throw AppUpdateException('下载安装包失败：服务器返回 ${response.statusCode}');
          }
          final contentLength = response.contentLength;
          if (contentLength != null && contentLength != asset.size) {
            throw const AppUpdateException('安装包大小与发布信息不一致');
          }

          final sink = file.openWrite();
          try {
            await for (final chunk in response.stream.timeout(
              const Duration(seconds: 30),
            )) {
              if (chunk.length > asset.size - downloaded) {
                throw const AppUpdateException('安装包大小与发布信息不一致');
              }
              downloaded += chunk.length;
              sink.add(chunk);
              onProgress(
                AppUpdateProgress(
                  AppUpdateStage.downloading,
                  fraction: (downloaded / asset.size).clamp(0, 1),
                ),
              );
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          if (downloaded != asset.size) {
            if (attempt + 1 < AppUpdateHttp.attempts) {
              await AppUpdateHttp.waitBeforeRetry(attempt);
              continue;
            }
            throw const AppUpdateException('安装包大小与发布信息不一致');
          }

          onProgress(const AppUpdateProgress(AppUpdateStage.verifying));
          final digest = await sha256.bind(file.openRead()).first;
          if (digest.toString().toLowerCase() != asset.sha256) {
            throw const AppUpdateException('安装包 SHA-256 校验失败');
          }
          return file;
        } on TimeoutException {
          if (attempt + 1 >= AppUpdateHttp.attempts) {
            throw const AppUpdateException('下载安装包超时');
          }
        } on http.ClientException catch (error) {
          if (attempt + 1 >= AppUpdateHttp.attempts) {
            throw AppUpdateException('下载安装包失败：${error.message}');
          }
        } on SocketException catch (error) {
          if (attempt + 1 >= AppUpdateHttp.attempts) {
            throw AppUpdateException('下载安装包失败：${error.message}');
          }
        } finally {
          client.close();
        }
        await AppUpdateHttp.waitBeforeRetry(attempt);
      }
      throw const AppUpdateException('下载安装包失败');
    } catch (error) {
      await _deleteDirectory(directory);
      rethrow;
    }
  }

  static Future<Directory> _createDownloadDirectory() async {
    if (!Platform.isAndroid) {
      return Directory.systemTemp.createTemp('sparxie-update-');
    }
    final cache = await getTemporaryDirectory();
    final root = Directory(
      '${cache.path}${Platform.pathSeparator}sparxie_updates',
    );
    await root.create(recursive: true);
    return root.createTemp('update-');
  }

  static Future<AppUpdateLaunch> _launchWindowsInstaller(
    File installer,
    String sha256,
  ) async {
    final app = File(Platform.resolvedExecutable);
    final bundledHelper = File(
      '${app.parent.path}${Platform.pathSeparator}sparxie-updater.exe',
    );
    if (!await bundledHelper.exists()) {
      throw const AppUpdateException('Windows 更新程序缺失');
    }
    final helper = File(
      '${installer.parent.path}${Platform.pathSeparator}sparxie-updater.exe',
    );
    await bundledHelper.copy(helper.path);
    final process = await Process.start(helper.path, [
      installer.path,
      app.path,
      '$pid',
      installer.parent.path,
      sha256,
    ], mode: ProcessStartMode.detached);
    await _waitForHelper(process, installer.parent, _windowsHelperReadyTimeout);
    return AppUpdateLaunch.closeApplication;
  }

  static Future<AppUpdateLaunch> _launchMacOSInstaller(
    File archive,
    String sha256,
  ) async {
    final currentBundle = _macOSAppBundle();
    if (currentBundle == null) {
      throw const AppUpdateException('无法定位当前 macOS 应用');
    }
    final bundleName = currentBundle.path.split(Platform.pathSeparator).last;
    final translocated =
        currentBundle.path.contains('/AppTranslocation/') ||
        currentBundle.path.startsWith('/Volumes/');
    final target = translocated
        ? Directory('/Applications/$bundleName')
        : currentBundle;
    final helper = File(
      '${currentBundle.path}/Contents/Helpers/sparxie-updater',
    );
    if (!await helper.exists()) {
      throw const AppUpdateException('macOS 更新程序缺失');
    }

    final process = await Process.start(helper.path, [
      archive.path,
      target.path,
      '$pid',
      archive.parent.path,
      sha256,
    ], mode: ProcessStartMode.detached);
    await _waitForHelper(process, archive.parent, _macOSHelperReadyTimeout);
    return AppUpdateLaunch.closeApplication;
  }

  static Future<void> _waitForHelper(
    Process process,
    Directory workDirectory,
    Duration timeout,
  ) async {
    final readyMarker = File(
      '${workDirectory.path}${Platform.pathSeparator}$_helperReadyMarker',
    );
    final failedMarker = File(
      '${workDirectory.path}${Platform.pathSeparator}$_helperFailedMarker',
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await failedMarker.exists()) {
        throw const AppUpdateException('更新程序未能启动，或授权已取消');
      }
      if (await readyMarker.exists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    process.kill();
    throw const AppUpdateException('更新程序未能正常启动');
  }

  static Directory? _macOSAppBundle() {
    var directory = File(Platform.resolvedExecutable).parent;
    while (directory.parent.path != directory.path) {
      if (directory.path.toLowerCase().endsWith('.app')) return directory;
      directory = directory.parent;
    }
    return null;
  }

  static Future<void> _deleteDirectory(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup; preserve the original update error.
    }
  }
}
