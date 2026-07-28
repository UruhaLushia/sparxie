import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

bool get supportsProcessIdentity =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

bool get supportsCustomTitleBar =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
