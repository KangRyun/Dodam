import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('기존 보호자 로그인 완료 후 보호자 홈 이동을 요청한다', (tester) async {
    var movedToGuardianHome = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationFlowScreen(
          onSignIn: (_) async => AuthState.authenticated(
            _session(role: UserRole.guardian, onboardingCompleted: true),
          ),
          onGuardianAuthenticated: (_) => movedToGuardianHome = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
    await tester.pumpAndSettle();

    expect(movedToGuardianHome, isTrue);
  });

  testWidgets('신규 사용자는 로그인 후 기본 정보 입력 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationFlowScreen(
          onSignIn: (_) async => AuthState.onboardingRequired(
            _session(role: UserRole.guardian, onboardingCompleted: false),
          ),
          onGuardianAuthenticated: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-google')));
    await tester.pumpAndSettle();

    expect(find.text('도담에서 어떻게 활동할까요?'), findsOneWidget);
  });

  testWidgets('전문가 로그인 완료 시 1차 MVP 미지원 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationFlowScreen(
          onSignIn: (_) async => AuthState.authenticated(
            _session(role: UserRole.expert, onboardingCompleted: true),
          ),
          onGuardianAuthenticated: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-naver')));
    await tester.pumpAndSettle();

    expect(find.text('아직 준비 중인 기능이에요'), findsOneWidget);
    expect(find.text('로그인 화면으로 돌아가기'), findsOneWidget);
  });
}

AuthSession _session({
  required UserRole role,
  required bool onboardingCompleted,
}) => AuthSession(
  user: AuthenticatedUser(
    id: 'test-user',
    provider: AuthProvider.kakao,
    providerUserId: 'provider-user',
    role: role,
    onboardingCompleted: onboardingCompleted,
    email: 'user@dodam.test',
  ),
  tokens: AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    accessTokenExpiresAt: DateTime(2026, 7, 22, 23, 59),
  ),
);
