import 'package:flutter/foundation.dart';

import 'config_store.dart';

enum BackendType {
  clash,
  surge,
  surgeController,
  singBox;

  String get label => switch (this) {
    BackendType.clash => 'Clash',
    BackendType.surge => 'Surge HTTP API',
    BackendType.surgeController => 'Surge 控制器',
    BackendType.singBox => 'sing-box',
  };

  static BackendType fromJson(Object? value) => switch (value) {
    'clash' => BackendType.clash,
    'surge' => BackendType.surge,
    'surgeController' ||
    'surge_controller' ||
    'surge-controller' => BackendType.surgeController,
    'singBox' || 'sing_box' || 'sing-box' => BackendType.singBox,
    _ => BackendType.clash,
  };
}

String normalizeControllerIconUrl(String? value) {
  final icon = value?.trim() ?? '';
  if (icon.isEmpty) return '';
  if (icon.length > 4096) {
    throw const FormatException('目标服务图标地址过长');
  }
  final uri = Uri.tryParse(icon);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('目标服务图标必须是 http 或 https URL');
  }
  return icon;
}

class Controller {
  Controller({
    required this.id,
    required this.name,
    this.type = BackendType.clash,
    required this.baseUrl,
    this.icon = '',
    this.secret = '',
    this.allowInsecure = false,
  });

  final String id;
  final String name;
  final BackendType type;
  final String baseUrl;
  final String icon;
  final String secret;

  /// Skip TLS certificate validation for https/wss backends.
  final bool allowInsecure;

  Controller copyWith({
    String? name,
    BackendType? type,
    String? baseUrl,
    String? icon,
    String? secret,
    bool? allowInsecure,
  }) {
    return Controller(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      icon: icon ?? this.icon,
      secret: secret ?? this.secret,
      allowInsecure: allowInsecure ?? this.allowInsecure,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'baseUrl': baseUrl,
    'icon': icon,
    'secret': secret,
    'allowInsecure': allowInsecure,
  };

  factory Controller.fromJson(Map<String, dynamic> json) => Controller(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    type: BackendType.fromJson(json['type']),
    baseUrl: json['baseUrl'] as String? ?? '',
    icon: json['icon'] as String? ?? '',
    secret: json['secret'] as String? ?? '',
    allowInsecure: json['allowInsecure'] as bool? ?? false,
  );
}

class ControllerDraft {
  const ControllerDraft({
    required this.name,
    required this.type,
    required this.baseUrl,
    this.icon = '',
    this.secret = '',
    this.allowInsecure = false,
  });

  final String name;
  final BackendType type;
  final String baseUrl;
  final String icon;
  final String secret;
  final bool allowInsecure;
}

class ControllerImportRequest {
  const ControllerImportRequest(this.draft);

  static const scheme = 'sparxie';
  static const _actions = {'install-target', 'install-backend'};

  final ControllerDraft draft;

  factory ControllerImportRequest.fromUri(Uri uri) {
    if (uri.scheme.toLowerCase() != scheme) {
      throw const FormatException('不支持的链接协议');
    }

    final action = uri.host.isNotEmpty
        ? uri.host.toLowerCase()
        : uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .firstOrNull
              ?.toLowerCase();
    if (!_actions.contains(action)) {
      throw const FormatException('不支持的导入操作');
    }

    final params = uri.queryParameters;
    final rawUrl = (params['url'] ?? params['address'] ?? params['endpoint'])
        ?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      throw const FormatException('缺少目标服务地址 url');
    }
    if (rawUrl.length > 4096) {
      throw const FormatException('目标服务地址过长');
    }

    final type = _parseType(params['type']);
    final baseUrl = _normalizeBaseUrl(rawUrl, type);
    final icon = normalizeControllerIconUrl(
      params['icon'] ?? params['iconUrl'] ?? params['icon-url'],
    );
    final ipc = _isIpcUrl(baseUrl);
    final rawName = params['name']?.trim();
    final name = rawName == null || rawName.isEmpty
        ? _defaultName(baseUrl, type)
        : rawName;
    if (name.length > 120) {
      throw const FormatException('目标服务名称过长');
    }
    final secret = ipc ? '' : params['secret']?.trim() ?? '';
    if (type == BackendType.surgeController && secret.isEmpty) {
      throw const FormatException('缺少 Surge 控制器密码 secret');
    }

    return ControllerImportRequest(
      ControllerDraft(
        name: name,
        type: type,
        baseUrl: baseUrl,
        icon: icon,
        secret: secret,
        allowInsecure:
            !ipc &&
            _isSecureUrl(baseUrl) &&
            _parseBool(params['allowInsecure'] ?? params['allow-insecure']),
      ),
    );
  }

  static BackendType _parseType(String? value) {
    return switch (value?.trim().toLowerCase()) {
      null || '' || 'clash' || 'mihomo' => BackendType.clash,
      'surge' => BackendType.surge,
      'surge-controller' ||
      'surge_controller' ||
      'surgecontroller' => BackendType.surgeController,
      'sing-box' || 'sing_box' || 'singbox' => BackendType.singBox,
      _ => throw const FormatException('不支持的目标服务类型'),
    };
  }

  static String _normalizeBaseUrl(String value, BackendType type) {
    var url = value;
    final lower = url.toLowerCase();
    final hasKnownScheme = const [
      'http://',
      'https://',
      'tcp://',
      'grpc://',
      'grpcs://',
      'unix:',
      'pipe:',
      'sparkle-service:',
    ].any(lower.startsWith);
    if (!hasKnownScheme) {
      if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(url)) {
        throw const FormatException('不支持的目标服务连接方式');
      }
      url = switch (type) {
        BackendType.singBox => 'grpc://$url',
        BackendType.surgeController => 'tcp://$url',
        _ => 'http://$url',
      };
    }

    final separator = url.indexOf(':');
    final rawScheme = url.substring(0, separator).toLowerCase();
    final normalizedScheme = switch ((type, rawScheme)) {
      (BackendType.singBox, 'http') => 'grpc',
      (BackendType.singBox, 'https') => 'grpcs',
      (BackendType.clash || BackendType.surge, 'grpc') => 'http',
      (BackendType.clash || BackendType.surge, 'grpcs') => 'https',
      _ => rawScheme,
    };
    if (normalizedScheme != rawScheme ||
        url.substring(0, separator) != normalizedScheme) {
      url = '$normalizedScheme${url.substring(separator)}';
    }

    final allowed = switch (type) {
      BackendType.clash => const {
        'http',
        'https',
        'unix',
        'pipe',
        'sparkle-service',
      },
      BackendType.surge => const {'http', 'https'},
      BackendType.surgeController => const {'tcp'},
      BackendType.singBox => const {'grpc', 'grpcs'},
    };
    if (!allowed.contains(normalizedScheme)) {
      throw FormatException('$normalizedScheme 连接方式不适用于 ${type.label}');
    }

    if (_isIpcUrl(url)) {
      if (normalizedScheme != 'sparkle-service' &&
          url.substring(url.indexOf(':') + 1).trim().isEmpty) {
        throw const FormatException('目标服务 IPC 路径不能为空');
      }
      return url;
    }

    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasAuthority || parsed.host.isEmpty) {
      throw const FormatException('目标服务地址无效');
    }
    if (type == BackendType.surgeController &&
        (!parsed.hasPort ||
            (parsed.path.isNotEmpty && parsed.path != '/') ||
            parsed.hasQuery ||
            parsed.hasFragment)) {
      throw const FormatException('Surge 控制器地址必须包含端口且不能包含路径或参数');
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const FormatException('请使用 secret 参数传递密钥');
    }
    return url;
  }

  static bool _isIpcUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('unix:') ||
        lower.startsWith('pipe:') ||
        lower.startsWith('sparkle-service:');
  }

  static bool _isSecureUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('https:') || lower.startsWith('grpcs:');
  }

  static bool _parseBool(String? value) => switch (value?.toLowerCase()) {
    '1' || 'true' || 'yes' || 'on' => true,
    _ => false,
  };

  static String _defaultName(String baseUrl, BackendType type) {
    final parsed = Uri.tryParse(baseUrl);
    if (parsed != null && parsed.host.isNotEmpty) return parsed.host;
    return type.label;
  }
}

class ControllerStore extends ChangeNotifier {
  /// Reserved id for the embedded kernel on supported platforms.
  static const localId = 'local-core';

  ControllerStore._(this._store);

  final JsonStore _store;
  List<Controller> _controllers = [];
  String? _activeId;

  Map<String, dynamic> get _section => _store.section('controllers');

  static Future<ControllerStore> load(
    JsonStore store, {
    bool localCoreSupported = false,
  }) async {
    final s = ControllerStore._(store);
    s._restore();
    final localCore = Controller(
      id: localId,
      name: '本地代理',
      baseUrl: 'local://core',
    );
    s._controllers.removeWhere((c) => c.id == localCore.id);
    if (localCoreSupported) {
      s._controllers = [localCore, ...s._controllers];
    } else if (s._controllers.isEmpty) {
      s._controllers = [
        Controller(
          id: _newId(),
          name: '本地内核',
          baseUrl: 'http://127.0.0.1:9090',
        ),
      ];
    }
    if (!s._controllers.any((controller) => controller.id == s._activeId)) {
      s._activeId = s._controllers.first.id;
    }
    await s._persist();
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
    String icon = '',
    String secret = '',
    bool allowInsecure = false,
  }) async {
    final controller = Controller(
      id: _newId(),
      name: name,
      type: type,
      baseUrl: baseUrl,
      icon: icon,
      secret: secret,
      allowInsecure: allowInsecure,
    );
    _controllers = [..._controllers, controller];
    _activeId ??= controller.id;
    await _persist();
    notifyListeners();
    return controller;
  }

  Future<Controller> addDraft(ControllerDraft draft) => add(
    name: draft.name,
    type: draft.type,
    baseUrl: draft.baseUrl,
    icon: draft.icon,
    secret: draft.secret,
    allowInsecure: draft.allowInsecure,
  );

  Future<void> update(
    String id, {
    String? name,
    BackendType? type,
    String? baseUrl,
    String? icon,
    String? secret,
    bool? allowInsecure,
  }) async {
    if (id == localId) return;
    _controllers = _controllers
        .map(
          (c) => c.id == id
              ? c.copyWith(
                  name: name,
                  type: type,
                  baseUrl: baseUrl,
                  icon: icon,
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
    if (id == localId) return;
    _controllers = _controllers.where((c) => c.id != id).toList();
    if (_activeId == id) {
      _activeId = _controllers.isEmpty ? null : _controllers.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    RangeError.checkValidIndex(oldIndex, _controllers, 'oldIndex');
    RangeError.checkValidIndex(newIndex, _controllers, 'newIndex');
    if (oldIndex == newIndex) return;
    final localPinned = _controllers.first.id == localId;
    if (localPinned && (oldIndex == 0 || newIndex == 0)) return;

    final reordered = List<Controller>.of(_controllers);
    final controller = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, controller);
    _controllers = reordered;
    notifyListeners();
    await _persist();
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
