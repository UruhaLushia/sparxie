import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller.dart' as ctl;
import '../rust_api.dart' as rust;

/// UI projection of the Rust-owned core snapshot stream.
class CoreController extends ChangeNotifier {
  CoreController({required this.store}) {
    _snapshot = rust.coreSnapshot();
    _sub = rust.coreEvents().listen(_onSnapshot);
    if (_snapshot.state == rust.CoreState.running) {
      _activateLocal();
    }
  }

  final ctl.ControllerStore store;

  late rust.CoreSnapshot _snapshot;
  String? _previousActiveId;
  bool _wired = false;
  Future<void> _settingsWrites = Future.value();
  StreamSubscription<rust.CoreSnapshot>? _sub;

  VoidCallback? onStopped;

  rust.CoreConfig get settings => _snapshot.settings;
  rust.CoreState get state => _snapshot.state;
  bool get tunAttached => _snapshot.tunAttached;
  bool get tunIpv6 => _snapshot.tunIpv6;
  String get lastError => _snapshot.lastError;

  bool get running =>
      state == rust.CoreState.running ||
      state == rust.CoreState.starting ||
      state == rust.CoreState.stopping;

  void _onSnapshot(rust.CoreSnapshot snapshot) {
    final previous = _snapshot.state;
    _snapshot = snapshot;
    if (snapshot.state == rust.CoreState.running &&
        previous != snapshot.state) {
      _activateLocal();
    } else if ((snapshot.state == rust.CoreState.stopped ||
            snapshot.state == rust.CoreState.error) &&
        previous != snapshot.state) {
      onStopped?.call();
      _restorePreviousController();
    }
    notifyListeners();
  }

  Future<void> _command(Future<void> Function() command) async {
    try {
      await command();
    } catch (_) {}
    _onSnapshot(rust.coreSnapshot());
  }

  Future<void> start() => _command(rust.coreStart);

  Future<void> stop() => _command(rust.coreStop);

  Future<void> updateTun(
    rust.TunSettings Function(rust.TunSettings current) update,
  ) {
    return updateSettings((current) {
      return rust.CoreConfig(
        mixedPort: current.mixedPort,
        port: current.port,
        socksPort: current.socksPort,
        allowLan: current.allowLan,
        logLevel: current.logLevel,
        externalController: current.externalController,
        secret: current.secret,
        tun: update(current.tun),
      );
    });
  }

  Future<void> updateSettings(
    rust.CoreConfig Function(rust.CoreConfig current) update,
  ) {
    final operation = _settingsWrites.catchError((_) {}).then((_) async {
      await _command(
        () => rust.coreUpdateSettings(config: update(_snapshot.settings)),
      );
    });
    _settingsWrites = operation;
    return operation;
  }

  void _activateLocal() {
    final previous = store.activeId;
    if (previous != ctl.ControllerStore.localId) {
      _previousActiveId = previous;
    }
    _wired = true;
    if (store.activeId != ctl.ControllerStore.localId) {
      unawaited(store.activate(ctl.ControllerStore.localId));
    }
  }

  void _restorePreviousController() {
    if (!_wired) return;
    _wired = false;
    final previous = _previousActiveId;
    _previousActiveId = null;
    if (previous != null && store.controllers.any((c) => c.id == previous)) {
      unawaited(store.activate(previous));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

extension TunSettingsCopy on rust.TunSettings {
  rust.TunSettings copyWith({
    bool? enabled,
    String? stack,
    String? dns,
    bool? ipv6,
    int? mtu,
    bool? allowBypass,
    String? bypassMode,
    String? bypassCustom,
    bool? systemProxy,
    String? accessMode,
    List<String>? accessPackages,
  }) => rust.TunSettings(
    enabled: enabled ?? this.enabled,
    stack: stack ?? this.stack,
    dns: dns ?? this.dns,
    ipv6: ipv6 ?? this.ipv6,
    mtu: mtu ?? this.mtu,
    allowBypass: allowBypass ?? this.allowBypass,
    bypassMode: bypassMode ?? this.bypassMode,
    bypassCustom: bypassCustom ?? this.bypassCustom,
    systemProxy: systemProxy ?? this.systemProxy,
    accessMode: accessMode ?? this.accessMode,
    accessPackages: accessPackages ?? this.accessPackages,
  );
}
