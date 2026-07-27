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

  testWidgets('보호자 홈 뒤로가기는 프로필 선택 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(const DodamApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('뒤로 가기'));
    await tester.pumpAndSettle();

    expect(find.text('누가 도담을 이용하나요?'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-profile')), findsOneWidget);
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

  testWidgets('보호자 홈에서 아동 선택 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(const DodamApp());
    await tester.pumpAndSettle();

    final childSelectLink = find.text('아동 선택 화면에서 보기');
    await tester.ensureVisible(childSelectLink);
    await tester.tap(childSelectLink);
    await tester.pumpAndSettle();

    expect(find.text('활동 대상 아동 선택'), findsOneWidget);
    expect(find.text('선택한 아이로 시작'), findsOneWidget);
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

  testWidgets('알 수 없는 경로는 공통 Error UI를 사용한다', (tester) async {
    await tester.pumpWidget(const DodamApp(initialRoute: '/missing'));
    await tester.pumpAndSettle();

    expect(find.text('페이지를 찾을 수 없어요'), findsWidgets);
    expect(find.text('보호자 홈으로 이동'), findsOneWidget);
  });
}
