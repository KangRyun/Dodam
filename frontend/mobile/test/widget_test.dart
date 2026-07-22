import 'package:dodam/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('앱은 보호자 홈에서 시작한다', (tester) async {
    await tester.pumpWidget(const DodamApp());

    expect(find.text('보호자 홈'), findsWidgets);
    expect(find.text('활동 대상 아동 선택'), findsOneWidget);
  });
}
