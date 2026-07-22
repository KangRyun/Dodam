/// Runtime configuration for the public Spring Boot API.
final class ApiEnvironment {
  ApiEnvironment._(this.apiBaseUri);

  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static const String publicApiPrefix = '/api/v1';

  final Uri apiBaseUri;

  /// Reads the server origin from `--dart-define=API_BASE_URL=...`.
  ///
  /// [API_BASE_URL] must be an origin such as `https://example.com`. The
  /// public API prefix is appended here so feature code cannot accidentally
  /// select an internal API namespace.
  factory ApiEnvironment.fromDartDefine() {
    return ApiEnvironment.fromBaseUrl(_configuredBaseUrl);
  }

  factory ApiEnvironment.fromBaseUrl(String baseUrl) {
    final value = baseUrl.trim();
    if (value.isEmpty) {
      throw StateError(
        'API_BASE_URL is required. Pass it with '
        '--dart-define=API_BASE_URL=https://example.com.',
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw FormatException('API_BASE_URL must be an absolute HTTP(S) URL.');
    }
    if (uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw FormatException(
        'API_BASE_URL must contain only the server origin.',
      );
    }

    return ApiEnvironment._(uri.replace(path: '$publicApiPrefix/'));
  }
}
