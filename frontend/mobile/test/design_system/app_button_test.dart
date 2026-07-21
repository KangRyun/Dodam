import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('공통 버튼은 탭 동작과 로딩 상태를 제공한다', (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(label: '계속하기', onPressed: () => tapCount++),
        ),
      ),
    );

    await tester.tap(find.text('계속하기'));
    expect(tapCount, 1);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppButton(label: '계속하기', onPressed: null, isLoading: true),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('선택 카드는 선택 상태를 시각화한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppChoiceCard(
            label: '기뻐요',
            isSelected: true,
            onTap: null,
            childFriendly: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('기뻐요'), findsOneWidget);
  });
}
