import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

bool get supportsProcessIdentity =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;
