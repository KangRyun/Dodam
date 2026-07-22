import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocialLoginService', () {
    test('카카오는 Access Token으로 로그인한다', () async {
      final repository = _RecordingAuthRepository();
      final service = SocialLoginService(repository);

      final state = await service.signInWithKakao('kakao-access-token');

      expect(state.status, AuthStatus.authenticated);
      expect(repository.lastCredential?.provider, AuthProvider.kakao);
      expect(repository.lastCredential?.type, OAuthCredentialType.accessToken);
    });

    test('구글은 ID Token으로 로그인한다', () async {
      final repository = _RecordingAuthRepository();
      final service = SocialLoginService(repository);

      await service.signInWithGoogle('google-id-token');

      expect(repository.lastCredential?.provider, AuthProvider.google);
      expect(repository.lastCredential?.type, OAuthCredentialType.idToken);
    });

    test('네이버는 Access Token으로 로그인한다', () async {
      final repository = _RecordingAuthRepository();
      final service = SocialLoginService(repository);

      await service.signInWithNaver('naver-access-token');

      expect(repository.lastCredential?.provider, AuthProvider.naver);
      expect(repository.lastCredential?.type, OAuthCredentialType.accessToken);
    });

    test('로그인 요청 중 연속 호출은 같은 요청 결과를 공유한다', () async {
      final completer = Completer<AuthSession>();
      final repository = _RecordingAuthRepository(result: completer.future);
      final service = SocialLoginService(repository);

      final first = service.signInWithKakao('kakao-access-token');
      final second = service.signInWithKakao('kakao-access-token');

      expect(service.isSigningIn, isTrue);
      expect(repository.signInCallCount, 1);

      completer.complete(_mockSession(AuthProvider.kakao));
      final states = await Future.wait([first, second]);

      expect(states.every((state) => state.isSignedIn), isTrue);
      expect(service.isSigningIn, isFalse);
    });

    test('Repository 인증 실패를 화면용 실패 상태로 변환한다', () async {
      final repository = _RecordingAuthRepository(
        failure: const AuthFailure(
          type: AuthFailureType.network,
          message: '인터넷 연결을 확인해 주세요.',
        ),
      );
      final service = SocialLoginService(repository);

      final state = await service.signInWithKakao('kakao-access-token');

      expect(state.status, AuthStatus.failure);
      expect(state.failure?.type, AuthFailureType.network);
      expect(state.failure?.canRetry, isTrue);
    });
  });
}

class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository({this.result, this.failure});

  final Future<AuthSession>? result;
  final AuthFailure? failure;
  OAuthCredential? lastCredential;
  int signInCallCount = 0;

  @override
  Future<AuthSession> signIn(OAuthCredential credential) async {
    signInCallCount++;
    lastCredential = credential;
    if (failure case final failure?) throw failure;
    return result ?? _mockSession(credential.provider);
  }

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) =>
      throw UnimplementedError();

  @override
  Future<AuthSession?> restoreSession() => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}

AuthSession _mockSession(AuthProvider provider) => AuthSession(
  user: AuthenticatedUser(
    id: 'user-001',
    provider: provider,
    providerUserId: 'provider-user-001',
    role: UserRole.guardian,
    onboardingCompleted: true,
  ),
  tokens: const AuthTokens(
    accessToken: 'service-access-token',
    refreshToken: 'service-refresh-token',
  ),
);
