import 'dart:async';

import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// S15P11B209-485·486 — 대화 화면의 AI 응답 대기·실패·재시도 배선 검증.
const _personContext = DrawingActivityContextDto(
  activityKind: 'HTP',
  htpAssessmentId: 91,
  htpStatus: 'IN_PROGRESS',
  stepOrder: 3,
  drawingSubject: 'PERSON',
);

const _houseContext = DrawingActivityContextDto(
  activityKind: 'HTP',
  htpAssessmentId: 91,
  htpStatus: 'IN_PROGRESS',
  stepOrder: 1,
  drawingSubject: 'HOUSE',
);

void main() {
  group('S485 답변 제출 대기 상태', () {
    testWidgets('선택형 답변 제출 중 progress를 보여주고 조작을 잠근다', (tester) async {
      final answers = _AnswerRepository(pending: Completer<int>());
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));

      expect(
        find.byKey(const ValueKey('ai-question-answer-submitting')),
        findsOneWidget,
      );
      expect(_enabled(tester, const ValueKey('ai-question-skip')), isFalse);
      expect(_enabled(tester, const ValueKey('ai-conversation-end')), isFalse);

      answers.pending!.complete(9101);
      await tester.pumpAndSettle();
    });

    testWidgets('건너뛰기 제출 중 진행 표시를 보여준다', (tester) async {
      final skips = _SkipRepository(pending: Completer<bool>());
      await _pumpConversation(tester, skipRepository: skips);

      await _tap(tester, const ValueKey('ai-question-skip'));

      expect(_enabled(tester, const ValueKey('ai-question-skip')), isFalse);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      skips.pending!.complete(true);
      await tester.pumpAndSettle();
    });

    testWidgets('제출이 끝나면 진행 표시를 걷는다', (tester) async {
      final answers = _AnswerRepository(failure: _failure(500));
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai-question-answer-submitting')),
        findsNothing,
      );
    });
  });

  group('S486 답변·건너뛰기·종료 실패', () {
    testWidgets('선택형 답변 실패는 안내를 남기고 질문·선택지를 유지한다', (tester) async {
      final answers = _AnswerRepository(failure: _failure(500));
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai-question-answer-failure')),
        findsOneWidget,
      );
      expect(find.text('무엇을 그렸어?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ai-question-option-1')),
        findsOneWidget,
      );
      expect(find.textContaining('500'), findsNothing);
    });

    testWidgets('답변 실패 후 다시 누르면 같은 멱등성 키로 재시도한다', (tester) async {
      final answers = _AnswerRepository(failure: _failure(500));
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();
      answers.failure = null;
      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();

      expect(answers.keys, hasLength(2));
      expect(answers.keys.toSet(), hasLength(1));
      expect(answers.bodies.toSet(), hasLength(1));
    });

    testWidgets('불확실 실패 뒤 다른 선택은 전송하지 않고 pending 선택을 유지한다', (tester) async {
      final answers = _AnswerRepository(failure: _failure(500));
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();
      await _tap(tester, const ValueKey('ai-question-option-2'));
      await tester.pumpAndSettle();

      expect(answers.keys, hasLength(1));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ai-question-option-1')),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ai-question-option-2')),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('완료 409 뒤 같은 선택은 막고 다른 선택은 새 Key·Body로 보낸다', (tester) async {
      final answers = _AnswerRepository(
        failure: _failure(409, 'OPTION_ANSWER_STORAGE_CONFLICT'),
      );
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();
      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();
      expect(answers.keys, hasLength(1));

      answers.failure = null;
      await _tap(tester, const ValueKey('ai-question-option-2'));
      await tester.pumpAndSettle();

      expect(answers.keys.toSet(), hasLength(2));
      expect(answers.bodies.toSet(), hasLength(2));
    });

    testWidgets('건너뛰기 실패는 안내를 남긴다', (tester) async {
      final skips = _SkipRepository(failure: _failure(500));
      await _pumpConversation(tester, skipRepository: skips);

      await _tap(tester, const ValueKey('ai-question-skip'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai-question-skip-failure')),
        findsOneWidget,
      );
    });

    testWidgets('대화 종료 실패는 안내를 남긴다', (tester) async {
      final ends = _EndRepository(failure: _failure(500));
      await _pumpConversation(tester, endRepository: ends);

      await _tap(tester, const ValueKey('ai-conversation-end'));
      await tester.tap(find.text('대화 그만하기'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai-conversation-end-failure')),
        findsOneWidget,
      );
    });
  });

  group('S486 steps/next 실패와 재시도', () {
    testWidgets('실패하면 화면 안에 재시도 카드를 띄운다', (tester) async {
      final drawing = _HtpRepository(failure: _failure(503));
      await _pumpConversation(tester, drawingRepository: drawing);

      await _endConversation(tester);

      expect(find.byKey(const ValueKey('htp-advance-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('htp-advance-retry')), findsOneWidget);
      expect(find.text('다음 그림을 준비하지 못했어요'), findsOneWidget);
      expect(find.textContaining('503'), findsNothing);
    });

    testWidgets('좁은 화면·큰 글자에서도 스크롤 없이 카드가 보인다', (tester) async {
      final drawing = _HtpRepository(failure: _failure(503));
      await _pumpConversation(
        tester,
        drawingRepository: drawing,
        size: const Size(360, 640),
        textScale: 2,
      );

      await _endConversation(tester);

      // ensureVisible로 억지로 찾지 않는다 — 실패 직후 재시도 버튼이 이미
      // 화면 안에 들어와 있어야 아이가 스스로 다음 단계로 갈 수 있다.
      final retry = find.byKey(const ValueKey('htp-advance-retry'));
      expect(retry, findsOneWidget);
      expect(
        _isWithinViewport(tester, retry),
        isTrue,
        reason: '재시도 버튼이 화면 밖에 있으면 스크롤을 추측해야 한다',
      );
      expect(find.text('다음 그림을 준비하지 못했어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('오류와 재시도를 스크린리더가 인지할 수 있다', (tester) async {
      final handle = tester.ensureSemantics();
      final drawing = _HtpRepository(failure: _failure(503));
      await _pumpConversation(tester, drawingRepository: drawing);

      await _endConversation(tester);

      expect(
        find.bySemanticsLabel('다음 그림을 준비하지 못했어요. 지금은 잘 안 돼요. 조금 뒤에 다시 해볼까요?'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('다시 시도'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('재시도는 같은 멱등성 키로 한 번만 다음 단계로 이동한다', (tester) async {
      final drawing = _HtpRepository(failure: _failure(503));
      await _pumpConversation(tester, drawingRepository: drawing);
      await _endConversation(tester);

      drawing.failure = null;
      await tester.tap(find.byKey(const ValueKey('htp-advance-retry')));
      await tester.pumpAndSettle();

      expect(drawing.stepKeys, hasLength(2));
      expect(drawing.stepKeys.toSet(), hasLength(1));
      expect(find.text('next-drawing-77'), findsOneWidget);
    });

    testWidgets('재시도 카드를 연달아 눌러도 요청은 한 번만 나간다', (tester) async {
      final drawing = _HtpRepository(failure: _failure(503));
      await _pumpConversation(tester, drawingRepository: drawing);
      await _endConversation(tester);

      drawing
        ..failure = null
        ..pending = Completer<void>();
      final retry = find.byKey(const ValueKey('htp-advance-retry'));
      await tester.tap(retry);
      await tester.pump();
      // 전환이 진행 중이면 버튼이 사라진다. 남아 있다면 눌러도 요청이 늘면 안 된다.
      if (retry.evaluate().isNotEmpty) {
        await tester.tap(retry, warnIfMissed: false);
        await tester.pump();
      }

      expect(drawing.stepCalls, 2, reason: '첫 실패 1회 + 재시도 1회');
      drawing.pending!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('재시도 불가능한 권한 오류에는 재시도 버튼을 만들지 않는다', (tester) async {
      final drawing = _HtpRepository(failure: _failure(403));
      await _pumpConversation(tester, drawingRepository: drawing);

      await _endConversation(tester);

      expect(find.byKey(const ValueKey('htp-advance-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('htp-advance-retry')), findsNothing);
    });

    testWidgets('화면을 떠난 뒤 늦게 성공해도 이동하거나 예외를 내지 않는다', (tester) async {
      final drawing = _HtpRepository(pending: Completer<void>());
      await _pumpConversation(tester, drawingRepository: drawing);
      // 전환 요청이 응답을 기다리는 사이에 화면을 떠난다.
      await _endConversation(tester);
      expect(drawing.stepCalls, 1);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      drawing.pending!.complete();
      await tester.pumpAndSettle();

      expect(find.text('next-drawing-77'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('S486 대화 시작 실패와 재시도', () {
    testWidgets('대화 생성 실패는 재시도 카드를 띄우고 같은 키로 재시도한다', (tester) async {
      final conversations = _ConversationRepository(
        startFailure: _failure(503),
      );
      await _pumpConversation(
        tester,
        conversationRepository: conversations,
        conversationId: null,
      );

      expect(
        find.byKey(const ValueKey('conversation-start-error')),
        findsOneWidget,
      );
      expect(find.text('대화를 시작하지 못했어요'), findsOneWidget);

      conversations.startFailure = null;
      await _tap(tester, const ValueKey('conversation-start-retry'));
      await tester.pumpAndSettle();

      expect(conversations.startKeys, hasLength(2));
      expect(conversations.startKeys.toSet(), hasLength(1));
      expect(find.text('무엇을 그렸어?'), findsOneWidget);
    });

    testWidgets('재시도 불가능한 오류에는 재시도 버튼을 만들지 않는다', (tester) async {
      await _pumpConversation(
        tester,
        conversationRepository: _ConversationRepository(
          startFailure: _failure(403),
        ),
        conversationId: null,
      );

      expect(
        find.byKey(const ValueKey('conversation-start-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conversation-start-retry')),
        findsNothing,
      );
    });
  });

  group('S486 이미 종료된 대화', () {
    testWidgets('종료 API를 다시 부르지 않고 다음 단계로 넘어간다', (tester) async {
      final conversations = _ConversationRepository(
        nextFailure: _failure(409, 'CONVERSATION_ALREADY_COMPLETED'),
      );
      final ends = _EndRepository();
      final drawing = _HtpRepository();

      await _pumpConversation(
        tester,
        conversationRepository: conversations,
        endRepository: ends,
        drawingRepository: drawing,
      );
      await tester.pumpAndSettle();

      expect(ends.calls, 0, reason: '이미 끝난 상태를 바꾸지 않는 불필요한 요청이다');
      expect(drawing.stepCalls, 1);
      expect(find.text('next-drawing-77'), findsOneWidget);
      // 실패 카드로 빠지지 않아야 재시도 루프가 생기지 않는다.
      expect(find.byKey(const ValueKey('ai-question-error')), findsNothing);
    });

    // HOUSE·TREE는 steps/next로, 일반 그림과 PERSON은 감정 화면으로 넘어간다.
    for (final (name, context) in <(String, DrawingActivityContextDto)>[
      ('일반 그림', DrawingActivityContextDto.general()),
      ('PERSON', _personContext),
    ]) {
      testWidgets('$name도 이미 종료 상태를 감정 화면까지 전달한다', (tester) async {
        final ends = _EndRepository();

        await _pumpConversation(
          tester,
          conversationRepository: _ConversationRepository(
            nextFailure: _failure(409, 'CONVERSATION_ALREADY_COMPLETED'),
          ),
          endRepository: ends,
          activityContext: context,
        );
        await tester.pumpAndSettle();

        expect(ends.calls, 0, reason: '이미 끝난 대화에는 종료 요청을 보내지 않는다');
        expect(find.text('emotion-screen'), findsOneWidget);
        expect(_lastEmotionArguments?.conversationAlreadyEnded, isTrue);
      });
    }

    testWidgets('질문 한도 종료는 종료 API를 정확히 한 번 호출한다', (tester) async {
      final ends = _EndRepository();

      await _pumpConversation(
        tester,
        conversationRepository: _ConversationRepository(
          nextFailure: _failure(409, 'QUESTION_LIMIT_REACHED'),
        ),
        endRepository: ends,
        activityContext: const DrawingActivityContextDto.general(),
      );
      await tester.pumpAndSettle();

      expect(ends.calls, 1);
      expect(_lastEmotionArguments?.conversationAlreadyEnded, isTrue);
    });
  });

  group('S486 대화 시작 request identity', () {
    testWidgets('같은 분석 재시도는 같은 Key를 쓴다', (tester) async {
      final conversations = _ConversationRepository(
        startFailure: _failure(503),
      );
      final detection = _detectionController();
      await _pumpConversation(
        tester,
        conversationRepository: conversations,
        conversationId: null,
        activityContext: const DrawingActivityContextDto.general(),
        objectDetectionController: detection,
      );

      await _detectAnalysis(tester, detection, 701);
      expect(conversations.startKeys, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('conversation-start-retry')));
      await tester.pumpAndSettle();

      expect(conversations.startKeys, hasLength(2));
      expect(conversations.startKeys.toSet(), hasLength(1));
      expect(conversations.analysisIds.toSet(), {701});
    });

    testWidgets('다른 분석이 들어오면 새 Key를 쓴다', (tester) async {
      final conversations = _ConversationRepository(
        startFailure: _failure(503),
      );
      final detection = _detectionController();
      await _pumpConversation(
        tester,
        conversationRepository: conversations,
        conversationId: null,
        activityContext: const DrawingActivityContextDto.general(),
        objectDetectionController: detection,
      );

      await _detectAnalysis(tester, detection, 701);
      await _detectAnalysis(tester, detection, 702);

      expect(conversations.analysisIds, [701, 702]);
      expect(conversations.startKeys.toSet(), hasLength(2));
    });

    testWidgets('이전 분석의 늦은 성공이 새 분석 상태를 덮지 않는다', (tester) async {
      final completer = Completer<int>();
      final conversations = _ConversationRepository(pendingStart: completer);
      final detection = _detectionController();
      await _pumpConversation(
        tester,
        conversationRepository: conversations,
        conversationId: null,
        activityContext: const DrawingActivityContextDto.general(),
        objectDetectionController: detection,
      );

      await _detectAnalysis(tester, detection, 701);
      expect(conversations.startKeys, hasLength(1));

      // 첫 요청이 응답을 기다리는 사이 새 분석이 들어온다.
      conversations.pendingStart = null;
      await _detectAnalysis(tester, detection, 702);

      completer.complete(9999);
      await tester.pumpAndSettle();

      // 늦게 도착한 이전 대화 ID로 질문을 요청하지 않는다.
      expect(conversations.questionConversationIds, isNot(contains(9999)));
      expect(conversations.analysisIds.last, 702);
    });
  });

  group('S486 영구 오류 재요청 차단', () {
    for (final status in [401, 403, 404, 422]) {
      testWidgets('선택형 답변 $status 뒤에는 다시 보내지 않는다', (tester) async {
        final answers = _AnswerRepository(failure: _failure(status));
        await _pumpConversation(tester, answerRepository: answers);

        await _tap(tester, const ValueKey('ai-question-option-1'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('ai-question-option-1')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(answers.keys, hasLength(1));
        // 질문과 선택지는 그대로 남아 아이가 상황을 볼 수 있다.
        expect(find.text('무엇을 그렸어?'), findsOneWidget);
        expect(find.textContaining('$status'), findsNothing);
      });

      testWidgets('건너뛰기 $status 뒤에는 다시 보내지 않는다', (tester) async {
        final skips = _SkipRepository(failure: _failure(status));
        await _pumpConversation(tester, skipRepository: skips);

        await _tap(tester, const ValueKey('ai-question-skip'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('ai-question-skip')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(skips.calls, 1);
        expect(_enabled(tester, const ValueKey('ai-question-skip')), isFalse);
      });

      testWidgets('대화 종료 $status 뒤에는 다시 보내지 않는다', (tester) async {
        final ends = _EndRepository(failure: _failure(status));
        await _pumpConversation(tester, endRepository: ends);

        await _tap(tester, const ValueKey('ai-conversation-end'));
        await tester.tap(find.text('대화 그만하기'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('ai-conversation-end')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(ends.calls, 1);
        expect(
          _enabled(tester, const ValueKey('ai-conversation-end')),
          isFalse,
        );
      });
    }

    testWidgets('영구 오류에도 남은 경로로 빠져나갈 수 있다', (tester) async {
      final answers = _AnswerRepository(failure: _failure(422));
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();

      // 답변만 잠기고 건너뛰기·대화 그만하기는 살아 있어야 한다.
      expect(_enabled(tester, const ValueKey('ai-question-skip')), isTrue);
      expect(_enabled(tester, const ValueKey('ai-conversation-end')), isTrue);
    });

    testWidgets('5xx 실패는 같은 Key로 다시 보낼 수 있다', (tester) async {
      final answers = _AnswerRepository(failure: _failure(503));
      await _pumpConversation(tester, answerRepository: answers);

      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();
      answers.failure = null;
      await _tap(tester, const ValueKey('ai-question-option-1'));
      await tester.pumpAndSettle();

      expect(answers.keys, hasLength(2));
      expect(answers.keys.toSet(), hasLength(1));
    });
  });
}

/// 객체 탐지를 실제 경로로 성공시켜 새 분석 ID의 대화 생성을 유도한다.
Future<void> _detectAnalysis(
  WidgetTester tester,
  DrawingObjectDetectionController detection,
  int analysisId,
) async {
  _nextAnalysisId = analysisId;
  detection
    ..onDrawingInputStarted()
    ..onDrawingInputEnded();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// `_detectAnalysis`가 다음에 돌려줄 분석 ID.
int _nextAnalysisId = 701;

DrawingObjectDetectionController _detectionController() =>
    DrawingObjectDetectionController(
      // 탐지 Controller는 같은 asset을 두 번 요청하지 않으므로 분석마다 다른 asset을 준다.
      saveDraft: () async => DraftSaveResponseDto(
        drawingAssetId: _nextAnalysisId,
        assetVersion: 1,
        lastEventSequence: 1,
        savedAt: '2026-07-30T00:00:00Z',
        expiresAt: '2026-08-01T00:00:00Z',
      ),
      requestDetection: (_) async => ObjectDetectionResponseDto(
        drawingAnalysisId: _nextAnalysisId,
        drawingSessionId: 100,
        drawingAssetId: _nextAnalysisId,
        requestId: 'req-$_nextAnalysisId',
        analysisType: 'OBJECT_DETECTION',
        status: 'SUCCEEDED',
        model: const DrawingAnalysisModelDto(name: 'yolo', version: '1'),
        detections: const [],
        requestedAt: '2026-07-30T00:00:00Z',
        processedAt: '2026-07-30T00:00:01Z',
      ),
      debounceDuration: const Duration(seconds: 3),
    );

// ---------------------------------------------------------------- helpers

/// 마지막으로 감정 화면에 전달된 인자. 이미 종료된 대화 전달을 확인한다.
EmotionSelectRouteArguments? _lastEmotionArguments;

Future<void> _pumpConversation(
  WidgetTester tester, {
  _ConversationRepository? conversationRepository,
  _AnswerRepository? answerRepository,
  _SkipRepository? skipRepository,
  _EndRepository? endRepository,
  _HtpRepository? drawingRepository,
  int? conversationId = 8001,
  DrawingActivityContextDto activityContext = _houseContext,
  Size size = const Size(1200, 2400),
  double textScale = 1,
  DrawingObjectDetectionController? objectDetectionController,
}) async {
  _lastEmotionArguments = null;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) {
          final arguments = settings.arguments;
          if (arguments is EmotionSelectRouteArguments) {
            _lastEmotionArguments = arguments;
            return const Scaffold(body: Text('emotion-screen'));
          }
          final id = arguments is DrawingRouteArguments
              ? arguments.sessionId
              : null;
          return Scaffold(body: Text('next-drawing-$id'));
        },
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: DrawingScreen(
        childId: '3',
        sessionId: 100,
        activityContext: activityContext,
        inputMethod: 'CANVAS',
        drawingRepository: drawingRepository ?? _HtpRepository(),
        conversationRepository:
            conversationRepository ?? _ConversationRepository(),
        conversationAnswerRepository: answerRepository ?? _AnswerRepository(),
        questionSkipRepository: skipRepository ?? _SkipRepository(),
        conversationEndRepository: endRepository ?? _EndRepository(),
        conversationId: conversationId,
        objectDetectionController: objectDetectionController,
        resumeConversation: objectDetectionController == null,
        idempotencyKeyProvider: _sequentialKeys(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // 발화가 없으면 선택지가 드러난다 — 선택형 경로 검증에 필요하다.
  await tester.pump(const Duration(seconds: 3));
}

/// 위젯이 현재 보이는 화면 영역 안에 들어와 있는지.
bool _isWithinViewport(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  return screen.overlaps(rect) &&
      rect.top >= screen.top &&
      rect.bottom <= screen.bottom;
}

/// 호출마다 다른 Key를 준다 — 재사용은 Controller가 보장해야 한다.
String Function() _sequentialKeys() {
  var next = 0;
  return () => 'key-${next++}';
}

Future<void> _endConversation(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai-conversation-end')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('대화 그만하기'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

bool _enabled(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  if (widget is TextButton) return widget.onPressed != null;
  if (widget is ButtonStyleButton) return widget.onPressed != null;
  throw StateError('Unsupported widget: ${widget.runtimeType}');
}

ApiResponseFailure _failure(int statusCode, [String? code]) =>
    ApiResponseFailure(
      statusCode: statusCode,
      error: code == null ? null : ApiError(code: code, message: '실패'),
    );

// ------------------------------------------------------------------ fakes

final class _ConversationRepository implements ConversationRepository {
  _ConversationRepository({
    this.startFailure,
    this.nextFailure,
    this.pendingStart,
  });

  Object? startFailure;
  Object? nextFailure;
  Completer<int>? pendingStart;
  final List<String> startKeys = [];
  final List<int?> analysisIds = [];
  final List<int> questionConversationIds = [];

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async {
    startKeys.add(idempotencyKey);
    analysisIds.add(analysisId);
    if (pendingStart case final completer?) return completer.future;
    if (startFailure case final caught?) throw caught;
    return 8001;
  }

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async {
    questionConversationIds.add(conversationId);
    if (nextFailure case final caught?) throw caught;
    return AiQuestion(
      messageId: 9001,
      conversationId: conversationId,
      sequence: 1,
      text: '무엇을 그렸어?',
      options: const [
        AiQuestionOption(
          optionId: '1',
          type: 'EMOJI',
          label: '가족',
          value: 'FAMILY',
        ),
        AiQuestionOption(
          optionId: '2',
          type: 'EMOJI',
          label: '친구',
          value: 'FRIEND',
        ),
      ],
      ttsAvailable: false,
      createdAt: DateTime.utc(2026, 7, 30),
    );
  }
}

final class _AnswerRepository implements ConversationAnswerRepository {
  _AnswerRepository({this.failure, this.pending});

  Object? failure;
  Completer<int>? pending;
  final List<String> keys = [];
  final List<String> bodies = [];

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    bodies.add(request.toJson().toString());
    if (failure case final caught?) throw caught;
    final messageId = await (pending?.future ?? Future<int>.value(9101));
    return OptionAnswerResult(answerMessageId: messageId);
  }
}

final class _SkipRepository implements QuestionSkipRepository {
  _SkipRepository({this.failure, this.pending});

  Object? failure;
  Completer<bool>? pending;
  int calls = 0;

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) async {
    calls += 1;
    if (failure case final caught?) throw caught;
    final skipped = await (pending?.future ?? Future<bool>.value(true));
    return QuestionSkipResult(skipped: skipped);
  }
}

final class _EndRepository implements ConversationEndRepository {
  _EndRepository({this.failure});

  Object? failure;
  int calls = 0;

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    calls += 1;
    if (failure case final caught?) throw caught;
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: 'CHILD_REQUEST',
      completedAt: '2026-07-30T00:00:00Z',
      nextStage: 'REFLECTION',
    );
  }
}

final class _HtpRepository implements DrawingRepository, HtpDrawingRepository {
  _HtpRepository({this.failure, this.pending});

  Object? failure;
  Completer<void>? pending;
  int stepCalls = 0;
  final List<String> stepKeys = [];

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    stepCalls += 1;
    stepKeys.add(idempotencyKey);
    if (failure case final caught?) throw caught;
    if (pending case final completer?) await completer.future;
    return HtpAssessmentDto(
      htpAssessmentId: assessmentId,
      status: 'IN_PROGRESS',
      expiresAt: '2026-08-01T00:00:00Z',
      currentStep: const HtpAssessmentStepDto(
        stepOrder: 2,
        drawingSubject: 'TREE',
        drawingSessionId: 77,
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
      ),
      allStepsCompleted: false,
    );
  }

  @override
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here.');
}
