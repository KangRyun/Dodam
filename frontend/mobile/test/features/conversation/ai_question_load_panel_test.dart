import 'dart:async';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// S15P11B209-485 대기 상태 UI와 S15P11B209-486 실패·재시도 UI 검증.
///
/// 두 상태가 같은 위젯의 다른 분기라 한 파일에서 함께 다룬다.
void main() {
  group('S485 대기 상태', () {
    testWidgets('질문을 요청하는 동안 대기 카드와 progress를 보여준다', (tester) async {
      final completer = Completer<AiQuestion>();
      final controller = _controller(
        _FakeRepository(pending: completer.future),
      );
      addTearDown(controller.dispose);

      await _pump(tester, controller);
      unawaited(controller.load());
      await tester.pump();

      expect(find.byKey(const ValueKey('ai-question-loading')), findsOneWidget);
      expect(find.text('새 질문을 생각하고 있어요'), findsOneWidget);
      expect(find.text('그림을 보며 잠시만 기다려 주세요.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_question);
      await tester.pumpAndSettle();
    });

    testWidgets('대기 상태를 live region으로 한 번만 읽어준다', (tester) async {
      final completer = Completer<AiQuestion>();
      final controller = _controller(
        _FakeRepository(pending: completer.future),
      );
      addTearDown(controller.dispose);
      final handle = tester.ensureSemantics();

      await _pump(tester, controller);
      unawaited(controller.load());
      await tester.pump();
      // AnimatedSwitcher가 완전히 나타나기 전에는 투명도 때문에 semantics가 빠진다.
      await tester.pump(const Duration(milliseconds: 300));

      final announced = find.bySemanticsLabel('새 질문을 생각하고 있어요. 잠시만 기다려 주세요.');
      expect(announced, findsOneWidget);
      expect(
        tester.getSemantics(announced),
        matchesSemantics(
          isLiveRegion: true,
          label: '새 질문을 생각하고 있어요. 잠시만 기다려 주세요.',
        ),
      );
      // 카드 안 Text와 progress가 따로 낭독되면 같은 말이 반복된다.
      expect(find.bySemanticsLabel('새 질문을 생각하고 있어요'), findsNothing);

      completer.complete(_question);
      await tester.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('성공하면 대기 카드를 제거한다', (tester) async {
      final controller = _controller(_FakeRepository());
      addTearDown(controller.dispose);

      await _pump(tester, controller);
      await controller.load();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-question-loading')), findsNothing);
      expect(find.byKey(const ValueKey('ai-question-ready')), findsOneWidget);
    });

    testWidgets('실패해도 대기 카드를 제거한다', (tester) async {
      final controller = _controller(_FakeRepository(failure: _failure(500)));
      addTearDown(controller.dispose);

      await _pump(tester, controller);
      await controller.load();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-question-loading')), findsNothing);
      expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);
    });

    testWidgets('정상 종료는 대기·오류 카드를 모두 남기지 않는다', (tester) async {
      final controller = _controller(
        _FakeRepository(failure: _failure(409, 'QUESTION_LIMIT_REACHED')),
      );
      addTearDown(controller.dispose);

      await _pump(tester, controller);
      await controller.load();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-question-loading')), findsNothing);
      expect(find.byKey(const ValueKey('ai-question-error')), findsNothing);
    });
  });

  group('S486 실패·재시도', () {
    for (final (status, code) in <(int, String?)>[
      (500, null),
      (502, null),
      (503, 'CONVERSATION_503_001'),
    ]) {
      testWidgets('재시도 가능한 $status 실패는 다시 불러오기를 제공한다', (tester) async {
        final controller = _controller(
          _FakeRepository(failure: _failure(status, code)),
        );
        addTearDown(controller.dispose);

        await _pump(tester, controller);
        await controller.load();
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('ai-question-retry')), findsOneWidget);
        expect(find.text('다시 불러오기'), findsOneWidget);
      });
    }

    testWidgets('연결 오류도 재시도를 제공한다', (tester) async {
      final controller = _controller(
        _FakeRepository(
          failure: const ApiTransportFailure(
            type: ApiTransportFailureType.connection,
          ),
        ),
      );
      addTearDown(controller.dispose);

      await _pump(tester, controller);
      await controller.load();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai-question-retry')), findsOneWidget);
      expect(find.text('연결이 잠깐 끊겼어요. 다시 해볼까요?'), findsOneWidget);
    });

    for (final (status, code) in <(int, String?)>[
      (401, null),
      (403, 'CONVERSATION_ACCESS_DENIED'),
      (404, 'CONVERSATION_404_001'),
      (422, 'AI_SAFETY_POLICY_BLOCKED'),
      (422, 'PREFERRED_RESPONSE_MODE_INVALID'),
      (409, 'CONVERSATION_409_002'),
      (409, 'QUESTION_STORAGE_CONFLICT'),
    ]) {
      testWidgets('재시도해도 같은 $status(${code ?? '-'})에는 버튼을 숨긴다', (tester) async {
        final controller = _controller(
          _FakeRepository(failure: _failure(status, code)),
        );
        addTearDown(controller.dispose);

        await _pump(tester, controller);
        await controller.load();
        await tester.pumpAndSettle();

        // 오류 안내 자체는 남겨 아이가 상황을 알 수 있게 한다.
        expect(find.byKey(const ValueKey('ai-question-error')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai-question-retry')), findsNothing);
      });
    }

    testWidgets('다시 불러오기를 누르면 같은 멱등성 키로 다시 요청한다', (tester) async {
      final repository = _FakeRepository(failure: _failure(500));
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await _pump(tester, controller);
      await controller.load();
      await tester.pumpAndSettle();

      repository.failure = null;
      await tester.tap(find.byKey(const ValueKey('ai-question-retry')));
      await tester.pumpAndSettle();

      expect(repository.callCount, 2);
      expect(repository.idempotencyKeys.toSet(), hasLength(1));
      expect(find.byKey(const ValueKey('ai-question-ready')), findsOneWidget);
    });

    testWidgets('내부 status·errorCode·예외 문구를 아이 화면에 노출하지 않는다', (tester) async {
      final controller = _controller(
        _FakeRepository(failure: _failure(503, 'CONVERSATION_503_001')),
      );
      addTearDown(controller.dispose);

      await _pump(tester, controller);
      await controller.load();
      await tester.pumpAndSettle();

      expect(find.textContaining('CONVERSATION'), findsNothing);
      expect(find.textContaining('503'), findsNothing);
      expect(find.textContaining('ApiResponseFailure'), findsNothing);
      expect(find.text('지금은 잘 안 돼요. 조금 뒤에 다시 해볼까요?'), findsOneWidget);
    });

    testWidgets('오류 상태도 live region으로 알린다', (tester) async {
      final controller = _controller(_FakeRepository(failure: _failure(500)));
      addTearDown(controller.dispose);
      final handle = tester.ensureSemantics();

      await _pump(tester, controller);
      await controller.load();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('질문을 불러오지 못했어요. 지금은 잘 안 돼요. 조금 뒤에 다시 해볼까요?'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('경계 조건', () {
    for (final (name, size, scale) in <(String, Size, double)>[
      ('작은 화면', Size(320, 640), 1.0),
      ('큰 글자', Size(390, 844), 2.0),
      ('작은 화면 + 큰 글자', Size(320, 640), 2.0),
    ]) {
      testWidgets('$name에서 대기·오류 카드가 overflow 없이 표시된다', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final completer = Completer<AiQuestion>();
        final repository = _FakeRepository(pending: completer.future);
        final controller = _controller(repository);
        addTearDown(controller.dispose);

        await _pump(tester, controller, textScale: scale);
        unawaited(controller.load());
        await tester.pump();
        expect(
          find.byKey(const ValueKey('ai-question-loading')),
          findsOneWidget,
        );

        completer.completeError(_failure(500));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai-question-retry')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  AiQuestionController controller, {
  double textScale = 1.0,
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: AiQuestionLoadPanel(
            controller: controller,
            loadOnMount: false,
          ),
        ),
      ),
    ),
  ),
);

AiQuestionController _controller(_FakeRepository repository) =>
    AiQuestionController(
      repository,
      conversationId: 11,
      basisAnalysisId: 22,
      idempotencyKeyProvider: () => 'question-key',
    );

ApiResponseFailure _failure(int statusCode, [String? code]) =>
    ApiResponseFailure(
      statusCode: statusCode,
      error: code == null ? null : ApiError(code: code, message: '실패'),
    );

final class _FakeRepository implements ConversationRepository {
  _FakeRepository({this.pending, this.failure});

  final Future<AiQuestion>? pending;
  Object? failure;
  int callCount = 0;
  final List<String> idempotencyKeys = [];

  @override
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  }) async => const ConversationStartResult(
    conversationId: 800,
    maxQuestionCount: 5,
  );

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) {
    callCount += 1;
    idempotencyKeys.add(idempotencyKey);
    if (failure case final caught?) return Future<AiQuestion>.error(caught);
    return pending ?? Future<AiQuestion>.value(_question);
  }
}

final _question = AiQuestion(
  messageId: 1,
  conversationId: 11,
  sequence: 1,
  text: '그림에는 누가 있어?',
  options: const [],
  ttsAvailable: true,
  createdAt: DateTime.utc(2026, 7, 30),
);
