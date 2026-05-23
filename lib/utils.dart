String formatBytes(BigInt bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = size >= 100 || unit == 0 ? 0 : 1;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<String> asStringList(Object? value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  return const [];
}

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

enum DelayBucket { untested, timeout, fast, slow }

DelayBucket classifyDelay(int ms) {
  if (ms < 0) return DelayBucket.untested;
  if (ms == 0) return DelayBucket.timeout;
  if (ms < 500) return DelayBucket.fast;
  return DelayBucket.slow;
}

String delayLabel(int ms) => switch (classifyDelay(ms)) {
  DelayBucket.untested => '测试',
  DelayBucket.timeout => '超时',
  DelayBucket.fast || DelayBucket.slow => '$ms',
};

BigInt asBigInt(Object? v) {
  if (v is BigInt) return v;
  if (v is int) return BigInt.from(v);
  if (v is num) return BigInt.from(v.toInt());
  if (v is String) return BigInt.tryParse(v) ?? BigInt.zero;
  return BigInt.zero;
}

