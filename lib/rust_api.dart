/// Single import surface for the generated flutter_rust_bridge bindings.
/// Re-exports keep screen code stable when we reorganize the Rust side.
library;

import 'controller.dart' as ctl;
import 'src/rust/backend/api/target.dart' as api;

export 'src/rust/backend/api/connections.dart';
export 'src/rust/backend/api/control.dart';
export 'src/rust/backend/api/providers.dart';
export 'src/rust/backend/api/proxies.dart';
export 'src/rust/backend/api/proxy_delay.dart';
export 'src/rust/backend/api/resources.dart';
export 'src/rust/backend/api/rules.dart';
export 'src/rust/backend/api/streams.dart';
export 'src/rust/backend/api/target.dart';
export 'src/rust/backend/api/types.dart';
export 'src/rust/utils/error.dart';

api.BackendTarget backendTargetForController(ctl.Controller c) =>
    api.BackendTarget(
      backendType: switch (c.type) {
        ctl.BackendType.clash => api.BackendType.clash,
        ctl.BackendType.surge => api.BackendType.surge,
        ctl.BackendType.singBox => api.BackendType.singBox,
      },
      baseUrl: c.baseUrl,
      secret: c.secret.isEmpty ? null : c.secret,
      allowInsecure: c.allowInsecure,
    );
