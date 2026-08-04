import 'dart:async';

import 'package:dodam/features/guardian_pin/application/guardian_pin_controller.dart';
import 'package:dodam/features/guardian_pin/data/dto/guardian_pin_dtos.dart';
import 'package:dodam/features/guardian_pin/domain/failures/guardian_pin_failure.dart';
import 'package:dodam/features/guardian_pin/domain/repositories/guardian_pin_repository.dart';
import 'package:dodam/features/guardian_pin/presentation/widgets/guardian_pin_input.dart';
import 'package:dodam/features/guardian_pin/presentation/widgets/guardian_pin_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('실제 숫자 입력은 4자리로 제한되고 화면과 semantics에는 마스킹된다', (tester) async {
    final repository = _PanelRepository();
    final controller = _controller(repository);
    await _pumpPanel(tester, controller: controller);

    await tester.enterText(find.byKey(guardianPinTextFieldKey), '01a2345');
    await tester.pump();

    expect(controller.inputLength, 4);
    expect(
      tester.widget<TextField>(find.byKey(guardianPinTextFieldKey)).obscureText,
      isTrue,
    );
    final semantics = tester.getSemantics(find.bySemanticsLabel('보호자 PIN 입력'));
    expect(semantics.getSemanticsData().value, '4자리 입력됨');
    expect(semantics.toString(), isNot(contains('0123')));
  });

  testWidgets('실제 삭제·초기화 버튼이 한 자리와 전체 입력을 지운다', (tester) async {
    final controller = _controller(_PanelRepository());
    await _pumpPanel(tester, controller: controller);
    await tester.enterText(find.byKey(guardianPinTextFieldKey), '0123');
    await tester.pump();

    await tester.tap(find.byKey(guardianPinDeleteKey));
    await tester.pump();
    expect(controller.inputLength, 3);

    await tester.tap(find.byKey(guardianPinClearKey));
    await tester.pump();
    expect(controller.inputLength, 0);
    expect(
      tester.getSize(find.byKey(guardianPinDeleteKey)),
      const Size(48, 48),
    );
    expect(tester.getSize(find.byKey(guardianPinClearKey)), const Size(48, 48));
  });

  testWidgets('키보드 focus와 제출 버튼의 실제 tap으로 검증한다', (tester) async {
    final repository = _PanelRepository();
    final controller = _controller(repository);
    await _pumpPanel(tester, controller: controller);

    await tester.tap(find.byKey(guardianPinTextFieldKey));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(guardianPinTextFieldKey))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await tester.enterText(find.byKey(guardianPinTextFieldKey), '0007');
    await tester.pump();
    await tester.tap(find.byKey(guardianPinSubmitKey));
    await tester.pump();

    expect(repository.verifyCalls, 1);
    expect(repository.lastPin, '0007');
  });

  testWidgets('loading 중 입력·삭제·중복 제출이 모두 차단된다', (tester) async {
    final pending = Completer<GuardianPinStatusDto>();
    final repository = _PanelRepository(verifyFuture: pending.future);
    final controller = _controller(repository);
    await _pumpPanel(tester, controller: controller);
    await tester.enterText(find.byKey(guardianPinTextFieldKey), '1234');
    await tester.pump();
    await tester.tap(find.byKey(guardianPinSubmitKey));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byKey(guardianPinTextFieldKey)).enabled,
      isFalse,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('확인하기 처리 중'), findsOneWidget);
    await tester.tap(find.byKey(guardianPinSubmitKey));
    await tester.tap(find.byKey(guardianPinDeleteKey));
    await tester.pump();
    expect(repository.verifyCalls, 1);

    pending.complete(_status());
    await tester.pump();
  });

  testWidgets('잠금 오류·남은 정보는 live region으로 표시되고 입력은 차단된다', (tester) async {
    final repository = _PanelRepository(
      verifyError: GuardianPinFailure(
        type: GuardianPinFailureType.locked,
        code: 'PIN_LOCKED',
        status: _status(
          locked: true,
          remainingAttempts: 0,
          retryAfterSeconds: 30,
        ),
      ),
    );
    final controller = _controller(repository);
    await _pumpPanel(tester, controller: controller);
    await tester.enterText(find.byKey(guardianPinTextFieldKey), '1234');
    await tester.pump();
    await tester.tap(find.byKey(guardianPinSubmitKey));
    await tester.pump();

    expect(find.textContaining('30초'), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find.byKey(guardianPinMessageKey),
    );
    expect(semantics.properties.liveRegion, isTrue);
    expect(
      tester.widget<TextField>(find.byKey(guardianPinTextFieldKey)).enabled,
      isFalse,
    );
  });

  testWidgets('PIN 불일치 오류는 서버가 준 남은 시도 횟수를 화면에 표시한다', (tester) async {
    final repository = _PanelRepository(
      verifyError: GuardianPinFailure(
        type: GuardianPinFailureType.mismatch,
        code: 'PIN_MISMATCH',
        status: _status(remainingAttempts: 3),
      ),
    );
    final controller = _controller(repository);
    await _pumpPanel(tester, controller: controller);
    await tester.enterText(find.byKey(guardianPinTextFieldKey), '1234');
    await tester.pump();
    await tester.tap(find.byKey(guardianPinSubmitKey));
    await tester.pump();

    expect(find.textContaining('3회'), findsOneWidget);
    expect(repository.verifyCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('성공 callback은 완료 한 번에 한 번만 호출된다', (tester) async {
    final controller = _controller(_PanelRepository());
    var completed = 0;
    await _pumpPanel(
      tester,
      controller: controller,
      onCompleted: () => completed += 1,
    );
    await tester.enterText(find.byKey(guardianPinTextFieldKey), '1234');
    await tester.pump();
    await tester.tap(find.byKey(guardianPinSubmitKey));
    await tester.pump();
    await tester.pump();

    expect(completed, 1);
  });

  final viewports = <({Size size, double textScale})>[
    (size: const Size(1280, 800), textScale: 1),
    (size: const Size(844, 390), textScale: 1),
    (size: const Size(390, 844), textScale: 1),
    (size: const Size(390, 844), textScale: 2),
    (size: const Size(844, 390), textScale: 2),
  ];

  for (final viewport in viewports) {
    testWidgets(
      '${viewport.size} textScale ${viewport.textScale}에서 overflow 없이 실제 scroll 가능',
      (tester) async {
        final controller = _controller(_PanelRepository());
        await _pumpPanel(
          tester,
          controller: controller,
          size: viewport.size,
          textScale: viewport.textScale,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -180),
        );
        await tester.pump();
        await tester.ensureVisible(find.byKey(guardianPinSubmitKey));
        expect(find.byKey(guardianPinSubmitKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('키보드 inset과 큰 글자에서도 제출 버튼까지 스크롤할 수 있다', (tester) async {
    final controller = _controller(_PanelRepository());
    await _pumpPanel(
      tester,
      controller: controller,
      size: const Size(844, 390),
      textScale: 2,
      keyboardInset: 220,
    );

    await tester.ensureVisible(find.byKey(guardianPinSubmitKey));
    expect(find.byKey(guardianPinSubmitKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

GuardianPinController _controller(_PanelRepository repository) =>
    GuardianPinController(repository: repository, mode: GuardianPinMode.verify);

Future<void> _pumpPanel(
  WidgetTester tester, {
  required GuardianPinController controller,
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboardInset = 0,
  VoidCallback? onCompleted,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: GuardianPinPanel(
            controller: controller,
            onCompleted: onCompleted,
          ),
        ),
      ),
    ),
  );
}

GuardianPinStatusDto _status({
  bool locked = false,
  int remainingAttempts = 5,
  int? retryAfterSeconds,
}) => GuardianPinStatusDto(
  pinConfigured: true,
  locked: locked,
  remainingAttempts: remainingAttempts,
  retryAfterSeconds: retryAfterSeconds,
  lockedUntil: null,
  serverTime: DateTime.utc(2026, 8, 4),
);

final class _PanelRepository implements GuardianPinRepository {
  _PanelRepository({this.verifyFuture, this.verifyError});

  final Future<GuardianPinStatusDto>? verifyFuture;
  final Object? verifyError;
  int verifyCalls = 0;
  String? lastPin;

  @override
  Future<GuardianPinStatusDto> verify(String pin) async {
    verifyCalls += 1;
    lastPin = pin;
    final future = verifyFuture;
    if (future != null) return future;
    final error = verifyError;
    if (error != null) throw error;
    return _status();
  }

  @override
  Future<GuardianPinStatusDto> getStatus() async => _status();

  @override
  Future<GuardianPinStatusDto> configure(String pin) =>
      throw UnimplementedError();

  @override
  Future<GuardianPinStatusDto> change({
    required String currentPin,
    required String newPin,
  }) => throw UnimplementedError();

  @override
  Future<GuardianPinStatusDto> reset() => throw UnimplementedError();
}
