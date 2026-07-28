import 'package:dodam/app/widgets/app_failure_view.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('연결이 끊기면 연결 안내(AppRetryView)를 보여준다', (tester) async {
    await tester.pumpWidget(
      subject(
        AppFailureView(
          title: '활동 기록을 불러오지 못했어요',
          failure: const ApiTransportFailure(
            type: ApiTransportFailureType.connection,
          ),
          onRetry: () {},
        ),
      ),
    );

    expect(find.byType(AppRetryView), findsOneWidget);
    expect(find.byType(AppErrorView), findsNothing);
    expect(find.text('활동 기록을 불러오지 못했어요'), findsOneWidget);
    expect(find.textContaining('인터넷 연결'), findsOneWidget);
  });

  testWidgets('서버 오류는 연결 안내가 아니라 일반 오류로 보여준다', (tester) async {
    await tester.pumpWidget(
      subject(
        AppFailureView(
          title: '관찰 리포트를 불러오지 못했어요',
          failure: const ApiResponseFailure(statusCode: 500, error: null),
          onRetry: () {},
        ),
      ),
    );

    expect(find.byType(AppErrorView), findsOneWidget);
    expect(find.byType(AppRetryView), findsNothing);
    expect(find.textContaining('일시적인 문제'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('세션 만료(401)는 재시도 버튼을 넘겨도 노출하지 않는다', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      subject(
        AppFailureView(
          title: '아이 정보를 불러오지 못했어요',
          failure: const ApiResponseFailure(statusCode: 401, error: null),
          onRetry: () => retryCount++,
        ),
      ),
    );

    expect(find.byType(AppButton), findsNothing);
    expect(find.textContaining('로그인'), findsOneWidget);
    expect(retryCount, 0);
  });

  testWidgets('재시도 콜백이 없으면 연결 문제라도 버튼 없이 안내만 한다', (tester) async {
    await tester.pumpWidget(
      subject(
        const AppFailureView(
          title: '아이 정보를 불러오지 못했어요',
          failure: ApiTransportFailure(
            type: ApiTransportFailureType.connection,
          ),
        ),
      ),
    );

    expect(find.byType(AppErrorView), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('아동 모드에서는 오류 원인을 드러내지 않는다', (tester) async {
    await tester.pumpWidget(
      subject(
        AppFailureView(
          title: '지금은 잘 안 돼요',
          failure: const ApiResponseFailure(statusCode: 403, error: null),
          childFriendly: true,
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('지금은 잘 안 돼요. 조금 뒤에 다시 해볼까요?'), findsOneWidget);
    expect(find.textContaining('권한'), findsNothing);
  });

  testWidgets('실패 객체가 없어도 화면이 비지 않는다', (tester) async {
    await tester.pumpWidget(
      subject(
        AppFailureView(
          title: '불러오지 못했어요',
          failure: null,
          onRetry: () {},
        ),
      ),
    );

    expect(find.byType(AppErrorView), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
