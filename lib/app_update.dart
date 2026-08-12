import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_paths.dart';
import 'app_prefs.dart';
import 'app_update_http.dart';

const _embeddedBuildNumber = int.fromEnvironment('SPARXIE_BUILD_NUMBER');
const _embeddedUpdateChannel = String.fromEnvironment('SPARXIE_UPDATE_CHANNEL');

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdateResult {
  const AppUpdateResult({
    required this.channel,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.channelChanged,
    required this.updateAvailable,
    required this.releaseUri,
    required this.asset,
  });

  final UpdateChannel channel;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final bool channelChanged;
  final bool updateAvailable;
  final Uri releaseUri;
  final AppUpdateAsset? asset;

  String get currentLabel => _versionLabel(currentVersion, currentBuild);
  String get latestLabel => _versionLabel(latestVersion, latestBuild);
}

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.uri,
    required this.size,
    required this.sha256,
  });

  final String name;
  final Uri uri;
  final int size;
  final String sha256;
}

abstract final class AppUpdateService {
  static final _stableRelease = Uri.parse(
    'https://github.com/UruhaLushia/sparxie/releases/latest',
  );
  static final _betaRelease = Uri.parse(
    'https://github.com/UruhaLushia/sparxie/releases/tag/pre-release',
  );
  static final _stableReleaseApi = Uri.parse(
    'https://api.github.com/repos/UruhaLushia/sparxie/releases/latest',
  );
  static final _betaReleaseApi = Uri.parse(
    'https://api.github.com/repos/UruhaLushia/sparxie/releases/tags/pre-release',
  );

  static UpdateChannel? get installedChannel =>
      switch (_embeddedUpdateChannel) {
        'stable' => UpdateChannel.stable,
        'beta' => UpdateChannel.beta,
        _ => Platform.isAndroid ? UpdateChannel.stable : null,
      };

  static bool canSelectChannel(UpdateChannel channel) =>
      !Platform.isAndroid || installedChannel == channel;

  static UpdateChannel resolveChannel(UpdateChannel preferred) =>
      Platform.isAndroid ? installedChannel ?? preferred : preferred;

  static Future<String> currentVersionLabel() async {
    final package = await PackageInfo.fromPlatform();
    final packageBuild = int.tryParse(package.buildNumber.trim()) ?? 0;
    final build = _embeddedBuildNumber > 0
        ? _embeddedBuildNumber
        : packageBuild;
    return _versionLabel(package.version.trim(), build);
  }

  static Future<AppUpdateResult> check(
    UpdateChannel channel, {
    String githubToken = '',
  }) async {
    if (!canSelectChannel(channel)) {
      throw const AppUpdateException('Android 不支持切换更新通道');
    }
    final releaseApiUri = channel == UpdateChannel.stable
        ? _stableReleaseApi
        : _betaReleaseApi;
    final metadataName = channel == UpdateChannel.stable
        ? 'release.json'
        : 'pre-release.json';
    final package = await PackageInfo.fromPlatform();
    final client = http.Client();
    late final Object? release;
    late final Object? metadata;
    try {
      release = await _getJson(
        client,
        releaseApiUri,
        headers: AppUpdateHttp.apiHeaders(githubToken),
        stage: '获取发布信息',
      );
      final metadataAsset = _assetNamed(release, metadataName, required: true)!;
      metadata = await _getVerifiedJson(client, metadataAsset, githubToken);
    } finally {
      client.close();
    }
    final latest = _latestVersion(metadata);
    final currentVersion = package.version.trim();
    if (currentVersion.isEmpty) {
      throw const AppUpdateException('当前版本号为空');
    }
    final packageBuild = int.tryParse(package.buildNumber.trim()) ?? 0;
    final currentBuild = _embeddedBuildNumber > 0
        ? _embeddedBuildNumber
        : packageBuild;
    final versionOrder = _compareVersions(latest.version, currentVersion);
    final currentChannel = installedChannel;
    final channelChanged = currentChannel != null && currentChannel != channel;
    final updateAvailable =
        channelChanged ||
        versionOrder > 0 ||
        (versionOrder == 0 && latest.build > currentBuild);

    return AppUpdateResult(
      channel: channel,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      latestVersion: latest.version,
      latestBuild: latest.build,
      channelChanged: channelChanged,
      updateAvailable: updateAvailable,
      releaseUri: channel == UpdateChannel.stable
          ? _stableRelease
          : _betaRelease,
      asset: switch (_platformAssetName()) {
        final name? => _assetNamed(release, name),
        null => null,
      },
    );
  }

  static Future<Object?> _getJson(
    http.Client client,
    Uri uri, {
    required Map<String, String> headers,
    required String stage,
  }) async {
    final response = await _getWithRetry(
      client,
      uri,
      headers: headers,
      stage: stage,
    );
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw AppUpdateException('$stage 失败：服务器返回了无效数据');
    }
  }

  static Future<Object?> _getVerifiedJson(
    http.Client client,
    AppUpdateAsset asset,
    String githubToken,
  ) async {
    final response = await _getWithRetry(
      client,
      asset.uri,
      headers: AppUpdateHttp.assetHeaders(githubToken),
      stage: '获取更新元数据',
    );
    final bytes = response.bodyBytes;
    if (bytes.length != asset.size) {
      throw const AppUpdateException('更新元数据大小与发布信息不一致');
    }
    if (sha256.convert(bytes).toString().toLowerCase() != asset.sha256) {
      throw const AppUpdateException('更新元数据 SHA-256 校验失败');
    }
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const AppUpdateException('更新元数据格式错误');
    }
  }

  static Future<http.Response> _getWithRetry(
    http.Client client,
    Uri uri, {
    required Map<String, String> headers,
    required String stage,
  }) async {
    for (var attempt = 0; attempt < AppUpdateHttp.attempts; attempt++) {
      try {
        final response = await client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
        if (AppUpdateHttp.isTransientStatus(response.statusCode) &&
            attempt + 1 < AppUpdateHttp.attempts) {
          await AppUpdateHttp.waitBeforeRetry(attempt);
          continue;
        }
        if (response.statusCode != 200) {
          throw AppUpdateException('$stage 失败：服务器返回 ${response.statusCode}');
        }
        return response;
      } on TimeoutException {
        if (attempt + 1 >= AppUpdateHttp.attempts) {
          throw AppUpdateException('$stage 超时');
        }
      } on http.ClientException catch (error) {
        if (attempt + 1 >= AppUpdateHttp.attempts) {
          throw AppUpdateException('$stage 失败：${error.message}');
        }
      } on SocketException catch (error) {
        if (attempt + 1 >= AppUpdateHttp.attempts) {
          throw AppUpdateException('$stage 失败：${error.message}');
        }
      }
      await AppUpdateHttp.waitBeforeRetry(attempt);
    }
    throw AppUpdateException('$stage 失败');
  }

  static AppUpdateAsset? _assetNamed(
    Object? raw,
    String expectedName, {
    bool required = false,
  }) {
    if (raw is! Map) {
      throw const AppUpdateException('发布信息格式错误');
    }
    final assets = raw['assets'];
    if (assets is! List) {
      throw const AppUpdateException('发布信息缺少资源列表');
    }
    Map? selected;
    for (final candidate in assets) {
      if (candidate is Map && candidate['name'] == expectedName) {
        selected = candidate;
        break;
      }
    }
    if (selected == null) {
      if (required) throw AppUpdateException('发布信息缺少 $expectedName');
      return null;
    }

    final rawUri = selected['url'];
    final size = selected['size'];
    final digest = selected['digest'];
    final uri = rawUri is String ? Uri.tryParse(rawUri) : null;
    if (uri == null || uri.scheme != 'https' || size is! int || size <= 0) {
      throw AppUpdateException('$expectedName 的发布信息无效');
    }
    if (digest is! String || !digest.startsWith('sha256:')) {
      throw AppUpdateException('$expectedName 缺少 SHA-256 校验值');
    }
    final sha256 = digest.substring('sha256:'.length).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw AppUpdateException('$expectedName 的 SHA-256 校验值无效');
    }
    return AppUpdateAsset(
      name: expectedName,
      uri: uri,
      size: size,
      sha256: sha256,
    );
  }

  static String? _platformAssetName() {
    final abi = Abi.current();
    if (Platform.isAndroid) {
      return switch (abi) {
        Abi.androidArm64 => 'sparxie-android-arm64-v8a.apk',
        Abi.androidX64 => 'sparxie-android-x86_64.apk',
        _ => 'sparxie-android-universal.apk',
      };
    }
    if (Platform.isWindows) {
      final suffix = AppPaths.isPortable ? '.zip' : '-setup.exe';
      return switch (abi) {
        Abi.windowsArm64 => 'sparxie-windows-arm64$suffix',
        Abi.windowsX64 => 'sparxie-windows-x86_64$suffix',
        _ => null,
      };
    }
    if (Platform.isMacOS) {
      return switch (abi) {
        Abi.macosArm64 => 'sparxie-macos-arm64-update.tar.gz',
        Abi.macosX64 => 'sparxie-macos-x86_64-update.tar.gz',
        _ => null,
      };
    }
    return null;
  }

  static ({String version, int build}) _latestVersion(Object? raw) {
    if (raw is! Map) throw const AppUpdateException('更新元数据格式错误');
    final apps = raw['apps'];
    if (apps is! List) {
      throw const AppUpdateException('更新元数据缺少应用列表');
    }

    Map? app;
    for (final candidate in apps) {
      if (candidate is Map &&
          candidate['bundleIdentifier'] == 'zip.atri.sparxie') {
        app = candidate;
        break;
      }
    }
    if (app == null) throw const AppUpdateException('更新元数据缺少 Sparxie');
    final versions = app['versions'];
    if (versions is! List) {
      throw const AppUpdateException('更新元数据缺少版本列表');
    }

    ({String version, int build})? latest;
    for (final candidate in versions) {
      if (candidate is! Map) continue;
      final version = candidate['version'];
      final build = int.tryParse('${candidate['buildVersion'] ?? ''}');
      if (version is! String || version.trim().isEmpty || build == null) {
        continue;
      }
      final next = (version: version.trim(), build: build);
      if (latest == null ||
          _compareVersions(next.version, latest.version) > 0 ||
          (_compareVersions(next.version, latest.version) == 0 &&
              next.build > latest.build)) {
        latest = next;
      }
    }
    if (latest == null) {
      throw const AppUpdateException('更新元数据没有有效版本');
    }
    return latest;
  }

  static int _compareVersions(String a, String b) {
    final left = _parseVersion(a);
    final right = _parseVersion(b);
    final length = left.core.length > right.core.length
        ? left.core.length
        : right.core.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.core.length ? left.core[i] : 0;
      final r = i < right.core.length ? right.core[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    if (left.preRelease.isEmpty && right.preRelease.isNotEmpty) return 1;
    if (left.preRelease.isNotEmpty && right.preRelease.isEmpty) return -1;
    return left.preRelease.compareTo(right.preRelease);
  }

  static ({List<int> core, String preRelease}) _parseVersion(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    value = value.split('+').first;
    final dash = value.indexOf('-');
    final coreText = dash < 0 ? value : value.substring(0, dash);
    final preRelease = dash < 0 ? '' : value.substring(dash + 1);
    final core = <int>[];
    for (final segment in coreText.split('.')) {
      final number = int.tryParse(segment);
      if (number == null) throw AppUpdateException('无法解析版本号：$raw');
      core.add(number);
    }
    if (core.isEmpty) throw AppUpdateException('无法解析版本号：$raw');
    return (core: core, preRelease: preRelease);
  }
}

String _versionLabel(String version, int build) =>
    build > 0 ? '$version ($build)' : version;
