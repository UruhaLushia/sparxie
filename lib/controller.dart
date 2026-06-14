import 'package:flutter/foundation.dart';

import 'config_store.dart';

enum BackendType {
  clash,
  surge,
  singBox;

  String get label => switch (this) {
    BackendType.clash => 'Clash',
    BackendType.surge => 'Surge',
    BackendType.singBox => 'sing-box',
  };

  static BackendType fromJson(Object? value) => switch (value) {
    'clash' => BackendType.clash,
    'surge' => BackendType.surge,
    'singBox' || 'sing_box' || 'sing-box' => BackendType.singBox,
    _ => BackendType.clash,
  };
}

class Controller {
  Controller({
    required this.id,
    required this.name,
    this.type = BackendType.clash,
    required this.baseUrl,
    this.secret = '',
    this.allowInsecure = false,
  });

  final String id;
  final String name;
  final BackendType type;
  final String baseUrl;
  final String secret;

  /// Skip TLS certificate validation for https/wss backends.
  final bool allowInsecure;

  Controller copyWith({
    String? name,
    BackendType? type,
    String? baseUrl,
    String? secret,
    bool? allowInsecure,
  }) {
    return Controller(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      secret: secret ?? this.secret,
      allowInsecure: allowInsecure ?? this.allowInsecure,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'baseUrl': baseUrl,
    'secret': secret,
    'allowInsecure': allowInsecure,
  };

  factory Controller.fromJson(Map<String, dynamic> json) => Controller(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    type: BackendType.fromJson(json['type']),
    baseUrl: json['baseUrl'] as String? ?? '',
    secret: json['secret'] as String? ?? '',
    allowInsecure: json['allowInsecure'] as bool? ?? false,
  );
}

class ControllerStore extends ChangeNotifier {
  ControllerStore._(this._store);

  final JsonStore _store;
  List<Controller> _controllers = [];
  String? _activeId;

  Map<String, dynamic> get _section => _store.section('controllers');

  static Future<ControllerStore> load(JsonStore store) async {
    final s = ControllerStore._(store);
    s._restore();
    if (s._controllers.isEmpty) {
      s._controllers = [
        Controller(
          id: _newId(),
          name: '本地内核',
          baseUrl: 'http://127.0.0.1:9090',
        ),
      ];
      s._activeId = s._controllers.first.id;
      await s._persist();
    }
    return s;
  }

  List<Controller> get controllers => List.unmodifiable(_controllers);

  Controller? get active {
    if (_activeId == null) {
      return _controllers.isEmpty ? null : _controllers.first;
    }
    return _controllers.firstWhere(
      (c) => c.id == _activeId,
      orElse: () => _controllers.first,
    );
  }

  String? get activeId => active?.id;

  void _restore() {
    final section = _section;
    final list = section['list'];
    if (list is List) {
      _controllers = list
          .whereType<Map>()
          .map((m) => Controller.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    final active = section['active'];
    _activeId = active is String ? active : null;
  }

  Future<void> _persist() async {
    final section = _section;
    section['list'] = _controllers.map((c) => c.toJson()).toList();
    if (_activeId != null) {
      section['active'] = _activeId;
    } else {
      section.remove('active');
    }
    await _store.flush();
  }

  Future<Controller> add({
    required String name,
    BackendType type = BackendType.clash,
    required String baseUrl,
    String secret = '',
    bool allowInsecure = false,
  }) async {
    final controller = Controller(
      id: _newId(),
      name: name,
      type: type,
      baseUrl: baseUrl,
      secret: secret,
      allowInsecure: allowInsecure,
    );
    _controllers = [..._controllers, controller];
    _activeId ??= controller.id;
    await _persist();
    notifyListeners();
    return controller;
  }

  Future<void> update(
    String id, {
    String? name,
    BackendType? type,
    String? baseUrl,
    String? secret,
    bool? allowInsecure,
  }) async {
    _controllers = _controllers
        .map(
          (c) => c.id == id
              ? c.copyWith(
                  name: name,
                  type: type,
                  baseUrl: baseUrl,
                  secret: secret,
                  allowInsecure: allowInsecure,
                )
              : c,
        )
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _controllers = _controllers.where((c) => c.id != id).toList();
    if (_activeId == id) {
      _activeId = _controllers.isEmpty ? null : _controllers.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> activate(String id) async {
    if (_controllers.any((c) => c.id == id)) {
      _activeId = id;
      await _persist();
      notifyListeners();
    }
  }

  static String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return now.toRadixString(36);
  }
}
