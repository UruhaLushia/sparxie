import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../error_format.dart';
import '../rust_api.dart' as rust;
import '../view_state/process_icons.dart';
import '../widgets/app_background.dart';
import '../widgets/compact_controls/search_field.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/page_body_transition.dart';
import '../widgets/process_icon.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

typedef _WindowRequest = ({
  int offset,
  int limit,
  String query,
  bool showSystem,
  int generation,
});

class CoreAccessScreen extends StatefulWidget {
  const CoreAccessScreen({
    super.key,
    required this.selected,
    required this.iconCache,
  });

  final Set<String> selected;
  final ProcessIconCache iconCache;

  @override
  State<CoreAccessScreen> createState() => _CoreAccessScreenState();
}

class _CoreAccessScreenState extends State<CoreAccessScreen> {
  static const _initialLimit = 32;
  static const _overscan = 4;

  late final Set<String> _selected = {...widget.selected};
  final _filterController = TextEditingController();
  final _scroll = ScrollController();
  List<rust.AppInfo> _apps = const [];
  int _total = 0;
  int _offset = 0;
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _showSystemApps = false;
  bool _draining = false;
  bool _windowScheduled = false;
  double _itemExtent = 72;
  Timer? _debounce;
  int _generation = 0;
  _WindowRequest? _pending;
  ({int offset, int limit})? _requestedWindow;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleWindow);
    _requestWindow(0, _initialLimit);
  }

  @override
  void dispose() {
    _generation++;
    _pending = null;
    _debounce?.cancel();
    _filterController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _requestWindow(int offset, int limit) {
    _requestedWindow = (offset: offset, limit: limit);
    _pending = (
      offset: offset,
      limit: limit,
      query: _query,
      showSystem: _showSystemApps,
      generation: ++_generation,
    );
    if (!_draining) unawaited(_drainWindows());
  }

  Future<void> _drainWindows() async {
    _draining = true;
    while (mounted && _pending != null) {
      final request = _pending!;
      _pending = null;
      try {
        final window = await rust.coreListAppsWindow(
          query: request.query,
          offset: request.offset,
          limit: request.limit,
          showSystem: request.showSystem,
        );
        if (!mounted || request.generation != _generation) continue;
        setState(() {
          _apps = window.apps;
          _total = window.total;
          _offset = request.offset;
          _loading = false;
          _error = null;
        });
        _scheduleWindow();
      } catch (error) {
        if (!mounted || request.generation != _generation) continue;
        setState(() {
          _loading = false;
          _error = formatError(error);
          _requestedWindow = null;
        });
      }
    }
    _draining = false;
  }

  void _scheduleWindow() {
    if (_windowScheduled) return;
    _windowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowScheduled = false;
      if (mounted) _ensureWindow();
    });
  }

  void _ensureWindow() {
    if (!_scroll.hasClients || _total == 0 || _loading || _error != null) {
      return;
    }
    final position = _scroll.position;
    final first = (position.pixels / _itemExtent).floor();
    final visible = (position.viewportDimension / _itemExtent).ceil();
    final offset = (first - _overscan).clamp(0, _total);
    final end = (first + visible + _overscan).clamp(offset, _total);
    final limit = (end - offset).clamp(1, 512);
    final desired = (offset: offset, limit: limit);
    final covered = offset >= _offset && end <= _offset + _apps.length;
    if (covered && _apps.length <= limit * 4) {
      if (_draining && desired != _requestedWindow) {
        _generation++;
        _pending = null;
        _requestedWindow = desired;
      }
      return;
    }
    if (desired != _requestedWindow) _requestWindow(offset, limit);
  }

  void _reload() {
    _debounce?.cancel();
    setState(() {
      _query = _filterController.text;
      _apps = const [];
      _total = 0;
      _offset = 0;
      _loading = true;
      _error = null;
    });
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    _requestWindow(0, _initialLimit);
  }

  void _setQuery(String _) {
    _debounce?.cancel();
    // Invalidate responses immediately, including during the debounce interval.
    _generation++;
    _pending = null;
    _debounce = Timer(const Duration(milliseconds: 250), _reload);
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    _itemExtent = 72 * scale.clamp(1.0, double.infinity);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(_selected.toList());
        }
      },
      child: Scaffold(
        appBar: AppRouteAppBar(
          child: AppBar(
            leading: AppRouteAppBar.leadingOf(context),
            automaticallyImplyLeading: false,
            title: const Text('选择应用'),
            flexibleSpace: const DesktopAppBarDragArea(),
            actions: [
              PopupMenuButton<String>(
                onSelected: (_) {
                  _showSystemApps = !_showSystemApps;
                  _reload();
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'system',
                    checked: _showSystemApps,
                    child: const Text('显示系统应用'),
                  ),
                ],
              ),
            ],
          ),
        ),
        body: AppPageBodyTransition(
          child: AppBackdropGroup(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: MaxWidthContent(
                    maxWidth: 720,
                    child: CompactSearchField(
                      controller: _filterController,
                      hintText: '搜索应用',
                      onChanged: _setQuery,
                      onClear: () {
                        _filterController.clear();
                        _setQuery('');
                      },
                    ),
                  ),
                ),
                Expanded(child: _buildList(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('读取应用失败：$_error', textAlign: TextAlign.center),
            TextButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_total == 0) {
      return Center(child: Text(_query.isEmpty ? '没有应用' : '没有匹配的应用'));
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleWindow();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _itemExtent,
        scrollCacheExtent: ScrollCacheExtent.pixels(_itemExtent * _overscan),
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: _total,
        itemBuilder: (context, index) {
          final local = index - _offset;
          final app = local >= 0 && local < _apps.length ? _apps[local] : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: MaxWidthContent(
              maxWidth: 720,
              child: SizedBox(
                height: _itemExtent - 4,
                child: AppPanelSurface(
                  groupBackdrop: true,
                  child: app == null
                      ? const SizedBox.expand()
                      : _AppRow(
                          key: ValueKey(app.package),
                          app: app,
                          iconCache: widget.iconCache,
                          checked: _selected.contains(app.package),
                          onChanged: (value) => setState(() {
                            if (value) {
                              _selected.add(app.package);
                            } else {
                              _selected.remove(app.package);
                            }
                          }),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.iconCache,
    required this.checked,
    required this.onChanged,
  });

  final rust.AppInfo app;
  final ProcessIconCache iconCache;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      dense: true,
      secondary: ProcessIcon(
        cache: iconCache,
        process: app.package,
        processPath: app.package,
      ),
      title: Text(
        app.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        app.package,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      value: checked,
      onChanged: (v) => onChanged(v ?? false),
    );
  }
}
