import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/reduced_motion.dart';

void main() {
  useReducedMotionForTests();

  testWidgets('기존 보호자 로그인 완료 후 프로필 선택 이동을 요청한다', (tester) async {
    var movedToProfileSelection = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationFlowScreen(
          onSignIn: (_) async => AuthState.authenticated(
            _session(role: UserRole.guardian, onboardingCompleted: true),
          ),
          onCompleteOnboarding: (_) async =>
              _session(role: UserRole.guardian, onboardingCompleted: true),
          onProfileSelectionRequired: (_) => movedToProfileSelection = true,
          onExpertAuthenticated: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-kakao')));
    await tester.pumpAndSettle();

    expect(movedToProfileSelection, isTrue);
  });

  testWidgets('신규 사용자는 로그인 후 기본 정보 입력 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationFlowScreen(
          onSignIn: (_) async => AuthState.onboardingRequired(
            _session(role: UserRole.guardian, onboardingCompleted: false),
          ),
          onCompleteOnboarding: (_) async =>
              _session(role: UserRole.guardian, onboardingCompleted: true),
          onProfileSelectionRequired: (_) {},
          onExpertAuthenticated: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-google')));
    await tester.pumpAndSettle();

    expect(find.text('도담에서 어떻게 활동할까요?'), findsOneWidget);
  });

  testWidgets('전문가 로그인 완료 시 전문가 화면 이동을 요청한다', (tester) async {
    var movedToExpertProfile = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationFlowScreen(
          onSignIn: (_) async => AuthState.authenticated(
            _session(role: UserRole.expert, onboardingCompleted: true),
          ),
          onCompleteOnboarding: (_) async =>
              _session(role: UserRole.expert, onboardingCompleted: true),
          onProfileSelectionRequired: (_) {},
          onExpertAuthenticated: (_) => movedToExpertProfile = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-login-naver')));
    await tester.pumpAndSettle();

    expect(movedToExpertProfile, isTrue);
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
