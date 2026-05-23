import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../utils.dart';

/// Proxy group + node catalog. Polls `/proxies` (no upstream WS).
///
/// Each [ProxyGroup] / [ProxyNode] is created once per name and reused across
/// polls. The notifier fires only on shape changes (group set or member list);
/// `now` and per-node `delay` flow through their own [ValueNotifier]s.
class ProxiesNotifier extends ChangeNotifier {
  final Map<String, ProxyGroup> _groupsById = <String, ProxyGroup>{};
  final Map<String, ProxyNode> _nodesById = <String, ProxyNode>{};
  List<ProxyGroup> _orderedGroups = const <ProxyGroup>[];

  List<ProxyGroup> get groups => _orderedGroups;

  ProxyNode? nodeByName(String name) => _nodesById[name];

  void reset() {
    if (_groupsById.isEmpty && _nodesById.isEmpty) return;
    for (final g in _groupsById.values) {
      g._dispose();
    }
    for (final n in _nodesById.values) {
      n._dispose();
    }
    _groupsById.clear();
    _nodesById.clear();
    _orderedGroups = const <ProxyGroup>[];
    notifyListeners();
  }

  void apply(String rawJson) {
    final root = jsonDecode(rawJson) as Map<String, dynamic>;
    final proxies = asMap(root['proxies']);

    var shapeChanged = false;

    final seenNodes = <String>{};
    final seenGroups = <String>{};
    // mihomo's `/proxies` keys are sorted by UTF-8 byte order; the user's
    // config order lives in `GLOBAL.all`.
    final orderedGroupNames = <String>[];
    List<String>? globalAll;

    // Register every proxy as a node so a parent group's `all` entry
    // resolves type + delay even when the member is itself a group or a
    // built-in like DIRECT / REJECT.
    for (final entry in proxies.entries) {
      final name = entry.key;
      final data = asMap(entry.value);
      seenNodes.add(name);
      final existing = _nodesById[name];
      final delay = _historyDelay(data['history']);
      final type = data['type']?.toString() ?? 'Proxy';
      final icon = data['icon']?.toString() ?? '';
      if (existing == null) {
        _nodesById[name] = ProxyNode._(
          name: name,
          type: type,
          icon: icon,
          initialDelay: delay,
        );
      } else {
        existing._setDelay(delay);
        if (existing.type != type) existing._type = type;
        if (existing.icon != icon) existing._icon = icon;
      }
    }

    for (final entry in proxies.entries) {
      final name = entry.key;
      final data = asMap(entry.value);
      final all = asStringList(data['all']);
      if (all.isEmpty) continue;
      seenGroups.add(name);
      orderedGroupNames.add(name);
      if (name == 'GLOBAL') globalAll = all;
      final type = data['type']?.toString() ?? 'Selector';
      final now = data['now']?.toString() ?? '';
      final icon = data['icon']?.toString() ?? '';
      // mihomo uses both `testUrl` and `tester` in different versions/forks.
      final testUrl = (data['testUrl'] ?? data['tester'] ?? '').toString();
      // `fixed` is the name of the pinned member, or empty/absent.
      final fixed = data['fixed']?.toString() ?? '';
      final existing = _groupsById[name];
      if (existing == null) {
        final group = ProxyGroup._(
          name: name,
          type: type,
          icon: icon,
          all: all,
          now: now,
          testUrl: testUrl,
          fixed: fixed,
        );
        _groupsById[name] = group;
        shapeChanged = true;
      } else {
        if (existing._type != type) existing._type = type;
        if (existing._icon != icon) existing._icon = icon;
        if (existing._setMembers(all)) shapeChanged = true;
        existing._setNow(now);
        existing._setTestUrl(testUrl);
        existing._setFixed(fixed);
      }
    }

    final removedGroupNames = <String>[];
    for (final key in _groupsById.keys) {
      if (!seenGroups.contains(key)) removedGroupNames.add(key);
    }
    for (final name in removedGroupNames) {
      _groupsById.remove(name)?._dispose();
      shapeChanged = true;
    }

    final removedNodeNames = <String>[];
    for (final key in _nodesById.keys) {
      if (!seenNodes.contains(key)) removedNodeNames.add(key);
    }
    // Don't dispose evicted nodes. A still-mounted ValueListenableBuilder may
    // hold a reference and a microtask-deferred dispose still races the build
    // phase. Cost is negligible — a name string + a single int notifier.
    for (final name in removedNodeNames) {
      _nodesById.remove(name);
    }

    if (shapeChanged) {
      // Hide GLOBAL (it duplicates every other group) and sort the rest by
      // GLOBAL.all index. Groups missing from GLOBAL.all sink to the bottom.
      final sortIndex = <String, int>{
        if (globalAll != null)
          for (var i = 0; i < globalAll.length; i++) globalAll[i]: i,
      };

      final ordered = <ProxyGroup>[];
      for (final name in orderedGroupNames) {
        if (name == 'GLOBAL') continue;
        final g = _groupsById[name];
        if (g != null) ordered.add(g);
      }
      ordered.sort((a, b) {
        final ai = sortIndex[a.name];
        final bi = sortIndex[b.name];
        if (ai == null && bi == null) return 0;
        if (ai == null) return 1;
        if (bi == null) return -1;
        return ai - bi;
      });
      _orderedGroups = List<ProxyGroup>.unmodifiable(ordered);
      notifyListeners();
    }
  }

  /// Optimistically point a group at a different node before the round-trip
  /// completes. The next `apply` reconciles against the upstream truth.
  void setNowOptimistic(String groupName, String nodeName) {
    final g = _groupsById[groupName];
    if (g == null) return;
    g._setNow(nodeName);
  }

  /// Push delays from `/group/<name>/delay` into per-node notifiers.
  void applyGroupDelay(String groupName, Map<String, dynamic> delays) {
    for (final entry in delays.entries) {
      final node = _nodesById[entry.key];
      if (node == null) continue;
      node._setDelay(asInt(entry.value));
    }
  }

  void applyNodeDelay(String nodeName, int delayMs) {
    _nodesById[nodeName]?._setDelay(delayMs);
  }

  static int _historyDelay(Object? raw) {
    if (raw is! List || raw.isEmpty) return -1;
    final last = asMap(raw.last);
    return asInt(last['delay']);
  }

  @override
  void dispose() {
    for (final g in _groupsById.values) {
      g._dispose();
    }
    for (final n in _nodesById.values) {
      n._dispose();
    }
    _groupsById.clear();
    _nodesById.clear();
    super.dispose();
  }
}

/// One proxy group. `now` and the member list are mutable observables.
class ProxyGroup {
  ProxyGroup._({
    required this.name,
    required String type,
    required String icon,
    required List<String> all,
    required String now,
    required String testUrl,
    required String fixed,
  })  : _type = type, // ignore: prefer_initializing_formals
        _icon = icon, // ignore: prefer_initializing_formals
        _testUrl = testUrl, // ignore: prefer_initializing_formals
        _all = List<String>.unmodifiable(all),
        // ignore: prefer_initializing_formals
        now = ValueNotifier<String>(now),
        fixed = ValueNotifier<String>(fixed);

  final String name;
  String _type;
  String _icon;
  String _testUrl;
  List<String> _all;

  String get type => _type;
  String get icon => _icon;

  /// Per-group `tester`/`testUrl` configured in mihomo (empty when absent).
  String get testUrl => _testUrl;
  List<String> get all => _all;

  final ValueNotifier<String> now;

  /// Name of the pinned (fixed) member, empty if not pinned. Listening to
  /// this lets the node tiles light up the pin icon without rebuilding the
  /// whole list.
  final ValueNotifier<String> fixed;

  bool _setMembers(List<String> next) {
    if (_listEquals(_all, next)) return false;
    _all = List<String>.unmodifiable(next);
    return true;
  }

  void _setNow(String value) {
    if (now.value != value) now.value = value;
  }

  void _setTestUrl(String value) {
    if (_testUrl != value) _testUrl = value;
  }

  void _setFixed(String value) {
    if (fixed.value != value) fixed.value = value;
  }

  void _dispose() {
    now.dispose();
    fixed.dispose();
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One selectable node. Subscribers repaint when [delay] changes.
class ProxyNode {
  ProxyNode._({
    required this.name,
    required String type,
    required String icon,
    required int initialDelay,
  })  : _type = type, // ignore: prefer_initializing_formals
        _icon = icon, // ignore: prefer_initializing_formals
        delay = ValueNotifier<int>(initialDelay);

  final String name;
  String _type;
  String _icon;
  String get type => _type;
  String get icon => _icon;

  /// -1 = untested, 0 = timeout, >0 = ms.
  final ValueNotifier<int> delay;

  void _setDelay(int value) {
    if (delay.value != value) delay.value = value;
  }

  void _dispose() => delay.dispose();
}
