import 'src/rust/error.dart';

/// Friendly Chinese formatter for the FFI error type. With this extension in
/// scope, `'$e'` and `e.message` produce a readable string instead of the
/// default `Instance of 'MihomoError_*'`.
extension MihomoErrorMessage on MihomoError {
  String get message => switch (this) {
    MihomoError_InvalidUrl(:final field0) => '无效的 mihomo 地址:$field0',
    MihomoError_InvalidRegex(:final pattern, :final message) =>
      '正则 `$pattern` 无效:$message',
    MihomoError_Upstream(:final status, :final body) =>
      'mihomo 返回 $status: $body',
    MihomoError_Network(:final field0) => '网络错误:$field0',
    MihomoError_InvalidJson(:final field0) => '返回 JSON 解析失败:$field0',
    MihomoError_Other(:final field0) => field0,
  };
}

/// Format an arbitrary thrown object — handles MihomoError specifically and
/// falls back to `toString()` for anything else.
String formatError(Object error) {
  if (error is MihomoError) return error.message;
  return error.toString();
}
