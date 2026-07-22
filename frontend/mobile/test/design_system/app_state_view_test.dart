import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('로딩 상태는 진행 표시와 안내 문구를 제공한다', (tester) async {
    await tester.pumpWidget(subject(const AppLoadingView()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('잠시만 기다려 주세요'), findsOneWidget);
  });

  testWidgets('오류 상태는 기존 공통 버튼으로 재시도한다', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(subject(AppErrorView(onRetry: () => retryCount++)));
    await tester.tap(find.text('다시 시도'));

    expect(retryCount, 1);
    expect(find.byType(AppButton), findsOneWidget);
  });

  testWidgets('빈 상태는 액션이 없을 때 버튼을 노출하지 않는다', (tester) async {
    await tester.pumpWidget(subject(const AppEmptyView()));

    expect(find.text('아직 내용이 없어요'), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('재시도 상태는 아동용 큰 버튼 변형을 재사용한다', (tester) async {
    await tester.pumpWidget(
      subject(AppRetryView(onRetry: () {}, childFriendly: true)),
    );

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.variant, AppButtonVariant.child);
  });
}
