import 'dart:async';

import 'package:dodam/core/network/api_error.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/settings/domain/repositories/account_withdrawal_repository.dart';
import 'package:dodam/features/settings/presentation/screens/account_withdrawal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    AccountWithdrawalRepository repository, {
    int? connectedChildCount = 2,
    Future<void> Function()? onSignOut,
  }) => MaterialApp(
    routes: {'/auth/login': (_) => const Scaffold(body: Text('소셜 로그인'))},
    home: AccountWithdrawalScreen(
      repository: repository,
      onSignOut: onSignOut ?? () async {},
      connectedChildCount: connectedChildCount,
    ),
  );

  Future<void> acknowledge(WidgetTester tester) async {
    final checkbox = find.byKey(const ValueKey('withdrawal-acknowledge'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
  }

  Future<void> typeConfirmation(WidgetTester tester, String value) async {
    final field = find.byKey(const ValueKey('withdrawal-confirmation-field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  AppButton submitButton(WidgetTester tester) => tester.widget<AppButton>(
    find.byKey(const ValueKey('withdrawal-submit')),
  );

  testWidgets('삭제 범위와 보존 안내를 탈퇴 전에 모두 보여준다', (tester) async {
    await tester.pumpWidget(host(_FakeWithdrawalRepository()));
    await tester.pump();

    expect(find.text('탈퇴 전에 꼭 확인해 주세요'), findsOneWidget);
    expect(find.text('탈퇴하면 이렇게 처리돼요'), findsOneWidget);
    expect(find.text('삭제되지 않고 남는 것도 있어요'), findsOneWidget);
    expect(find.text('탈퇴 즉시 끝나지 않는 것도 있어요'), findsOneWidget);
    expect(find.text('아직 안내드릴 수 없는 것'), findsOneWidget);

    // 단독 보호 아동 삭제 범위와 공동 보호 아동 관계 해제를 구분해 안내한다.
    expect(
      find.textContaining('혼자 돌보는 아이는 프로필이 삭제 상태로 바뀌고'),
      findsOneWidget,
    );
    expect(
      find.textContaining('다른 보호자와 함께 돌보는 아이는 삭제하지 않아요'),
      findsOneWidget,
    );
    // 물리 삭제를 약속하지 않는다.
    expect(
      find.textContaining('파일이 이미 완전히 지워졌다는 뜻은 아니에요'),
      findsOneWidget,
    );
    // 되돌릴 수 없이 지워지는 것과 소셜 재가입 가능 여부를 함께 알린다.
    expect(find.textContaining('과정(획) 기록'), findsOneWidget);
    expect(find.textContaining('같은 소셜 계정으로 다시 가입할 수는 있지만'), findsOneWidget);
    // 확정된 법적 보존 항목은 남는 것으로, 미정인 기간·비식별화만 미정으로 안내한다.
    expect(find.textContaining('동의한 기록은 분쟁에 대비해'), findsOneWidget);
    expect(find.textContaining('언제까지 두는지'), findsOneWidget);
  });

  testWidgets('연결된 아이가 0명이라고 확인했을 때만 아이 데이터가 없다고 안내한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_FakeWithdrawalRepository(), connectedChildCount: 0),
    );
    await tester.pump();

    expect(find.textContaining('연결된 아이가 없어서'), findsOneWidget);
    expect(find.textContaining('혼자 돌보는 아이는'), findsNothing);
    expect(find.textContaining('다른 보호자와 함께 돌보는 아이는'), findsNothing);
  });

  // 목록 조회 실패로 아이 수를 모를 때 "아이 데이터도 없다"고 안내하면, 서버가
  // 조건 없이 단독 보호 아동을 삭제하는데도 거짓 안심을 주게 된다.
  testWidgets('아이 수를 확인하지 못했으면 아동 규칙을 모두 보여준다', (tester) async {
    await tester.pumpWidget(
      host(_FakeWithdrawalRepository(), connectedChildCount: null),
    );
    await tester.pump();

    expect(find.textContaining('연결된 아이가 없어서'), findsNothing);
    expect(find.textContaining('혼자 돌보는 아이는'), findsOneWidget);
    expect(find.textContaining('다른 보호자와 함께 돌보는 아이는'), findsOneWidget);
  });

  testWidgets('안내 확인과 정확한 DELETE 입력을 모두 마쳐야 탈퇴 버튼이 열린다', (tester) async {
    await tester.pumpWidget(host(_FakeWithdrawalRepository()));
    await tester.pump();

    expect(submitButton(tester).onPressed, isNull);

    await typeConfirmation(tester, 'DELETE');
    expect(
      submitButton(tester).onPressed,
      isNull,
      reason: '안내 확인 전에는 열리면 안 된다',
    );

    await acknowledge(tester);
    expect(submitButton(tester).onPressed, isNotNull);

    await typeConfirmation(tester, 'delete');
    expect(
      submitButton(tester).onPressed,
      isNull,
      reason: '확인 문구가 정확히 일치하지 않으면 잠겨야 한다',
    );
  });

  testWidgets('탈퇴에 성공하면 세션을 정리하고 로그인 화면으로 돌아간다', (tester) async {
    final repository = _FakeWithdrawalRepository();
    var signOutCount = 0;

    await tester.pumpWidget(
      host(repository, onSignOut: () async => signOutCount += 1),
    );
    await tester.pump();

    await acknowledge(tester);
    await typeConfirmation(tester, 'DELETE');
    await tester.tap(find.byKey(const ValueKey('withdrawal-submit')));
    await tester.pumpAndSettle();

    // 최종 확인 다이얼로그를 한 번 더 거친다.
    expect(find.text('정말 탈퇴할까요?'), findsOneWidget);
    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(repository.receivedConfirmations, ['DELETE']);
    expect(signOutCount, 1);
    expect(find.text('소셜 로그인'), findsOneWidget);
  });

  // onSignOut 은 푸시 해제와 POST auth/logout 을 포함해 수 초가 걸릴 수 있다.
  // 그동안 화면은 살아 있으므로 버튼이 다시 열리면 두 번째 탈퇴 요청이 나간다.
  testWidgets('성공 후 로그아웃 정리를 기다리는 동안 버튼이 다시 열리지 않는다', (tester) async {
    final repository = _FakeWithdrawalRepository();
    final signOutGate = Completer<void>();

    await tester.pumpWidget(
      host(repository, onSignOut: () => signOutGate.future),
    );
    await tester.pump();

    await acknowledge(tester);
    await typeConfirmation(tester, 'DELETE');
    await tester.tap(find.byKey(const ValueKey('withdrawal-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탈퇴하기'));
    // onSignOut 이 끝나지 않아 pumpAndSettle 은 멎지 않는다. 다이얼로그가 닫히고
    // 성공 상태가 화면에 반영될 만큼만 프레임을 진행한다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(repository.receivedConfirmations, ['DELETE']);
    expect(
      submitButton(tester).onPressed,
      isNull,
      reason: '탈퇴는 되돌릴 수 없으므로 성공 후 다시 눌릴 수 없어야 한다',
    );

    signOutGate.complete();
    await tester.pumpAndSettle();
    expect(repository.receivedConfirmations, ['DELETE']);
  });

  testWidgets('최종 확인을 취소하면 탈퇴를 요청하지 않는다', (tester) async {
    final repository = _FakeWithdrawalRepository();
    var signOutCount = 0;

    await tester.pumpWidget(
      host(repository, onSignOut: () async => signOutCount += 1),
    );
    await tester.pump();

    await acknowledge(tester);
    await typeConfirmation(tester, 'DELETE');
    await tester.tap(find.byKey(const ValueKey('withdrawal-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();

    expect(repository.receivedConfirmations, isEmpty);
    expect(signOutCount, 0);
    expect(find.text('소셜 로그인'), findsNothing);
  });

  testWidgets('확인 값 불일치 응답은 전용 문구를 띄우고 화면에 머문다', (tester) async {
    final repository = _FakeWithdrawalRepository(
      failure: const ApiResponseFailure(
        statusCode: 400,
        error: ApiError(
          code: 'USER_400_002',
          message: '회원 탈퇴 확인 값이 올바르지 않습니다.',
        ),
      ),
    );
    var signOutCount = 0;

    await tester.pumpWidget(
      host(repository, onSignOut: () async => signOutCount += 1),
    );
    await tester.pump();

    await acknowledge(tester);
    await typeConfirmation(tester, 'DELETE');
    await tester.tap(find.byKey(const ValueKey('withdrawal-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('확인 문구가 올바르지 않아요'), findsOneWidget);
    expect(signOutCount, 0);
    expect(find.text('소셜 로그인'), findsNothing);
  });

  testWidgets('연결 실패는 공통 오류 문구를 띄우고 세션을 지우지 않는다', (tester) async {
    final repository = _FakeWithdrawalRepository(
      failure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    var signOutCount = 0;

    await tester.pumpWidget(
      host(repository, onSignOut: () async => signOutCount += 1),
    );
    await tester.pump();

    await acknowledge(tester);
    await typeConfirmation(tester, 'DELETE');
    await tester.tap(find.byKey(const ValueKey('withdrawal-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('인터넷 연결'), findsOneWidget);
    expect(signOutCount, 0);
  });
}

final class _FakeWithdrawalRepository implements AccountWithdrawalRepository {
  _FakeWithdrawalRepository({this.failure});

  final Object? failure;
  final List<String> receivedConfirmations = [];

  @override
  Future<void> withdraw({required String confirmation}) async {
    receivedConfirmations.add(confirmation);
    await Future<void>.delayed(Duration.zero);
    if (failure case final failure?) throw failure;
  }
}
