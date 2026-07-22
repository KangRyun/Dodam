import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kakaoCredential = OAuthCredential(
    provider: AuthProvider.kakao,
    type: OAuthCredentialType.accessToken,
    value: 'mock-kakao-access-token',
  );

  group('AuthRepositoryImpl', () {
    test('기존 보호자는 온보딩 없이 인증된다', () async {
      final repository = AuthRepositoryImpl(responseDelay: Duration.zero);

      final session = await repository.signIn(kakaoCredential);
      final state = AuthState.fromSession(session);

      expect(state.status, AuthStatus.authenticated);
      expect(session.user.role, UserRole.guardian);
      expect(session.requiresOnboarding, isFalse);
      expect(session.user.provider, AuthProvider.kakao);
    });

    test('신규 사용자는 온보딩 필요 상태가 된다', () async {
      final repository = AuthRepositoryImpl(
        scenario: MockAuthScenario.newGuardian,
        responseDelay: Duration.zero,
      );

      final session = await repository.signIn(kakaoCredential);
      final state = AuthState.fromSession(session);

      expect(state.status, AuthStatus.onboardingRequired);
      expect(session.requiresOnboarding, isTrue);
      expect(session.requiresAdditionalEmail, isFalse);
    });

    test('이메일 미제공 신규 사용자를 구분한다', () async {
      final repository = AuthRepositoryImpl(
        scenario: MockAuthScenario.newUserWithoutEmail,
        responseDelay: Duration.zero,
      );

      final session = await repository.signIn(kakaoCredential);

      expect(session.requiresAdditionalEmail, isTrue);
    });

    test('네트워크 실패는 재시도 가능한 실패로 반환된다', () async {
      final repository = AuthRepositoryImpl(
        scenario: MockAuthScenario.networkFailure,
        responseDelay: Duration.zero,
      );

      await expectLater(
        repository.signIn(kakaoCredential),
        throwsA(
          isA<AuthFailure>()
              .having(
                (failure) => failure.type,
                'type',
                AuthFailureType.network,
              )
              .having((failure) => failure.canRetry, 'canRetry', isTrue),
        ),
      );
    });

    test('로그아웃하면 저장된 Mock 세션이 제거된다', () async {
      final repository = AuthRepositoryImpl(responseDelay: Duration.zero);
      await repository.signIn(kakaoCredential);

      expect(await repository.restoreSession(), isNotNull);
      await repository.signOut();

      expect(await repository.restoreSession(), isNull);
    });

    test('Provider별로 합의된 토큰 종류만 허용한다', () async {
      final repository = AuthRepositoryImpl(responseDelay: Duration.zero);
      const invalidGoogleCredential = OAuthCredential(
        provider: AuthProvider.google,
        type: OAuthCredentialType.accessToken,
        value: 'google-access-token-is-not-accepted',
      );

      await expectLater(
        repository.signIn(invalidGoogleCredential),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.type,
            'type',
            AuthFailureType.invalidCredential,
          ),
        ),
      );
    });

    test('Google 로그인은 ID Token을 허용한다', () async {
      final repository = AuthRepositoryImpl(responseDelay: Duration.zero);
      const googleCredential = OAuthCredential(
        provider: AuthProvider.google,
        type: OAuthCredentialType.idToken,
        value: 'mock-google-id-token',
      );

      final session = await repository.signIn(googleCredential);

      expect(session.user.provider, AuthProvider.google);
    });
  });
}
