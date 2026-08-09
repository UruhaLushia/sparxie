part of '../proxies.dart';

class ProxyMemberWindowRequest {
  const ProxyMemberWindowRequest(this.offset, this.limit, this.membersHash);

  final int offset;
  final int limit;
  final int membersHash;
}

/// One proxy group. The mutable selection and member window are observable.
class ProxyGroup {
  ProxyGroup._({
    required this.name,
    required String type,
    required bool selectable,
    required String icon,
    required this._memberCount,
    required this._membersHash,
    required String now,
    required int nowDelay,
    required String testUrl,
    required String fixed,
  }) : _type = type, // ignore: prefer_initializing_formals
       _selectable = selectable, // ignore: prefer_initializing_formals
       _icon = icon, // ignore: prefer_initializing_formals
       _testUrl = testUrl, // ignore: prefer_initializing_formals
       now = ValueNotifier<String>(now), // ignore: prefer_initializing_formals
       nowDelay = ValueNotifier<int>(
         nowDelay,
       ), // ignore: prefer_initializing_formals
       fixed = ValueNotifier<String>(fixed),
       _membersVersion = ValueNotifier<int>(0);

  static const int _memberWindowMin = 64;
  static const int _memberWindowOverscan = 32;
  static const int _memberRefetchMargin = 16;

  final String name;
  String _type;
  bool _selectable;
  String _icon;
  String _testUrl;
  int _memberCount;
  int _membersHash;
  int _memberOffset = 0;
  List<ProxyMember> _members = const <ProxyMember>[];
  List<rust.ProxyMemberSection> _memberSections =
      const <rust.ProxyMemberSection>[];
  int? _currentMemberIndex;
  final ValueNotifier<int> _membersVersion;

  final ValueNotifier<String> now;
  final ValueNotifier<int> nowDelay;
  final ValueNotifier<String> fixed;

  String get type => _type;
  String get icon => _icon;
  bool get canSelectMembers => _selectable;
  bool get usesManualSelection =>
      _type == 'Selector' || _type == 'select' || _type == 'Select';
  bool get canSelectOnTap => _selectable && usesManualSelection;
  bool get canFixMembers => _selectable && !usesManualSelection;
  bool get hidesExactNow => _type == 'LoadBalance';
  ValueListenable<int> get membersVersion => _membersVersion;
  String get testUrl => _testUrl;
  int get memberCount => _memberCount;
  List<rust.ProxyMemberSection> get memberSections => _memberSections;
  int? get locatedMemberIndex => _currentMemberIndex;

  ProxyMember? memberAt(int index) {
    final local = index - _memberOffset;
    if (local < 0 || local >= _members.length) return null;
    return _members[local];
  }

  bool hasMemberRange(int first, int last) {
    if (first < 0 || last >= _memberCount) return false;
    if (last < first) return true;
    for (var index = first; index <= last; index++) {
      if (memberAt(index) == null) return false;
    }
    return true;
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
    if (_memberOffset >= count && _clearMembers()) changed = true;
    return changed;
  }

  void _setNow(String value) {
    if (now.value == value) return;
    now.value = value;
    _currentMemberIndex = null;
    for (var index = 0; index < _members.length; index++) {
      if (_members[index].name == value) {
        _currentMemberIndex = _memberOffset + index;
        _setNowDelay(_members[index].delay.value);
        return;
      }
    }
    _setNowDelay(-1);
  }

  void _setNowDelay(int value) {
    if (nowDelay.value != value) nowDelay.value = value;
  }

  void _setTestUrl(String value) {
    if (_testUrl != value) _testUrl = value;
  }

  void _setFixed(String value) {
    if (fixed.value != value) fixed.value = value;
  }

  ProxyMemberWindowRequest? _windowRequest(
    int firstIndex,
    int lastIndex, {
    bool force = false,
  }) {
    if (_memberCount <= 0) return null;
    final first = firstIndex.clamp(0, _memberCount - 1);
    final last = lastIndex.clamp(first, _memberCount - 1);
    final cachedEnd = _memberOffset + _members.length;
    if (!force &&
        _members.isNotEmpty &&
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
    if (!force &&
        _members.isNotEmpty &&
        offset == _memberOffset &&
        limit == _members.length) {
      return null;
    }
    return ProxyMemberWindowRequest(offset, limit, _membersHash);
  }

  ProxyMemberWindowRequest? _currentWindowRequest() {
    if (_members.isEmpty) return null;
    return ProxyMemberWindowRequest(
      _memberOffset,
      _members.length,
      _membersHash,
    );
  }

  bool _setMemberWindow(
    int offset,
    List<rust.ProxyMemberEntry> entries, {
    List<rust.ProxyMemberSection>? sections,
    int? currentIndex,
  }) {
    final locationChanged =
        currentIndex != null && currentIndex != _currentMemberIndex;
    if (currentIndex != null) _currentMemberIndex = currentIndex;
    var sectionsChanged = false;
    if (sections != null && !listEquals(_memberSections, sections)) {
      _memberSections = List<rust.ProxyMemberSection>.unmodifiable(sections);
      sectionsChanged = true;
    }
    if (!hidesExactNow) {
      for (final entry in entries) {
        if (entry.name == now.value) {
          _setNowDelay(entry.delay);
          break;
        }
      }
    }
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
      return typeChanged || sectionsChanged || locationChanged;
    }

    final oldByName = <String, ProxyMember>{};
    for (final member in _members) {
      oldByName[member.name] = member;
    }
    final next = <ProxyMember>[];
    for (final entry in entries) {
      final reused = oldByName.remove(entry.name);
      if (reused == null) {
        next.add(ProxyMember.fromEntry(entry));
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
    if (!hidesExactNow && now.value == name) _setNowDelay(delay);
    for (final member in _members) {
      if (member.name == name) member._setDelay(delay);
    }
  }

  void _applyVisibleDelays(Map<String, int> delayByName) {
    if (!hidesExactNow) {
      final delay = delayByName[now.value];
      if (delay != null) _setNowDelay(delay);
    }
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
    final changed = _members.isNotEmpty || _memberSections.isNotEmpty;
    if (_members.isNotEmpty) _retireMembers(_members);
    _members = const <ProxyMember>[];
    _memberSections = const <rust.ProxyMemberSection>[];
    _currentMemberIndex = null;
    return changed;
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

  void _dispose() {
    now.dispose();
    nowDelay.dispose();
    fixed.dispose();
    _membersVersion.dispose();
    for (final member in _members) {
      member._dispose();
    }
  }
}

/// One proxy node. Subscribers repaint when [delay] changes.
class ProxyMember {
  ProxyMember._({
    required this.name,
    required String type,
    required int initialDelay,
  }) : _type = type, // ignore: prefer_initializing_formals
       delay = ValueNotifier<int>(initialDelay);

  factory ProxyMember.fromEntry(rust.ProxyMemberEntry entry) => ProxyMember._(
    name: entry.name,
    type: entry.proxyType,
    initialDelay: entry.delay,
  );

  final String name;
  String _type;
  final ValueNotifier<int> delay;
  bool _disposed = false;

  String get type => _type;

  bool _setType(String value) {
    if (_type == value) return false;
    _type = value;
    return true;
  }

  void _setDelay(int value) {
    if (delay.value != value) delay.value = value;
  }

  void updateDelay(int value) => _setDelay(value);

  void dispose() => _dispose();

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    delay.dispose();
  }
}
