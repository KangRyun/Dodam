import 'package:dodam/features/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kakaoCredential = OAuthCredential(
    provider: AuthProvider.kakao,
    type: OAuthCredentialType.authorizationCode,
    value: 'mock-authorization-code',
  );

  group('MockAuthRepository', () {
    test('기존 보호자는 온보딩 없이 인증된다', () async {
      final repository = MockAuthRepository(responseDelay: Duration.zero);

      final session = await repository.signIn(kakaoCredential);
      final state = AuthState.fromSession(session);

      expect(state.status, AuthStatus.authenticated);
      expect(session.user.role, UserRole.guardian);
      expect(session.requiresOnboarding, isFalse);
      expect(session.user.provider, AuthProvider.kakao);
    });

    test('신규 사용자는 온보딩 필요 상태가 된다', () async {
      final repository = MockAuthRepository(
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
      final repository = MockAuthRepository(
        scenario: MockAuthScenario.newUserWithoutEmail,
        responseDelay: Duration.zero,
      );

      final session = await repository.signIn(kakaoCredential);

      expect(session.requiresAdditionalEmail, isTrue);
    });

    test('네트워크 실패는 재시도 가능한 실패로 반환된다', () async {
      final repository = MockAuthRepository(
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
      final repository = MockAuthRepository(responseDelay: Duration.zero);
      await repository.signIn(kakaoCredential);

      expect(await repository.restoreSession(), isNotNull);
      await repository.signOut();

      expect(await repository.restoreSession(), isNull);
    });
  });
}
