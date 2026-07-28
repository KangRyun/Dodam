import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/settings/presentation/screens/settings_main_screen.dart';

void main() {
  const session = AuthSession(
    user: AuthenticatedUser(
      id: 'guardian-1',
      provider: AuthProvider.kakao,
      providerUserId: 'kakao-1',
      role: UserRole.guardian,
      onboardingCompleted: true,
      nickname: '민지엄마',
    ),
    tokens: AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessTokenExpiresAt: null,
    ),
  );

  testWidgets('설정 메인에 사용자와 보호자용 메뉴를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsMainScreen(
          loadSession: () async => session,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('민지엄마'), findsOneWidget);
    expect(find.text('카카오 계정 연결됨'), findsOneWidget);
    expect(find.text('내 정보 관리'), findsOneWidget);
    expect(find.text('동의 관리'), findsOneWidget);
    expect(find.text('알림 설정'), findsOneWidget);
    expect(find.text('데이터 보관 기간'), findsOneWidget);
    expect(find.text('약관 및 정책'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    expect(find.text('회원 탈퇴'), findsOneWidget);
    expect(find.text('아이 관리'), findsNothing);
    expect(find.text('전문가 인증'), findsNothing);
  });
}
