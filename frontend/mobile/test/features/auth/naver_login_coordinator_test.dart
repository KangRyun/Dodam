import 'dart:async';

import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NaverLoginCoordinator', () {
    test('네이버 Access Token을 백엔드 인증 계약으로 전달한다', () async {
      final repository = _RecordingAuthRepository();
      final coordinator = NaverLoginCoordinator(
        NaverLoginClientImpl(
          responseDelay: Duration.zero,
          accessToken: 'naver-access-token',
        ),
        SocialLoginService(repository),
      );

      final state = await coordinator.signIn();

      expect(state.status, AuthStatus.authenticated);
      expect(repository.credential?.provider, AuthProvider.naver);
      expect(repository.credential?.type, OAuthCredentialType.accessToken);
      expect(repository.credential?.value, 'naver-access-token');
    });

    test('사용자가 네이버 로그인을 취소하면 조용히 미인증 상태로 복귀한다', () async {
      final repository = _RecordingAuthRepository();
      final coordinator = NaverLoginCoordinator(
        NaverLoginClientImpl(
          scenario: NaverLoginScenario.cancelled,
          responseDelay: Duration.zero,
        ),
        SocialLoginService(repository),
      );

      final state = await coordinator.signIn();

      expect(state.status, AuthStatus.unauthenticated);
      expect(repository.signInCallCount, 0);
    });

    test('네이버 Provider 실패를 인증 실패 상태로 반환한다', () async {
      final coordinator = NaverLoginCoordinator(
        NaverLoginClientImpl(
          scenario: NaverLoginScenario.providerFailure,
          responseDelay: Duration.zero,
        ),
        SocialLoginService(_RecordingAuthRepository()),
      );

      final state = await coordinator.signIn();

      expect(state.status, AuthStatus.failure);
      expect(state.failure?.type, AuthFailureType.providerRejected);
    });

    test('신규 사용자의 네이버 인증 결과를 온보딩 필요 상태로 유지한다', () async {
      final coordinator = NaverLoginCoordinator(
        NaverLoginClientImpl(responseDelay: Duration.zero),
        SocialLoginService(
          AuthRepositoryImpl(
            scenario: MockAuthScenario.newGuardian,
            responseDelay: Duration.zero,
          ),
        ),
      );

      final state = await coordinator.signIn();

      expect(state.status, AuthStatus.onboardingRequired);
      expect(state.session?.user.provider, AuthProvider.naver);
    });

    test('연속 탭은 네이버 로그인 요청 하나를 공유한다', () async {
      final client = _PendingNaverLoginClient();
      final coordinator = NaverLoginCoordinator(
        client,
        SocialLoginService(_RecordingAuthRepository()),
      );

      final first = coordinator.signIn();
      final second = coordinator.signIn();
      expect(identical(first, second), isTrue);
      expect(client.signInCallCount, 1);

      client.complete();
      await first;
    });
  });
}

final class _RecordingAuthRepository implements AuthRepository {
  OAuthCredential? credential;
  int signInCallCount = 0;

  @override
  Future<AuthSession> signIn(OAuthCredential credential) async {
    signInCallCount += 1;
    this.credential = credential;
    return AuthSession(
      user: AuthenticatedUser(
        id: 'user-1',
        provider: credential.provider,
        providerUserId: 'naver-user-1',
        role: UserRole.guardian,
        onboardingCompleted: true,
      ),
      tokens: AuthTokens(
        accessToken: 'service-access-token',
        refreshToken: 'service-refresh-token',
        accessTokenExpiresAt: DateTime(2026, 7, 22, 18),
      ),
    );
  }

  @override
  Future<AuthTokens> refreshTokens(String refreshToken) =>
      throw UnimplementedError();

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}

final class _PendingNaverLoginClient implements NaverLoginClient {
  final Completer<NaverLoginResult> _completer = Completer();
  int signInCallCount = 0;

  @override
  Future<NaverLoginResult> signIn() {
    signInCallCount += 1;
    return _completer.future;
  }

  void complete() =>
      _completer.complete(const NaverLoginSuccess('naver-access-token'));
}
