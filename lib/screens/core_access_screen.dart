import 'dart:async';

import 'package:flutter/material.dart';

import '../rust_api.dart' as rust;
import '../widgets/app_background.dart';
import '../widgets/compact_controls/search_field.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/page_body_transition.dart';
import '../widgets/route_app_bar.dart';
import '../widgets/section_panel.dart';

const _pageSize = 80;

class CoreAccessScreen extends StatefulWidget {
  const CoreAccessScreen({super.key, required this.selected});

  final Set<String> selected;

  @override
  State<CoreAccessScreen> createState() => _CoreAccessScreenState();
}

class _CoreAccessScreenState extends State<CoreAccessScreen> {
  late final Set<String> _selected = {...widget.selected};
  late final TextEditingController _filterController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<rust.AppInfo> _apps = const [];
  int _total = 0;
  int _offset = 0;
  String _query = '';
  bool _loading = false;
  Timer? _debounce;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load(append: false);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _filterController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _load(append: true);
    }
  }

  Future<void> _load({required bool append}) async {
    if (_loading) return;
    if (append && _apps.length >= _total) return;
    _loading = true;
    final seq = ++_requestSeq;
    final offset = append ? _offset : 0;
    late final rust.AppWindow window;
    try {
      window = await rust.coreListAppsWindow(
        query: _query,
        offset: offset,
        limit: _pageSize,
      );
    } catch (_) {
      if (mounted && seq == _requestSeq) {
        setState(() => _loading = false);
      }
      return;
    }
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _total = window.total;
      _apps = append ? [..._apps, ...window.apps] : window.apps;
      _offset = _apps.length;
      _loading = false;
    });
  }

  void _setQuery(String value) {
    final query = value.trim().toLowerCase();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _requestSeq++;
      _query = query;
      _apps = const [];
      _total = 0;
      _offset = 0;
      _loading = false;
      _load(append: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppRouteAppBar(
        child: AppBar(
          leading: AppRouteAppBar.leadingOf(context),
          automaticallyImplyLeading: false,
          title: const Text('选择应用'),
          flexibleSpace: const DesktopAppBarDragArea(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_selected.toList()),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
      body: AppPageBodyTransition(
        child: AppBackdropGroup(
          child: ListView(
            controller: _scroll,
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CompactSearchField(
                      controller: _filterController,
                      hintText: '搜索应用',
                      onChanged: _setQuery,
                      onClear: () {
                        _filterController.clear();
                        _setQuery('');
                      },
                    ),
                    const SizedBox(height: 14),
                    AppPanelSurface(
                      groupBackdrop: true,
                      child: _apps.isEmpty && !_loading
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _query.isEmpty ? '没有应用' : '没有匹配的应用',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _apps.length + 1,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                if (index == _apps.length) {
                                  return _loading
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Center(
                                            child: SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink();
                                }
                                final app = _apps[index];
                                return _AppRow(
                                  app: app,
                                  checked: _selected.contains(app.package),
                                  onChanged: (v) => setState(() {
                                    if (v) {
                                      _selected.add(app.package);
                                    } else {
                                      _selected.remove(app.package);
                                    }
                                  }),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.checked,
    required this.onChanged,
  });

  final rust.AppInfo app;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      dense: true,
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
