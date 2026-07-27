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

  // 경계조건 보강 (S15P11B209-440): 각 뷰의 반대 분기·문구 주입 검증

  testWidgets('빈 상태는 액션이 주어지면 버튼을 노출하고 콜백을 호출한다', (tester) async {
    var actionCount = 0;

    await tester.pumpWidget(
      subject(
        AppEmptyView(
          actionLabel: '새 활동 시작',
          onAction: () => actionCount++,
        ),
      ),
    );
    await tester.tap(find.text('새 활동 시작'));

    // showAction=true 분기: 액션 라벨+콜백이 모두 있을 때만 버튼이 뜬다
    expect(find.byType(AppButton), findsOneWidget);
    expect(actionCount, 1);
  });

  testWidgets('오류 상태는 재시도 콜백이 없으면 버튼을 노출하지 않는다', (tester) async {
    await tester.pumpWidget(subject(const AppErrorView()));

    // onRetry == null 분기: 액션 없이 안내만 표시
    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('오류 상태는 주입된 제목·문구를 그대로 렌더한다', (tester) async {
    await tester.pumpWidget(
      subject(
        const AppErrorView(
          title: '리포트를 불러오지 못했어요',
          message: '잠시 후 다시 확인해 주세요.',
        ),
      ),
    );

    // 정상 경로: 기본값이 아닌 주입 문구가 화면에 노출되는지(문구 계약)
    expect(find.text('리포트를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('잠시 후 다시 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('빈 상태는 아동용일 때 아동 전용 아이콘을 사용한다', (tester) async {
    await tester.pumpWidget(subject(const AppEmptyView(childFriendly: true)));

    // childFriendly 시각 분기: 아동용은 auto_awesome, 기본은 inbox
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsNothing);
  });

  testWidgets('재시도 상태는 기본(비아동)일 때 보조 버튼 변형을 사용한다', (tester) async {
    await tester.pumpWidget(subject(AppRetryView(onRetry: () {})));

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.variant, AppButtonVariant.secondary);
  });
}
