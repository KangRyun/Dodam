import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_complete_cta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 그림일기 대화 재개.
///
/// 질문 상한으로 대화가 끝난 뒤에도 아이가 그림을 더 그리면, 서버는 같은
/// next-question 계약으로 대화를 다시 열어 새 질문을 준다. 화면은 그 재개를 조용히
/// 청하고 **질문이 실제로 도착했을 때만** '대화 중'으로 돌아가야 한다. 거절은 대화가
/// 정말 끝난 보통의 경우이므로 아이 화면에 아무것도 남기지 않는다(가드레일 9절).
void main() {
  group('AiQuestionController 조용한 재개', () {
    test('재개에 성공하면 새 질문으로 대화 상태를 되돌린다', () async {
      final repository = _QuestionRepository(
        (_, _) async => _question('더 그린 건 뭐야?', messageId: 9102),
      );
      final controller = AiQuestionController(
        repository,
        conversationId: 8001,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      addTearDown(controller.dispose);

      final resumed = await controller.resumeForAnalysis(7002);

      expect(resumed, isTrue);
      expect(controller.status, AiQuestionStatus.success);
      expect(controller.question?.messageId, 9102);
      expect(controller.error, isNull);
      expect(repository.analysisIds, [7002]);
      // 재개는 새 그림이 근거다 — 이전 답변 문맥을 실어 보내지 않는다.
      expect(repository.previousAnswerMessageIds, [null]);
    });

    test('재개가 거절되면 오류를 남기지 않고 종료 상태를 유지한다', () async {
      final repository = _QuestionRepository((call, _) async {
        if (call == 0) throw _failure(409, 'QUESTION_LIMIT_REACHED');
        throw _failure(422, 'CONVERSATION_NOT_RESUMABLE');
      });
      final controller = AiQuestionController(
        repository,
        conversationId: 8001,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      addTearDown(controller.dispose);

      // 질문 상한 도달로 대화가 정상 종료된 상태를 만든다.
      await controller.loadForAnalysis(7001);
      expect(controller.status, AiQuestionStatus.conversationComplete);

      final resumed = await controller.resumeForAnalysis(7002);

      expect(resumed, isFalse);
      // 실패가 상태로 새면 아이 화면에 "질문을 불러오지 못했어요" 카드가 뜬다.
      expect(controller.status, AiQuestionStatus.conversationComplete);
      expect(controller.error, isNull);
      expect(repository.calls, 2, reason: '재개는 실제로 청해 봐야 한다');
    });

    test('같은 그림 재개 재시도는 같은 Key를 재사용한다', () async {
      final repository = _QuestionRepository((call, _) async {
        if (call == 0) {
          throw const ApiTransportFailure(
            type: ApiTransportFailureType.connection,
          );
        }
        return _question('더 그린 건 뭐야?', messageId: 9102);
      });
      final controller = AiQuestionController(
        repository,
        conversationId: 8001,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      addTearDown(controller.dispose);

      await controller.resumeForAnalysis(7002);
      await controller.resumeForAnalysis(7002);

      expect(repository.keys, hasLength(2));
      expect(repository.keys.toSet(), hasLength(1));
    });

    test('이미 같은 그림으로 받은 질문은 다시 청하지 않는다', () async {
      final repository = _QuestionRepository(
        (_, _) async => _question('더 그린 건 뭐야?', messageId: 9102),
      );
      final controller = AiQuestionController(
        repository,
        conversationId: 8001,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      addTearDown(controller.dispose);

      expect(await controller.resumeForAnalysis(7002), isTrue);
      expect(await controller.resumeForAnalysis(7002), isFalse);
      expect(repository.calls, 1);
    });
  });

  group('ConversationEndController.reopen', () {
    test('다시 열면 종료 상태와 보류 Key·Body를 함께 지운다', () async {
      final repository = _EndRepository();
      final controller = ConversationEndController(
        repository,
        conversationId: 8001,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      addTearDown(controller.dispose);

      await controller.submit(lastQuestionMessageId: 9101);
      expect(controller.completed, isTrue);

      controller.reopen();

      // completed가 false로 돌아가야 '그림 완료'가 다시 막힌다
      // (_confirmAndComplete의 `!completed` 가드).
      expect(controller.completed, isFalse);
      expect(controller.status, ConversationEndStatus.idle);
      expect(controller.nextStage, isNull);
      // 다음 종료는 마지막 질문 ID가 다른 새 요청이다. Key를 물려주면 백엔드가
      // IDEMPOTENCY_KEY_REUSED로 거절한다.
      expect(controller.requestIdempotencyKey, isNull);
      expect(controller.requestSnapshot, isNull);

      await controller.submit(lastQuestionMessageId: 9102);
      expect(repository.keys, hasLength(2));
      expect(repository.keys.toSet(), hasLength(2));
      expect(repository.requests.last.lastQuestionMessageId, 9102);
    });

    test('실패 상태는 되돌리지 않는다', () async {
      final controller = ConversationEndController(
        _EndRepository(failure: _failure(503)),
        conversationId: 8001,
        idempotencyKeyProvider: _sequentialKeys(),
      );
      addTearDown(controller.dispose);

      await controller.submit(lastQuestionMessageId: 9101);
      expect(controller.status, ConversationEndStatus.failure);

      controller.reopen();

      // 종료가 아직 안 된 실패는 되돌릴 것이 없다. 재시도 상태를 지우면 안 된다.
      expect(controller.status, ConversationEndStatus.failure);
      expect(controller.requestIdempotencyKey, isNotNull);
    });
  });

  group('그림일기 대화 재개 (화면)', () {
    testWidgets('대화가 끝난 뒤 새 그림이 감지되면 다시 질문한다', (tester) async {
      final conversations = _QuestionRepository((call, _) async {
        if (call == 0) throw _failure(409, 'QUESTION_LIMIT_REACHED');
        return _question('여기 새로 그린 건 뭐야?', messageId: 9102);
      });
      final ends = _EndRepository();
      final detection = _detectionController();
      addTearDown(detection.dispose);

      await _pumpDiary(
        tester,
        conversations: conversations,
        ends: ends,
        detection: detection,
      );

      // 질문 상한 도달 → 자동 종료. 이때는 완료 버튼이 열려 있다.
      await _detect(tester, detection, 7001);
      expect(ends.keys, hasLength(1));
      expect(find.byType(DrawingCompleteCta), findsOneWidget);

      // 아이가 그림을 더 그렸다 → 서버가 대화를 다시 열어 준다.
      await _detect(tester, detection, 7002);

      expect(conversations.analysisIds, [7001, 7002]);
      expect(find.text('여기 새로 그린 건 뭐야?'), findsOneWidget);
      final bubble = tester.widget<AiQuestionBubbleOverlay>(
        find.byType(AiQuestionBubbleOverlay),
      );
      expect(bubble.visible, isTrue, reason: '숨어 있던 질문 패널이 다시 보여야 한다');
      // 종료 상태가 idle로 돌아가야 '그림 완료'가 다시 막힌다. 질문에 답하는 동안은
      // 완료 버튼 자체가 사라져 아이가 대화를 건너뛸 수 없다.
      expect(bubble.endStatus, ConversationEndStatus.idle);
      expect(find.byType(DrawingCompleteCta), findsNothing);
      expect(ends.keys, hasLength(1), reason: '재개가 종료 API를 다시 부르지는 않는다');
    });

    testWidgets('재개가 거절되면 아이 화면에 아무것도 남기지 않는다', (tester) async {
      final conversations = _QuestionRepository((call, _) async {
        if (call == 0) throw _failure(409, 'QUESTION_LIMIT_REACHED');
        throw _failure(422, 'CONVERSATION_NOT_RESUMABLE');
      });
      final ends = _EndRepository();
      final detection = _detectionController();
      addTearDown(detection.dispose);

      await _pumpDiary(
        tester,
        conversations: conversations,
        ends: ends,
        detection: detection,
      );

      await _detect(tester, detection, 7001);
      await _detect(tester, detection, 7002);

      expect(conversations.analysisIds, [7001, 7002], reason: '재개는 청해 봤다');
      // 아이가 누른 조작이 아니다 — 오류 카드도, 스낵바도, 상태 코드도 없다.
      expect(find.byKey(const ValueKey('ai-question-error')), findsNothing);
      expect(find.text('질문을 불러오지 못했어요'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('422'), findsNothing);
      // 대화는 끝난 그대로다 — 아이는 그림만 계속 그린다.
      expect(find.byType(DrawingCompleteCta), findsOneWidget);
    });

    testWidgets('같은 그림으로는 재개를 반복해 청하지 않는다', (tester) async {
      final conversations = _QuestionRepository((call, _) async {
        if (call == 0) throw _failure(409, 'QUESTION_LIMIT_REACHED');
        throw _failure(422, 'CONVERSATION_NOT_RESUMABLE');
      });
      final detection = _detectionController();
      addTearDown(detection.dispose);

      await _pumpDiary(
        tester,
        conversations: conversations,
        ends: _EndRepository(),
        detection: detection,
      );

      await _detect(tester, detection, 7001);
      await _detect(tester, detection, 7002);
      // 같은 분석 결과가 다시 통지돼도 서버를 또 두드리지 않는다.
      _notifyDetectionAgain(detection);
      await tester.pumpAndSettle();

      expect(conversations.analysisIds, [7001, 7002]);
    });

    testWidgets('HTP는 대화가 끝난 뒤 재개를 청하지 않는다', (tester) async {
      final conversations = _QuestionRepository(
        (_, _) async => _question('이 집엔 누가 살아?', messageId: 9102),
      );
      final detection = _detectionController();
      addTearDown(detection.dispose);

      await _pumpDiary(
        tester,
        conversations: conversations,
        ends: _EndRepository(),
        detection: detection,
        activityContext: const DrawingActivityContextDto(
          activityKind: 'HTP',
          htpAssessmentId: 91,
          htpStatus: 'IN_PROGRESS',
          stepOrder: 1,
          drawingSubject: 'HOUSE',
        ),
      );

      await _detect(tester, detection, 7001);
      await _detect(tester, detection, 7002);

      // HTP는 주제별 그림 완료 응답으로만 대화를 연다 — 탐지 경로 자체가 없다.
      expect(conversations.analysisIds, isEmpty);
    });
  });
}

// ----------------------------------------------------------------- helpers

Future<void> _pumpDiary(
  WidgetTester tester, {
  required _QuestionRepository conversations,
  required _EndRepository ends,
  required DrawingObjectDetectionController detection,
  DrawingActivityContextDto activityContext =
      const DrawingActivityContextDto.general(),
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '3',
        activityContext: activityContext,
        objectDetectionController: detection,
        conversationRepository: conversations,
        conversationEndRepository: ends,
        conversationId: 8001,
        idempotencyKeyProvider: _sequentialKeys(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// 탐지 controller를 실제 경로로 성공시켜 새 분석 ID를 화면에 전달한다.
Future<void> _detect(
  WidgetTester tester,
  DrawingObjectDetectionController detection,
  int analysisId,
) async {
  _nextAnalysisId = analysisId;
  detection
    ..onDrawingInputStarted()
    ..onDrawingInputEnded();
  await tester.pump(const Duration(milliseconds: 2));
  await tester.pumpAndSettle();
}

/// 같은 탐지 결과로 listener가 한 번 더 도는 상황을 만든다.
void _notifyDetectionAgain(DrawingObjectDetectionController detection) =>
    detection.notifyListeners();

int _nextAnalysisId = 7001;

DrawingObjectDetectionController _detectionController() =>
    DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 1),
      // 탐지 controller는 같은 asset을 두 번 요청하지 않는다 — 분석마다 다른 asset.
      saveDraft: () async => DraftSaveResponseDto(
        drawingAssetId: _nextAnalysisId,
        assetVersion: 1,
        lastEventSequence: 1,
        savedAt: '2026-08-08T00:00:00Z',
        expiresAt: null,
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
        requestedAt: '2026-08-08T00:00:00Z',
        processedAt: '2026-08-08T00:00:01Z',
      ),
    );

AiQuestion _question(String text, {required int messageId}) => AiQuestion(
  messageId: messageId,
  conversationId: 8001,
  sequence: 1,
  text: text,
  options: const [],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 8),
);

ApiResponseFailure _failure(int statusCode, [String? code]) =>
    ApiResponseFailure(
      statusCode: statusCode,
      error: code == null ? null : ApiError(code: code, message: '실패'),
    );

/// 호출마다 다른 Key를 준다 — 재사용은 Controller가 보장해야 한다.
String Function() _sequentialKeys() {
  var next = 0;
  return () => 'key-${next++}';
}

// ------------------------------------------------------------------- fakes

final class _QuestionRepository implements ConversationRepository {
  _QuestionRepository(this._respond);

  final Future<AiQuestion> Function(int call, NextQuestionRequest request)
  _respond;
  final List<int?> analysisIds = [];
  final List<int?> previousAnswerMessageIds = [];
  final List<String> keys = [];

  int get calls => keys.length;

  @override
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  }) async =>
      const ConversationStartResult(conversationId: 8001, maxQuestionCount: 5);

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) {
    final call = keys.length;
    keys.add(idempotencyKey);
    analysisIds.add(request.basisAnalysisId);
    previousAnswerMessageIds.add(request.previousAnswerMessageId);
    return _respond(call, request);
  }
}

final class _EndRepository implements ConversationEndRepository {
  _EndRepository({this.failure});

  final Object? failure;
  final List<String> keys = [];
  final List<ConversationEndRequest> requests = [];

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    requests.add(request);
    if (failure case final caught?) throw caught;
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: 'QUESTION_LIMIT_REACHED',
      completedAt: '2026-08-08T00:00:00Z',
      nextStage: 'DRAWING',
    );
  }
}
