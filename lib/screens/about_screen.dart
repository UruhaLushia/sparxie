import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../app_prefs.dart';
import '../app_update.dart';
import '../app_update_installer.dart';
import '../widgets/compact_controls.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('关于'),
          flexibleSpace: const DesktopAppBarDragArea(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            MaxWidthContent(
              maxWidth: 720,
              child: Column(
                children: [
                  const _AppIntroduction(),
                  const SizedBox(height: 12),
                  AppPanelSurface(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _UpdateControls(prefs: prefs),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIntroduction extends StatelessWidget {
  const _AppIntroduction();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppPanelSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Column(
          children: [
            Text(
              'Sparxie',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '跨平台代理控制器',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '支持 Clash / Mihomo、Surge 与 sing-box，'
              '提供代理组、连接、规则与运行状态管理。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            FutureBuilder<String>(
              future: AppUpdateService.currentVersionLabel(),
              builder: (context, snapshot) => Text(
                '版本 ${snapshot.data ?? '—'}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateControls extends StatefulWidget {
  const _UpdateControls({required this.prefs});

  final AppPrefs prefs;

  @override
  State<_UpdateControls> createState() => _UpdateControlsState();
}

class _UpdateControlsState extends State<_UpdateControls> {
  bool _checking = false;
  bool _installing = false;
  bool _failed = false;
  String? _status;
  double? _downloadProgress;

  bool get _busy => _checking || _installing;
  UpdateChannel get _selectedChannel =>
      AppUpdateService.resolveChannel(widget.prefs.updateChannel);
  bool get _canForceUpdate =>
      _selectedChannel == UpdateChannel.beta && AppUpdateInstaller.isSupported;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('检查更新', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    Platform.isAndroid ? 'Android 更新通道随安装包固定' : '选择要跟踪的发布通道',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onLongPress: !_busy && _canForceUpdate ? _forceCheck : null,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _check,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt, size: 18),
                label: Text(_installing ? '更新中' : (_checking ? '检查中' : '检查')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        CompactSegmentedButton<UpdateChannel>(
          expanded: true,
          segments: [
            ButtonSegment(
              value: UpdateChannel.stable,
              enabled:
                  !_busy &&
                  AppUpdateService.canSelectChannel(UpdateChannel.stable),
              label: const Text('正式版'),
            ),
            ButtonSegment(
              value: UpdateChannel.beta,
              enabled:
                  !_busy &&
                  AppUpdateService.canSelectChannel(UpdateChannel.beta),
              label: const Text('测试版'),
            ),
          ],
          selected: {_selectedChannel},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            final channel = selection.first;
            if (!AppUpdateService.canSelectChannel(channel)) return;
            unawaited(widget.prefs.setUpdateChannel(channel));
            setState(() {
              _status = null;
              _failed = false;
            });
          },
        ),
        if (_status case final status?) ...[
          const SizedBox(height: 8),
          if (_downloadProgress case final progress?) ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
          ],
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _check({bool force = false}) async {
    setState(() {
      _checking = true;
      _failed = false;
      _status = null;
      _downloadProgress = null;
    });
    AppUpdateResult? result;
    try {
      final channel = _selectedChannel;
      result = await AppUpdateService.check(
        channel,
        githubToken: widget.prefs.githubToken,
      );
      if (!mounted) return;
      setState(() {
        _status = _updateStatus(result!);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _status = '检查失败：$error';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (result == null || !mounted) return;
    if (force) {
      await _showUpdate(result, force: true);
    } else if (result.updateAvailable) {
      await _showUpdate(result);
    }
  }

  Future<void> _forceCheck() async {
    if (_busy || !_canForceUpdate) return;
    await _check(force: true);
  }

  Future<void> _showUpdate(AppUpdateResult result, {bool force = false}) async {
    final canInstall = AppUpdateInstaller.isSupported && result.asset != null;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          force
              ? '强制更新测试'
              : result.channelChanged
              ? '切换到${_channelLabel(result.channel)}'
              : '发现新版本',
        ),
        content: Text(
          '当前版本：${result.currentLabel}\n'
          '${force || result.channelChanged ? '目标' : '最新'}版本：${result.latestLabel}'
          '${force ? '\n\n将重新下载安装测试版，用于验证完整更新流程。' : ''}'
          '${canInstall ? '' : _externalUpdateHint}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(canInstall ? '下载并安装' : '查看发布'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    if (canInstall) {
      await _install(result.asset!);
      return;
    }
    await _openRelease(result.releaseUri);
  }

  String get _externalUpdateHint => Platform.isLinux
      ? '\n\nLinux 请通过系统包管理器更新；这里仅打开发布页面。'
      : '\n\n当前发布暂未提供此平台的应用内安装包。';

  String _channelLabel(UpdateChannel channel) => switch (channel) {
    UpdateChannel.stable => '正式版',
    UpdateChannel.beta => '测试版',
  };

  String _updateStatus(AppUpdateResult result) {
    if (!result.updateAvailable) {
      return '已是最新版本 · ${result.currentLabel}';
    }
    if (result.channelChanged) {
      return '可切换到${_channelLabel(result.channel)} · ${result.latestLabel}';
    }
    return '发现 ${result.latestLabel} · 当前 ${result.currentLabel}';
  }

  Future<void> _install(AppUpdateAsset asset) async {
    setState(() {
      _installing = true;
      _failed = false;
      _status = '正在准备下载';
      _downloadProgress = null;
    });
    try {
      final launch = await AppUpdateInstaller.install(
        asset,
        githubToken: widget.prefs.githubToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            switch (progress.stage) {
              case AppUpdateStage.downloading:
                _downloadProgress = progress.fraction;
                final percent = progress.fraction == null
                    ? null
                    : (progress.fraction! * 100).round();
                _status = percent == null ? '正在下载' : '正在下载 $percent%';
              case AppUpdateStage.verifying:
                _downloadProgress = null;
                _status = '正在校验安装包';
              case AppUpdateStage.launchingInstaller:
                _downloadProgress = null;
                _status = '正在启动安装程序';
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _status = null;
        _downloadProgress = null;
      });
      if (launch == AppUpdateLaunch.closeApplication) {
        await windowManager.close();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _status = '更新失败：$error';
        _downloadProgress = null;
      });
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _openRelease(Uri releaseUri) async {
    final launched = await launchUrl(
      releaseUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开发布页面')));
    }
  }
}
