import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  testWidgets('알 수 없는 경로는 공통 Error UI를 사용한다', (tester) async {
    await tester.pumpWidget(const DodamApp(initialRoute: '/missing'));
    await tester.pumpAndSettle();

    expect(find.text('페이지를 찾을 수 없어요'), findsWidgets);
    expect(find.text('보호자 홈으로 이동'), findsOneWidget);
  });
}
