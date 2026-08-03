import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('프로필 선택에서 보호자를 누르면 보호자 홈으로 이동한다', (tester) async {
    await tester.pumpWidget(
      const DodamApp(initialRoute: AppRoutes.profileSelection),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('guardian-profile')));
    await tester.pumpAndSettle();

    expect(find.text('보호자 홈'), findsOneWidget);
  });

  testWidgets('보호자 홈 사이드바 "프로필 전환"은 프로필 선택 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(const DodamApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('guardian-switch-profile')));
    await tester.pumpAndSettle();

    expect(find.text('누가 도담을 이용하나요?'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-profile')), findsOneWidget);
  });

  testWidgets('프로필 선택에서 로그아웃하면 로그인 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      const DodamApp(initialRoute: AppRoutes.profileSelection),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('logout-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('social-login-kakao')), findsOneWidget);
  });

  testWidgets('프로필 선택에서 아동을 누르면 해당 아동 홈으로 이동한다', (tester) async {
    await tester.pumpWidget(
      const DodamApp(initialRoute: AppRoutes.profileSelection),
    );
    await tester.pumpAndSettle();

    final childProfile = find.byKey(const ValueKey('child-profile-3'));
    await tester.ensureVisible(childProfile);
    await tester.tap(childProfile);
    await tester.pumpAndSettle();

    expect(find.text('도담이, 오늘은 무엇을 그려 볼까?'), findsOneWidget);
  });

  testWidgets('프로필 선택에서 아이 추가를 누르면 등록 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      const DodamApp(initialRoute: AppRoutes.profileSelection),
    );
    await tester.pumpAndSettle();

    final addChildProfile = find.byKey(const ValueKey('add-child-profile'));
    await tester.ensureVisible(addChildProfile);
    await tester.tap(addChildProfile);
    await tester.pumpAndSettle();

    expect(find.text('아이 등록'), findsOneWidget);
  });

  testWidgets('보호자 홈의 아동 선택은 인라인 칩으로 처리한다(화면 이동 없음)', (tester) async {
    // 개편 전에는 "아동 선택 화면에서 보기"로 별도 화면(활동 대상 아동 선택)으로
    // 이동했지만, 지금은 홈 안 인라인 칩(_MiniSwitch)에서 바로 선택한다.
    await tester.pumpWidget(const DodamApp());
    await tester.pumpAndSettle();

    final childChip = find.byKey(const ValueKey('child-3'));
    expect(childChip, findsOneWidget);
    await tester.tap(childChip);
    await tester.pumpAndSettle();

    // 화면 이동 없이 보호자 홈에 그대로 머문다.
    expect(find.text('보호자 홈'), findsWidgets);
    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
  });

  testWidgets('선택 컨텍스트 없는 childId 직접 경로는 진입을 막는다', (tester) async {
    await tester.pumpWidget(
      DodamApp(initialRoute: AppRoutes.childModeHome('3')),
    );
    await tester.pumpAndSettle();

    expect(find.text('선택된 아동이 없어요'), findsOneWidget);
    expect(find.text('보호자 홈으로 이동'), findsOneWidget);
  });

  testWidgets('선택 컨텍스트 없이 Drawing 경로로 직접 진입하면 차단한다', (tester) async {
    await tester.pumpWidget(DodamApp(initialRoute: AppRoutes.drawing('3')));
    await tester.pumpAndSettle();

    expect(find.text('선택된 아동이 없어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
  });

  testWidgets('약관 및 정책 경로는 자리표시자 대신 약관 열람 화면을 연다', (tester) async {
    await tester.pumpWidget(
      const DodamApp(initialRoute: AppRoutes.settingsTerms),
    );
    await tester.pumpAndSettle();

    expect(find.text('약관 및 정책'), findsOneWidget);
    expect(find.text('서비스 이용약관'), findsOneWidget);
    expect(find.text('개인정보 처리방침'), findsOneWidget);
    expect(find.text('페이지를 찾을 수 없어요'), findsNothing);
  });

  testWidgets('알 수 없는 경로는 공통 Error UI를 사용한다', (tester) async {
    await tester.pumpWidget(const DodamApp(initialRoute: '/missing'));
    await tester.pumpAndSettle();

    expect(find.text('페이지를 찾을 수 없어요'), findsWidgets);
    expect(find.text('보호자 홈으로 이동'), findsOneWidget);
  });
}
