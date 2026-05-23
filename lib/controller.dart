import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Controller {
  Controller({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.secret = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final String secret;

  Controller copyWith({String? name, String? baseUrl, String? secret}) {
    return Controller(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      secret: secret ?? this.secret,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'secret': secret,
  };

  factory Controller.fromJson(Map<String, dynamic> json) => Controller(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    baseUrl: json['baseUrl'] as String? ?? '',
    secret: json['secret'] as String? ?? '',
  );
}

class ControllerStore extends ChangeNotifier {
  ControllerStore._(this._prefs);

  static const _kControllers = 'controllers.v1';
  static const _kActiveId = 'controllers.active';

  final SharedPreferences _prefs;
  List<Controller> _controllers = [];
  String? _activeId;

  static Future<ControllerStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = ControllerStore._(prefs);
    store._restore();
    if (store._controllers.isEmpty) {
      store._controllers = [
        Controller(
          id: _newId(),
          name: '本地内核',
          baseUrl: 'http://127.0.0.1:9090',
        ),
      ];
      store._activeId = store._controllers.first.id;
      await store._persist();
    }
    return store;
  }

  List<Controller> get controllers => List.unmodifiable(_controllers);

  Controller? get active {
    if (_activeId == null) return _controllers.isEmpty ? null : _controllers.first;
    return _controllers.firstWhere(
      (c) => c.id == _activeId,
      orElse: () => _controllers.first,
    );
  }

  String? get activeId => active?.id;

  void _restore() {
    final raw = _prefs.getString(_kControllers);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _controllers = list
            .whereType<Map<String, dynamic>>()
            .map(Controller.fromJson)
            .toList();
      } catch (_) {
        _controllers = [];
      }
    }
    _activeId = _prefs.getString(_kActiveId);
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _kControllers,
      jsonEncode(_controllers.map((c) => c.toJson()).toList()),
    );
    if (_activeId != null) {
      await _prefs.setString(_kActiveId, _activeId!);
    } else {
      await _prefs.remove(_kActiveId);
    }
  }

  Future<Controller> add({
    required String name,
    required String baseUrl,
    String secret = '',
  }) async {
    final controller = Controller(
      id: _newId(),
      name: name,
      baseUrl: baseUrl,
      secret: secret,
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
    String? baseUrl,
    String? secret,
  }) async {
    _controllers = _controllers
        .map(
          (c) => c.id == id
              ? c.copyWith(name: name, baseUrl: baseUrl, secret: secret)
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
