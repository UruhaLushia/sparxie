abstract final class AppUpdateHttp {
  static const attempts = 3;

  static Map<String, String> apiHeaders(String token) =>
      _headers('application/vnd.github+json', token);

  static Map<String, String> assetHeaders(String token) =>
      _headers('application/octet-stream', token);

  static Map<String, String> _headers(String accept, String token) => {
    'Accept': accept,
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'Sparxie-Updater',
    if (token.trim() case final value when value.isNotEmpty)
      'Authorization': 'Bearer $value',
  };

  static bool isTransientStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  static Future<void> waitBeforeRetry(int attempt) =>
      Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 250 : 750));
}
