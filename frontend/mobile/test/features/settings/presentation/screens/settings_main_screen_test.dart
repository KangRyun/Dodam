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
        home: SettingsMainScreen(user: session.user, onSignOut: () async {}),
      ),
    );
    await tester.pump();

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

  testWidgets('설정 로그아웃을 취소하면 세션 초기화를 요청하지 않는다', (tester) async {
    var signOutCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsMainScreen(
          user: session.user,
          onSignOut: () async => signOutCount += 1,
        ),
      ),
    );

    final logoutAction = find.byKey(const ValueKey('settings-logout-action'));
    await tester.ensureVisible(logoutAction);
    await tester.tap(logoutAction);
    await tester.pumpAndSettle();
    expect(find.text('로그아웃할까요?'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
  });

  testWidgets('설정 로그아웃을 확인하면 세션 초기화를 요청하고 로그인 화면으로 이동한다', (tester) async {
    var signOutCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/auth/login': (_) => const Scaffold(body: Text('소셜 로그인'))},
        home: SettingsMainScreen(
          user: session.user,
          onSignOut: () async => signOutCount += 1,
        ),
      ),
    );

    final logoutAction = find.byKey(const ValueKey('settings-logout-action'));
    await tester.ensureVisible(logoutAction);
    await tester.tap(logoutAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃').last);
    await tester.pumpAndSettle();

    expect(signOutCount, 1);
    expect(find.text('소셜 로그인'), findsOneWidget);
  });

  testWidgets('약관 및 정책을 누르면 준비 중 안내 대신 약관 열람 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/guardian/settings/terms': (_) =>
              const Scaffold(body: Text('약관 및 정책 화면')),
        },
        home: SettingsMainScreen(user: session.user, onSignOut: () async {}),
      ),
    );

    final termsTile = find.byKey(const ValueKey('settings-terms-tile'));
    await tester.ensureVisible(termsTile);
    await tester.tap(termsTile);
    await tester.pumpAndSettle();

    expect(find.text('약관 및 정책 화면'), findsOneWidget);
    expect(find.textContaining('준비 중이에요'), findsNothing);
  });

  testWidgets('회원 탈퇴를 누르면 준비 중 안내 대신 탈퇴 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/guardian/settings/withdraw': (_) =>
              const Scaffold(body: Text('회원 탈퇴 확인 화면')),
        },
        home: SettingsMainScreen(user: session.user, onSignOut: () async {}),
      ),
    );

    final withdrawAction = find.byKey(
      const ValueKey('settings-withdraw-action'),
    );
    await tester.ensureVisible(withdrawAction);
    await tester.tap(withdrawAction);
    await tester.pumpAndSettle();

    expect(find.text('회원 탈퇴 확인 화면'), findsOneWidget);
    expect(find.textContaining('준비 중이에요'), findsNothing);
  });
}
