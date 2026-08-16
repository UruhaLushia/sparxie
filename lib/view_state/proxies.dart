import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../rust_api.dart' as rust;

part 'proxies/models.dart';

/// Proxy group + node catalog. Polls Rust's structured `/proxies` catalog.
///
/// Each [ProxyGroup] is created once per name and reused across polls. Group
/// members are windowed: Rust keeps the full list, while Dart retains bounded
/// slices only for expanded groups and visible cards being warmed.
class ProxiesNotifier extends ChangeNotifier {
  final Map<String, ProxyGroup> _groupsById = <String, ProxyGroup>{};
  List<ProxyGroup> _orderedGroups = const <ProxyGroup>[];

  List<ProxyGroup> get groups => _orderedGroups;

  void reset() {
    if (_groupsById.isEmpty) return;
    for (final g in _groupsById.values) {
      g._dispose();
    }
    _groupsById.clear();
    _orderedGroups = const <ProxyGroup>[];
    notifyListeners();
  }

  void applyCatalog(rust.ProxyCatalog catalog) {
    var shapeChanged = false;
    final seenGroups = <String>{};
    final ordered = <ProxyGroup>[];

    for (final entry in catalog.groups) {
      final name = entry.name;
      seenGroups.add(name);
      final existing = _groupsById[name];
      if (existing == null) {
        final group = ProxyGroup._(
          name: name,
          type: entry.proxyType,
          selectable: entry.selectable,
          icon: entry.icon,
          memberCount: entry.memberCount,
          membersHash: entry.membersHash,
          now: entry.now,
          nowDelay: entry.nowDelay,
          testUrl: entry.testUrl,
          fixed: entry.fixed,
        );
        _groupsById[name] = group;
        ordered.add(group);
        shapeChanged = true;
      } else {
        if (existing._type != entry.proxyType) {
          existing._type = entry.proxyType;
          shapeChanged = true;
        }
        existing._selectable = entry.selectable;
        if (existing._icon != entry.icon) {
          existing._icon = entry.icon;
          shapeChanged = true;
        }
        if (existing._setMemberShape(entry.memberCount, entry.membersHash)) {
          existing._notifyMembers();
          shapeChanged = true;
        }
        existing._setNow(entry.now);
        existing._setNowDelay(entry.nowDelay);
        existing._setTestUrl(entry.testUrl);
        existing._setFixed(entry.fixed);
        ordered.add(existing);
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

  void setFixedOptimistic(String groupName, String nodeName) {
    _groupsById[groupName]?._setFixed(nodeName);
  }

  /// Push delays from `/group/<name>/delay` into per-node notifiers.
  void applyGroupDelay(List<rust.GroupDelayEntry> delays) {
    final delayByName = <String, int>{};
    for (final entry in delays) {
      delayByName[entry.name] = entry.delay;
    }
    _applyVisibleDelays(delayByName);
  }

  void applyProxyDelay(List<rust.ProxyDelayEntry> delays) {
    final delayByName = <String, int>{};
    for (final entry in delays) {
      delayByName[entry.name] = entry.delay;
    }
    _applyVisibleDelays(delayByName);
  }

  void applyProxyDelayEvent(
    String groupName,
    rust.ProxyDelayEvent event, {
    bool applyWindow = true,
  }) {
    if (applyWindow && event.windowEntries.isNotEmpty) {
      applyGroupMembers(
        groupName,
        event.windowMembersHash,
        event.windowOffset,
        event.windowEntries,
      );
    } else if (event.name.isNotEmpty) {
      _setVisibleDelay(event.name, event.delay);
    }
  }

  void applyNodeDelay(String nodeName, int delayMs) {
    _setVisibleDelay(nodeName, delayMs);
  }

  void releaseGroupMembers(String groupName) {
    final group = _groupsById[groupName];
    if (group != null && group._clearMembers()) group._notifyMembers();
  }

  void releaseAllGroupMembers() {
    for (final group in _groupsById.values) {
      if (group._clearMembers()) group._notifyMembers();
    }
  }

  ProxyMemberWindowRequest? memberWindowRequest(
    String groupName,
    int firstIndex,
    int lastIndex, {
    bool force = false,
  }) {
    return _groupsById[groupName]?._windowRequest(
      firstIndex,
      lastIndex,
      force: force,
    );
  }

  String memberCurrentName(String groupName) =>
      _groupsById[groupName]?.now.value ?? '';

  ProxyMemberWindowRequest? currentMemberWindowRequest(String groupName) {
    return _groupsById[groupName]?._currentWindowRequest();
  }

  void applyGroupMembers(
    String groupName,
    int membersHash,
    int offset,
    List<rust.ProxyMemberEntry> entries, {
    List<rust.ProxyMemberSection>? sections,
    int? currentIndex,
  }) {
    final group = _groupsById[groupName];
    if (group == null) return;
    if (group._membersHash != membersHash) return;
    if (group._setMemberWindow(
      offset,
      entries,
      sections: sections,
      currentIndex: currentIndex,
    )) {
      group._notifyMembers();
    }
  }

  void _setVisibleDelay(String name, int delay) {
    for (final group in _groupsById.values) {
      group._setVisibleDelay(name, delay);
    }
  }

  void _applyVisibleDelays(Map<String, int> delayByName) {
    if (delayByName.isEmpty) return;
    for (final group in _groupsById.values) {
      group._applyVisibleDelays(delayByName);
    }
  }

  static bool _sameGroupOrder(List<ProxyGroup> a, List<ProxyGroup> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    for (final g in _groupsById.values) {
      g._dispose();
    }
    _groupsById.clear();
    super.dispose();
  }
}
