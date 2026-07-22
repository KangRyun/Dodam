import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('저장된 보호자 세션이 있으면 보호자 홈 이동을 요청한다', (tester) async {
    var guardianNavigationCount = 0;
    var loginNavigationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthBootstrapScreen(
          restoreSession: () async => _session(),
          onGuardianAuthenticated: (_) => guardianNavigationCount += 1,
          onLoginRequired: (_) => loginNavigationCount += 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(guardianNavigationCount, 1);
    expect(loginNavigationCount, 0);
  });

  testWidgets('저장된 세션이 없으면 로그인 화면 이동을 요청한다', (tester) async {
    var guardianNavigationCount = 0;
    var loginNavigationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthBootstrapScreen(
          restoreSession: () async => null,
          onGuardianAuthenticated: (_) => guardianNavigationCount += 1,
          onLoginRequired: (_) => loginNavigationCount += 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(guardianNavigationCount, 0);
    expect(loginNavigationCount, 1);
  });
}

AuthSession _session() => AuthSession(
  user: const AuthenticatedUser(
    id: 'guardian-1',
    provider: AuthProvider.kakao,
    providerUserId: 'provider-1',
    role: UserRole.guardian,
    onboardingCompleted: true,
    email: 'guardian@dodam.test',
    nickname: '민지엄마',
  ),
  tokens: AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    accessTokenExpiresAt: DateTime(2026, 7, 24),
  ),
);
