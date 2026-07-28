import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const credential = OAuthCredential(
    provider: AuthProvider.kakao,
    type: OAuthCredentialType.accessToken,
    value: 'provider-access-token',
  );

  test('Provider Token과 deviceId를 백엔드에 보내고 서비스 세션을 저장한다', () async {
    final adapter = _QueuedResponseAdapter([
      _successResponse(
        user: {
          'userId': 42,
          'role': null,
          'nickname': null,
          'email': null,
          'emailRequired': true,
          'accountStatus': 'PENDING',
          'onboardingCompleted': false,
        },
      ),
    ]);
    final store = InMemoryAuthSessionStore();
    late final ApiClient apiClient;
    final repository = RemoteAuthRepository(
      apiClient: () => apiClient,
      deviceIdProvider: const _FixedDeviceIdProvider('install-001'),
      sessionStore: store,
    );
    apiClient = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      httpClientAdapter: adapter,
    );

    final session = await repository.signIn(credential);

    expect(adapter.requests.single.path, 'auth/oauth/kakao');
    expect(adapter.requests.single.data, {
      'accessToken': 'provider-access-token',
      'idToken': null,
      'deviceId': 'install-001',
    });
    expect(session.user.id, '42');
    expect(session.user.provider, AuthProvider.kakao);
    expect(session.user.role, isNull);
    expect(session.user.emailRequired, isTrue);
    expect(session.requiresAdditionalEmail, isTrue);
    expect(await store.read(), session);
  });

  test('Refresh Token을 rotation하고 저장된 Token pair를 교체한다', () async {
    final adapter = _QueuedResponseAdapter([
      _successResponse(
        accessToken: 'access-token-1',
        refreshToken: 'refresh-token-1',
      ),
      _successResponse(
        accessToken: 'access-token-2',
        refreshToken: 'refresh-token-2',
      ),
    ]);
    late final ApiClient apiClient;
    final repository = RemoteAuthRepository(
      apiClient: () => apiClient,
      deviceIdProvider: const _FixedDeviceIdProvider('install-001'),
      sessionStore: InMemoryAuthSessionStore(),
    );
    apiClient = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      httpClientAdapter: adapter,
    );
    await repository.signIn(credential);

    final refreshed = await repository.refreshAccessToken();

    expect(refreshed, isTrue);
    expect(adapter.requests.last.path, 'auth/reissue');
    expect(adapter.requests.last.data, {
      'refreshToken': 'refresh-token-1',
      'deviceId': 'install-001',
    });
    expect(await repository.readAccessToken(), 'access-token-2');
    expect(
      (await repository.restoreSession())?.tokens.refreshToken,
      'refresh-token-2',
    );
  });

  test('온보딩 시 USER 약관을 조회하고 동의 내역을 백엔드 계약으로 변환한다', () async {
    final adapter = _QueuedResponseAdapter([
      _successResponse(
        user: {
          'userId': 42,
          'role': null,
          'nickname': null,
          'email': 'guardian@example.com',
          'emailRequired': false,
          'accountStatus': 'PENDING',
          'onboardingCompleted': false,
        },
      ),
      ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': [
            {'termId': 1, 'termCode': 'SERVICE_TOS'},
            {'termId': 2, 'termCode': 'MARKETING'},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
      ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': {
            'userId': 42,
            'role': 'GUARDIAN',
            'nickname': '도담 보호자',
            'email': 'guardian@example.com',
            'emailRequired': false,
            'accountStatus': 'ACTIVE',
            'onboardingCompleted': true,
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    ]);
    late final ApiClient apiClient;
    final repository = RemoteAuthRepository(
      apiClient: () => apiClient,
      deviceIdProvider: const _FixedDeviceIdProvider('install-001'),
      sessionStore: InMemoryAuthSessionStore(),
    );
    apiClient = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      httpClientAdapter: adapter,
    );
    await repository.signIn(credential);

    final session = await repository.completeOnboarding(
      NewUserOnboardingInput(
        profile: const OnboardingProfileInput(
          role: UserRole.guardian,
          nickname: '도담 보호자',
        ),
        consents: ConsentAgreementInput(
          agreedConsents: {ConsentCode.serviceTerms},
        ),
      ),
    );

    expect(adapter.requests[1].path, 'consents/terms');
    expect(adapter.requests[1].queryParameters, {'targetScope': 'USER'});
    expect(adapter.requests[2].path, 'users/me/onboarding');
    expect(adapter.requests[2].data, {
      'role': 'GUARDIAN',
      'nickname': '도담 보호자',
      'email': 'guardian@example.com',
      'profileImageFileId': null,
      'consents': [
        {'termId': 1, 'action': 'AGREE'},
        {'termId': 2, 'action': 'WITHDRAW'},
      ],
    });
    expect(session.user.role, UserRole.guardian);
    expect(session.user.onboardingCompleted, isTrue);
  });

  test('백엔드 OAuth Credential 오류를 AuthFailure로 매핑한다', () async {
    final adapter = _QueuedResponseAdapter([
      ResponseBody.fromString(
        jsonEncode({
          'success': false,
          'code': 'AUTH_401_001',
          'message': 'OAuth 인증 정보가 유효하지 않습니다.',
          'data': null,
        }),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    ]);
    late final ApiClient apiClient;
    final repository = RemoteAuthRepository(
      apiClient: () => apiClient,
      deviceIdProvider: const _FixedDeviceIdProvider('install-001'),
      sessionStore: InMemoryAuthSessionStore(),
    );
    apiClient = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      httpClientAdapter: adapter,
    );

    await expectLater(
      repository.signIn(credential),
      throwsA(
        isA<AuthFailure>()
            .having(
              (failure) => failure.type,
              'type',
              AuthFailureType.invalidCredential,
            )
            .having((failure) => failure.code, 'code', 'AUTH_401_001'),
      ),
    );
  });

  test('Refresh 중 일시적인 서버 장애가 발생하면 저장된 세션을 보존한다', () async {
    final adapter = _QueuedResponseAdapter([
      _successResponse(),
      ResponseBody.fromString(
        jsonEncode({
          'success': false,
          'code': 'COMMON_500',
          'message': '일시적인 오류가 발생했습니다.',
          'data': null,
        }),
        503,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    ]);
    final store = InMemoryAuthSessionStore();
    late final ApiClient apiClient;
    final repository = RemoteAuthRepository(
      apiClient: () => apiClient,
      deviceIdProvider: const _FixedDeviceIdProvider('install-001'),
      sessionStore: store,
    );
    apiClient = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      httpClientAdapter: adapter,
    );
    final session = await repository.signIn(credential);

    expect(await repository.refreshAccessToken(), isFalse);
    expect(await store.read(), session);
  });

  test('Refresh Token이 무효하면 저장된 세션을 제거한다', () async {
    final adapter = _QueuedResponseAdapter([
      _successResponse(),
      ResponseBody.fromString(
        jsonEncode({
          'success': false,
          'code': 'AUTH_401_004',
          'message': 'Refresh Token이 유효하지 않습니다.',
          'data': null,
        }),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    ]);
    final store = InMemoryAuthSessionStore();
    late final ApiClient apiClient;
    final repository = RemoteAuthRepository(
      apiClient: () => apiClient,
      deviceIdProvider: const _FixedDeviceIdProvider('install-001'),
      sessionStore: store,
    );
    apiClient = ApiClient(
      environment: ApiEnvironment.fromBaseUrl('https://example.test'),
      httpClientAdapter: adapter,
    );
    await repository.signIn(credential);

    expect(await repository.refreshAccessToken(), isFalse);
    expect(await store.read(), isNull);
  });
}

ResponseBody _successResponse({
  String accessToken = 'service-access-token',
  String refreshToken = 'service-refresh-token',
  Map<String, dynamic>? user,
}) => ResponseBody.fromString(
  jsonEncode({
    'success': true,
    'code': 'COMMON_200',
    'message': '요청이 성공했습니다.',
    'data': {
      'grantType': 'Bearer',
      'accessToken': accessToken,
      'accessTokenExpiresInSeconds': 3600,
      'refreshToken': refreshToken,
      'refreshTokenExpiresInSeconds': 1209600,
      'user':
          user ??
          {
            'userId': 42,
            'role': 'GUARDIAN',
            'nickname': '도담 보호자',
            'email': 'guardian@example.com',
            'emailRequired': false,
            'accountStatus': 'ACTIVE',
            'onboardingCompleted': true,
          },
    },
  }),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final class _QueuedResponseAdapter implements HttpClientAdapter {
  _QueuedResponseAdapter(this._responses);

  final List<ResponseBody> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

final class _FixedDeviceIdProvider implements DeviceIdProvider {
  const _FixedDeviceIdProvider(this.deviceId);

  final String deviceId;

  @override
  Future<String> getDeviceId() async => deviceId;
}
