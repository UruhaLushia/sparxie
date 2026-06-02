import 'package:flutter/foundation.dart';

import '../rust_api.dart' as rust;

/// Proxy group + node catalog. Polls Rust's structured `/proxies` catalog.
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

  void applyCatalog(rust.ProxyCatalog catalog) {
    var shapeChanged = false;
    final seenNodes = <String>{};
    final seenGroups = <String>{};

    for (final entry in catalog.nodes) {
      final name = entry.name;
      seenNodes.add(name);
      final existing = _nodesById[name];
      if (existing == null) {
        _nodesById[name] = ProxyNode._(
          name: name,
          type: entry.proxyType,
          icon: entry.icon,
          initialDelay: entry.delay,
        );
      } else {
        existing._setDelay(entry.delay);
        if (existing.type != entry.proxyType) existing._type = entry.proxyType;
        if (existing.icon != entry.icon) existing._icon = entry.icon;
      }
    }

    for (final entry in catalog.groups) {
      final name = entry.name;
      seenGroups.add(name);
      final existing = _groupsById[name];
      if (existing == null) {
        final group = ProxyGroup._(
          name: name,
          type: entry.proxyType,
          icon: entry.icon,
          all: entry.all,
          now: entry.now,
          testUrl: entry.testUrl,
          fixed: entry.fixed,
        );
        _groupsById[name] = group;
        shapeChanged = true;
      } else {
        if (existing._type != entry.proxyType) existing._type = entry.proxyType;
        if (existing._icon != entry.icon) existing._icon = entry.icon;
        if (existing._setMembers(entry.all)) shapeChanged = true;
        existing._setNow(entry.now);
        existing._setTestUrl(entry.testUrl);
        existing._setFixed(entry.fixed);
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

    final ordered = <ProxyGroup>[];
    for (final entry in catalog.groups) {
      final group = _groupsById[entry.name];
      if (group != null) ordered.add(group);
    }
    if (shapeChanged || !_sameGroupOrder(_orderedGroups, ordered)) {
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
  void applyGroupDelay(List<rust.GroupDelayEntry> delays) {
    for (final entry in delays) {
      final node = _nodesById[entry.name];
      if (node == null) continue;
      node._setDelay(entry.delay);
    }
  }

  void applyProxyDelay(List<rust.ProxyDelayEntry> delays) {
    for (final entry in delays) {
      final node = _nodesById[entry.name];
      if (node == null) continue;
      node._setDelay(entry.delay);
    }
  }

  void applyNodeDelay(String nodeName, int delayMs) {
    _nodesById[nodeName]?._setDelay(delayMs);
  }

  static bool _sameGroupOrder(List<ProxyGroup> a, List<ProxyGroup> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name) return false;
    }
    return true;
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
  }) : _type = type, // ignore: prefer_initializing_formals
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
  }) : _type = type, // ignore: prefer_initializing_formals
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
