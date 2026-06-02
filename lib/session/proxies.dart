import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../rust_api.dart' as rust;

/// Proxy group + node catalog. Polls Rust's structured `/proxies` catalog.
///
/// Each [ProxyGroup] is created once per name and reused across polls. Group
/// members are windowed: Rust keeps the full list, Dart only holds the current
/// visible slice for expanded groups.
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
          icon: entry.icon,
          memberCount: entry.memberCount,
          membersHash: entry.membersHash,
          now: entry.now,
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
        if (existing._icon != entry.icon) {
          existing._icon = entry.icon;
          shapeChanged = true;
        }
        if (existing._setMemberShape(entry.memberCount, entry.membersHash)) {
          shapeChanged = true;
        }
        existing._setNow(entry.now);
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
    int lastIndex,
  ) {
    return _groupsById[groupName]?._windowRequest(firstIndex, lastIndex);
  }

  void applyGroupMembers(
    String groupName,
    int membersHash,
    int offset,
    List<rust.ProxyMemberEntry> entries,
  ) {
    final group = _groupsById[groupName];
    if (group == null) return;
    if (group._membersHash != membersHash) return;
    if (group._setMemberWindow(offset, entries)) group._notifyMembers();
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

class ProxyMemberWindowRequest {
  const ProxyMemberWindowRequest(this.offset, this.limit, this.membersHash);
  final int offset;
  final int limit;
  final int membersHash;
}

/// One proxy group. `now` and the member list are mutable observables.
class ProxyGroup {
  ProxyGroup._({
    required this.name,
    required String type,
    required String icon,
    required this._memberCount,
    required this._membersHash,
    required String now,
    required String testUrl,
    required String fixed,
  }) : _type = type, // ignore: prefer_initializing_formals
       _icon = icon, // ignore: prefer_initializing_formals
       _testUrl = testUrl, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       now = ValueNotifier<String>(now),
       fixed = ValueNotifier<String>(fixed),
       _membersVersion = ValueNotifier<int>(0);

  static const int _memberWindowMin = 96;
  static const int _memberWindowOverscan = 32;
  static const int _memberRefetchMargin = 16;
  final String name;
  String _type;
  String _icon;
  String _testUrl;
  int _memberCount;
  int _membersHash;
  int _memberOffset = 0;
  List<ProxyMember> _members = const <ProxyMember>[];
  final ValueNotifier<int> _membersVersion;

  String get type => _type;
  String get icon => _icon;
  ValueListenable<int> get membersVersion => _membersVersion;

  /// Per-group `tester`/`testUrl` configured in mihomo (empty when absent).
  String get testUrl => _testUrl;
  int get memberCount => _memberCount;

  final ValueNotifier<String> now;

  /// Name of the pinned (fixed) member, empty if not pinned. Listening to
  /// this lets the node tiles light up the pin icon without rebuilding the
  /// whole list.
  final ValueNotifier<String> fixed;

  ProxyMember? memberAt(int index) {
    final local = index - _memberOffset;
    if (local < 0 || local >= _members.length) return null;
    return _members[local];
  }

  bool _setMemberShape(int count, int hash) {
    var changed = false;
    if (_memberCount != count) {
      _memberCount = count;
      changed = true;
    }
    if (_membersHash != hash) {
      _membersHash = hash;
      _clearMembers();
      return true;
    }
    if (_memberOffset >= count && _clearMembers()) {
      changed = true;
    }
    return changed;
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
    _membersVersion.dispose();
    for (final member in _members) {
      member._dispose();
    }
  }

  ProxyMemberWindowRequest? _windowRequest(int firstIndex, int lastIndex) {
    if (_memberCount <= 0) return null;
    final first = firstIndex.clamp(0, _memberCount - 1);
    final last = lastIndex.clamp(first, _memberCount - 1);
    final cachedEnd = _memberOffset + _members.length;
    if (_members.isNotEmpty &&
        first >= _memberOffset + _memberRefetchMargin &&
        last < cachedEnd - _memberRefetchMargin) {
      return null;
    }
    final visible = last - first + 1;
    var limit = visible + _memberWindowOverscan * 2;
    if (limit < _memberWindowMin) limit = _memberWindowMin;
    if (limit > _memberCount) limit = _memberCount;
    final center = (first + last) ~/ 2;
    final maxOffset = (_memberCount - limit).clamp(0, _memberCount).toInt();
    final offset = (center - limit ~/ 2).clamp(0, maxOffset).toInt();
    if (_members.isNotEmpty &&
        offset == _memberOffset &&
        limit == _members.length) {
      return null;
    }
    return ProxyMemberWindowRequest(offset, limit, _membersHash);
  }

  bool _setMemberWindow(int offset, List<rust.ProxyMemberEntry> entries) {
    final same =
        offset == _memberOffset &&
        _members.length == entries.length &&
        _sameMemberEntries(_members, entries);
    if (same) {
      var typeChanged = false;
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (_members[i]._setType(entry.proxyType)) typeChanged = true;
        _members[i]._setDelay(entry.delay);
      }
      return typeChanged;
    }

    final oldByName = <String, ProxyMember>{};
    for (final member in _members) {
      oldByName[member.name] = member;
    }
    final next = <ProxyMember>[];
    for (final entry in entries) {
      final reused = oldByName.remove(entry.name);
      if (reused == null) {
        next.add(ProxyMember._fromRust(entry));
      } else {
        reused._setType(entry.proxyType);
        reused._setDelay(entry.delay);
        next.add(reused);
      }
    }
    _retireMembers(oldByName.values);
    _memberOffset = offset;
    _members = List<ProxyMember>.unmodifiable(next);
    return true;
  }

  void _setVisibleDelay(String name, int delay) {
    for (final member in _members) {
      if (member.name == name) member._setDelay(delay);
    }
  }

  void _applyVisibleDelays(Map<String, int> delayByName) {
    for (final member in _members) {
      final delay = delayByName[member.name];
      if (delay != null) member._setDelay(delay);
    }
  }

  static bool _sameMemberEntries(
    List<ProxyMember> members,
    List<rust.ProxyMemberEntry> entries,
  ) {
    for (var i = 0; i < members.length; i++) {
      if (members[i].name != entries[i].name) return false;
    }
    return true;
  }

  bool _clearMembers() {
    _memberOffset = 0;
    if (_members.isEmpty) return false;
    _retireMembers(_members);
    _members = const <ProxyMember>[];
    return true;
  }

  void _notifyMembers() {
    _membersVersion.value++;
  }

  void _retireMembers(Iterable<ProxyMember> members) {
    if (members.isEmpty) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final member in members) {
        member._dispose();
      }
    });
  }
}

/// One selectable node. Subscribers repaint when [delay] changes.
class ProxyMember {
  ProxyMember._({
    required this.name,
    required String type,
    required int initialDelay,
  }) : _type = type, // ignore: prefer_initializing_formals
       delay = ValueNotifier<int>(initialDelay);

  factory ProxyMember._fromRust(rust.ProxyMemberEntry entry) => ProxyMember._(
    name: entry.name,
    type: entry.proxyType,
    initialDelay: entry.delay,
  );

  final String name;
  String _type;
  String get type => _type;

  /// -1 = untested, 0 = timeout, >0 = ms.
  final ValueNotifier<int> delay;
  bool _disposed = false;

  bool _setType(String value) {
    if (_type == value) return false;
    _type = value;
    return true;
  }

  void _setDelay(int value) {
    if (delay.value != value) delay.value = value;
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    delay.dispose();
  }
}
