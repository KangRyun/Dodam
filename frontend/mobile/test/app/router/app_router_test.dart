import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('보호자 홈에서 아동 선택 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(const DodamApp());

    await tester.tap(find.text('활동 대상 아동 선택'));
    await tester.pumpAndSettle();

    expect(find.text('활동 대상 아동 선택'), findsWidgets);
    expect(find.text('아동 선택 후 시작'), findsOneWidget);
  });

  testWidgets('childId 경로는 아동 모드 화면을 생성한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: AppRoutes.childModeHome('child-1'),
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아동 활동 시작'), findsWidgets);
    expect(find.text('child-1'), findsNothing);
  });

  testWidgets('알 수 없는 경로는 공통 Error UI를 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/missing',
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('페이지를 찾을 수 없어요'), findsWidgets);
    expect(find.text('보호자 홈으로 이동'), findsOneWidget);
  });
}
