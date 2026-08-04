import 'named_avatar.dart';

/// Proxy avatar — image when [icon] is non-empty, otherwise a
/// color-tinted letter chip derived from [name].
class ProxyAvatar extends NamedAvatar {
  const ProxyAvatar({
    super.key,
    required super.name,
    super.icon = '',
    super.size = 44,
  });
}
