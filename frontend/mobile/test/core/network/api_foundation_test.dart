import 'package:dodam/core/network/network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiEnvironment', () {
    test('adds the public API prefix to the configured origin', () {
      final environment = ApiEnvironment.fromBaseUrl('https://example.com');

      expect(environment.apiBaseUri.toString(), 'https://example.com/api/v1/');
    });

    test('rejects a base URL that already contains a path', () {
      expect(
        () => ApiEnvironment.fromBaseUrl('https://example.com/internal'),
        throwsFormatException,
      );
    });
  });

  group('PublicApiPath', () {
    test('normalizes a public resource path', () {
      expect(PublicApiPath.normalize('/children/1'), 'children/1');
    });

    test('rejects internal API paths', () {
      expect(
        () => PublicApiPath.normalize('/internal/ai/v1/analysis'),
        throwsArgumentError,
      );
    });

    test('rejects absolute URLs and duplicate public prefixes', () {
      expect(
        () => PublicApiPath.normalize('https://example.com/api/v1/users/me'),
        throwsArgumentError,
      );
      expect(
        () => PublicApiPath.normalize('/api/v1/users/me'),
        throwsArgumentError,
      );
    });
  });

  test('ApiError parses validation errors and allows them to be absent', () {
    final validationError = ApiError.fromJson({
      'timestamp': '2026-07-22T12:00:00Z',
      'path': '/api/v1/children',
      'code': 'VALIDATION_ERROR',
      'message': 'Invalid request.',
      'errors': [
        {'field': 'name', 'reason': 'must not be blank'},
      ],
    });
    final ordinaryError = ApiError.fromJson({
      'timestamp': '2026-07-22T12:00:00Z',
      'path': '/api/v1/children/1',
      'code': 'CHILD_NOT_FOUND',
      'message': 'Child not found.',
    });

    expect(validationError.errors.single.field, 'name');
    expect(ordinaryError.errors, isEmpty);
  });

  test('ApiPage parses the common top-level pagination shape', () {
    final page = ApiPage<int>.fromJson({
      'content': [
        {'id': 101},
        {'id': 102},
      ],
      'page': 0,
      'size': 2,
      'totalElements': 3,
      'totalPages': 2,
      'hasNext': true,
    }, (json) => json['id'] as int);

    expect(page.content, [101, 102]);
    expect(page.hasNext, isTrue);
  });

  test('SingleFlightTokenRefresher shares one in-flight refresh', () async {
    var callCount = 0;
    final refresher = SingleFlightTokenRefresher(() async {
      callCount += 1;
      await Future<void>.delayed(Duration.zero);
      return true;
    });

    final results = await Future.wait([
      refresher.refreshAccessToken(),
      refresher.refreshAccessToken(),
    ]);

    expect(results, [true, true]);
    expect(callCount, 1);
  });
}
