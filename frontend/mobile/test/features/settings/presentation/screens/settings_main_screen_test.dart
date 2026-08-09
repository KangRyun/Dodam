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

    expect(find.text('도담이 대장간'), findsOneWidget);
    expect(find.text('설정을 차근차근 정리해요'), findsOneWidget);
    expect(find.text('민지엄마 · 카카오 계정 연결됨'), findsOneWidget);
    expect(find.text('계정과 프로필'), findsOneWidget);
    expect(find.text('앱 사용 설정'), findsOneWidget);
    expect(find.text('서비스 정보'), findsOneWidget);
    expect(find.text('계정 관리'), findsOneWidget);
    expect(find.text('보호자 정보'), findsOneWidget);
    expect(find.text('동의 관리'), findsOneWidget);
    expect(find.text('알림 설정'), findsOneWidget);
    expect(find.text('데이터 보관 기간'), findsOneWidget);
    expect(find.text('약관 및 정책'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    expect(find.text('회원 탈퇴'), findsOneWidget);
    expect(find.text('개인정보 관리'), findsNothing);
    expect(find.text('아이 관리'), findsNothing);
    expect(find.text('전문가 인증'), findsNothing);
  });

  testWidgets('대장장이 도담이와 그룹 제목을 접근성 정보로 전달한다', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsMainScreen(user: session.user, onSignOut: () async {}),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('설정을 정리하는 대장장이 도담이'), findsOneWidget);
    expect(
      find.bySemanticsLabel('보호자 정보, 닉네임과 연결 계정을 확인하고 관리해요'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('계정과 프로필'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('지원 viewport와 text scale에서 overflow 없이 모든 설정에 접근한다', (
    tester,
  ) async {
    const scenarios = <({Size size, double textScale})>[
      (size: Size(1280, 800), textScale: 1),
      (size: Size(1280, 800), textScale: 2),
      (size: Size(844, 390), textScale: 1),
      (size: Size(844, 390), textScale: 2),
      (size: Size(390, 844), textScale: 1),
      (size: Size(390, 844), textScale: 2),
    ];

    for (final scenario in scenarios) {
      await tester.binding.setSurfaceSize(scenario.size);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scenario.textScale)),
            child: child!,
          ),
          home: SettingsMainScreen(user: session.user, onSignOut: () async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            '${scenario.size.width}×${scenario.size.height}, text scale ${scenario.textScale}',
      );
      expect(
        find.byKey(const ValueKey('settings-scroll-view')),
        findsOneWidget,
      );
      expect(find.text('설정'), findsOneWidget);
      expect(find.text('회원 탈퇴'), findsOneWidget);

      final profileTile = find.byKey(const ValueKey('settings-profile-tile'));
      await tester.ensureVisible(profileTile);
      expect(tester.getSize(profileTile).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    }

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('보호자 정보를 누르면 실제 프로필 관리 route로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/guardian/settings/profile': (_) =>
              const Scaffold(body: Text('보호자 정보 화면')),
        },
        home: SettingsMainScreen(user: session.user, onSignOut: () async {}),
      ),
    );

    final profileTile = find.byKey(const ValueKey('settings-profile-tile'));
    await tester.ensureVisible(profileTile);
    await tester.tap(profileTile);
    await tester.pumpAndSettle();

    expect(find.text('보호자 정보 화면'), findsOneWidget);
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
