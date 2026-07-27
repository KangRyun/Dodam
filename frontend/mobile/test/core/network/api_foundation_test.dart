import 'dart:typed_data';

import 'package:dodam/core/network/network.dart';
import 'package:dio/dio.dart';
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

  test('ApiError는 현재 공통 오류 응답의 code와 message를 파싱한다', () {
    final error = ApiError.fromJson({
      'success': false,
      'code': 'AUTH_401_001',
      'message': 'OAuth 인증 정보가 유효하지 않습니다.',
      'data': null,
    });

    expect(error.code, 'AUTH_401_001');
    expect(error.message, 'OAuth 인증 정보가 유효하지 않습니다.');
    expect(error.timestamp, isNull);
    expect(error.path, isNull);
  });

  test('ApiError는 Backend Validation 상세 응답을 파싱한다', () {
    final error = ApiError.fromJson({
      'success': false,
      'code': 'COMMON_400_001',
      'message': '요청 값이 올바르지 않습니다.',
      'data': {
        'fieldErrors': [
          {'field': 'childName', 'message': '아동 이름은 필수입니다.'},
        ],
        'globalErrors': ['요청 조합이 올바르지 않습니다.'],
      },
    });

    expect(error.errors.single.field, 'childName');
    expect(error.errors.single.reason, '아동 이름은 필수입니다.');
    expect(error.globalErrors, ['요청 조합이 올바르지 않습니다.']);
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

  test('401 응답이면 Token을 한 번 재발급하고 새 헤더로 요청을 재시도한다', () async {
    final tokens = _MutableTokenProvider('expired-access-token');
    final refresher = _TestTokenRefresher(() async {
      tokens.accessToken = 'refreshed-access-token';
      return true;
    });
    final server = _UnauthorizedOnceAdapter();
    final client = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      accessTokenProvider: tokens,
      tokenRefresher: refresher,
      httpClientAdapter: server,
    );

    final response = await client.get<Map<String, dynamic>>('children');

    expect(response.data, {'ok': true});
    expect(refresher.callCount, 1);
    expect(server.authorizationHeaders, [
      'Bearer expired-access-token',
      'Bearer refreshed-access-token',
    ]);
  });

  test('재시도 요청도 401이면 추가 재발급 없이 오류를 반환한다', () async {
    final tokens = _MutableTokenProvider('expired-access-token');
    final refresher = _TestTokenRefresher(() async {
      tokens.accessToken = 'refreshed-access-token';
      return true;
    });
    final client = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      accessTokenProvider: tokens,
      tokenRefresher: refresher,
      httpClientAdapter: _AlwaysUnauthorizedAdapter(),
    );

    await expectLater(
      client.get<Map<String, dynamic>>('children'),
      throwsA(isA<ApiResponseFailure>()),
    );
    expect(refresher.callCount, 1);
  });
}

final class _MutableTokenProvider implements AccessTokenProvider {
  _MutableTokenProvider(this.accessToken);

  String? accessToken;

  @override
  Future<String?> readAccessToken() async => accessToken;
}

final class _TestTokenRefresher implements TokenRefresher {
  _TestTokenRefresher(this._refresh);

  final Future<bool> Function() _refresh;
  int callCount = 0;

  @override
  Future<bool> refreshAccessToken() {
    callCount += 1;
    return _refresh();
  }
}

final class _UnauthorizedOnceAdapter implements HttpClientAdapter {
  final List<String?> authorizationHeaders = [];
  int _requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorizationHeaders.add(options.headers['Authorization'] as String?);
    _requestCount += 1;
    if (_requestCount == 1) {
      return ResponseBody.fromString(
        '{"success":false,"code":"AUTH_EXPIRED"}',
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _AlwaysUnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"success":false,"code":"AUTH_EXPIRED"}',
    401,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
