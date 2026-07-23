final class PublicApiPath {
  const PublicApiPath._();

  static String normalize(String path) {
    final value = path.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(path, 'path', 'API path cannot be empty.');
    }

    final uri = Uri.tryParse(value);
    if (uri == null || uri.hasScheme || uri.hasAuthority) {
      throw ArgumentError.value(
        path,
        'path',
        'Only relative public API paths are allowed.',
      );
    }

    final normalized = value.replaceFirst(RegExp(r'^/+'), '');
    if (normalized == 'internal' || normalized.startsWith('internal/')) {
      throw ArgumentError.value(
        path,
        'path',
        '/internal/** is forbidden in the Flutter client.',
      );
    }
    if (normalized == 'api/v1' || normalized.startsWith('api/v1/')) {
      throw ArgumentError.value(
        path,
        'path',
        'The /api/v1 prefix is already applied by ApiEnvironment.',
      );
    }
    if (uri.pathSegments.contains('..')) {
      throw ArgumentError.value(
        path,
        'path',
        'Parent path segments are forbidden.',
      );
    }

    return normalized;
  }
}
