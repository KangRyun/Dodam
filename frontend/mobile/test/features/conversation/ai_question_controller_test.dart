import 'dart:async';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiQuestionController', () {
    test('질문 조회 성공 상태와 응답을 저장한다', () async {
      final repository = _RecordingConversationRepository();
      final controller = AiQuestionController(
        repository,
        conversationId: 11,
        basisAnalysisId: 22,
        idempotencyKeyProvider: () => 'question-key',
      );

      await controller.load();

      expect(controller.status, AiQuestionStatus.success);
      expect(controller.question?.text, '그림에는 누가 있어?');
      expect(repository.lastConversationId, 11);
      expect(repository.lastRequest?.basisAnalysisId, 22);
      expect(repository.lastIdempotencyKey, 'question-key');
    });

    test('조회 중 연속 호출은 API를 한 번만 요청한다', () async {
      final completer = Completer<AiQuestion>();
      final repository = _RecordingConversationRepository(
        result: completer.future,
      );
      final controller = AiQuestionController(repository, conversationId: 11);

      final first = controller.load();
      final second = controller.load();

      expect(controller.status, AiQuestionStatus.loading);
      expect(repository.callCount, 1);
      completer.complete(_question);
      await Future.wait([first, second]);
      expect(controller.status, AiQuestionStatus.success);
    });

    test('실패 후 재시도는 같은 멱등성 키를 사용한다', () async {
      final repository = _RecordingConversationRepository(failOnce: true);
      final controller = AiQuestionController(
        repository,
        conversationId: 11,
        idempotencyKeyProvider: () => 'stable-key',
      );

      await controller.load();
      expect(controller.status, AiQuestionStatus.failure);

      await controller.load();
      expect(controller.status, AiQuestionStatus.success);
      expect(repository.idempotencyKeys, ['stable-key', 'stable-key']);
    });

    test('새 객체 탐지 결과마다 분석 ID를 바꿔 다음 질문을 요청한다', () async {
      var keySequence = 0;
      final repository = _RecordingConversationRepository();
      final controller = AiQuestionController(
        repository,
        conversationId: 11,
        idempotencyKeyProvider: () => 'question-key-${++keySequence}',
      );

      await controller.loadForAnalysis(701);
      await controller.loadForAnalysis(701);
      await controller.loadForAnalysis(702);

      expect(repository.callCount, 2);
      expect(repository.basisAnalysisIds, [701, 702]);
      expect(repository.idempotencyKeys, ['question-key-1', 'question-key-2']);
    });

    test('선택·음성 답변 메시지 ID로 같은 분석의 후속 질문을 요청한다', () async {
      var keySequence = 0;
      final repository = _RecordingConversationRepository();
      final controller = AiQuestionController(
        repository,
        conversationId: 11,
        idempotencyKeyProvider: () => 'question-key-${++keySequence}',
      );

      await controller.loadForAnalysis(701);
      await controller.loadNext(previousAnswerMessageId: 801);
      await controller.loadNext(previousAnswerMessageId: 802);

      expect(repository.callCount, 3);
      expect(repository.basisAnalysisIds, [701, 701, 701]);
      expect(repository.previousAnswerMessageIds, [null, 801, 802]);
      expect(repository.idempotencyKeys, [
        'question-key-1',
        'question-key-2',
        'question-key-3',
      ]);
    });

    test('건너뛰기 뒤에는 답변 ID 없이 같은 분석의 다음 질문을 요청한다', () async {
      final repository = _RecordingConversationRepository();
      final controller = AiQuestionController(
        repository,
        conversationId: 11,
        idempotencyKeyProvider: () => 'question-key',
      );

      await controller.loadForAnalysis(701);
      await controller.loadNext();

      expect(repository.callCount, 2);
      expect(repository.previousAnswerMessageIds, [null, null]);
    });

    test('질문 제한 응답은 실패가 아니라 정상 대화 완료 상태로 구분한다', () async {
      final repository = _RecordingConversationRepository(
        failures: [
          const ApiResponseFailure(
            statusCode: 409,
            error: ApiError(
              code: 'CONVERSATION_409_001',
              message: '질문 가능 횟수를 모두 사용했습니다.',
            ),
          ),
        ],
      );
      final controller = AiQuestionController(repository, conversationId: 11);

      await controller.loadNext(previousAnswerMessageId: 801);

      expect(controller.status, AiQuestionStatus.conversationComplete);
      expect(
        controller.completionReason,
        ConversationCompletionReason.questionLimitReached,
      );
      expect(controller.error, isNull);
    });

    test('질문 없음 응답은 NO_MORE_QUESTION 종료 사유로 구분한다', () async {
      final repository = _RecordingConversationRepository(
        failures: [
          const ApiResponseFailure(
            statusCode: 409,
            error: ApiError(
              code: 'NO_MORE_QUESTION',
              message: '더 이상 생성할 질문이 없습니다.',
            ),
          ),
        ],
      );
      final controller = AiQuestionController(repository, conversationId: 11);

      await controller.loadNext(previousAnswerMessageId: 801);

      expect(controller.status, AiQuestionStatus.conversationComplete);
      expect(
        controller.completionReason,
        ConversationCompletionReason.noMoreQuestion,
      );
    });
  });
}

final class _RecordingConversationRepository implements ConversationRepository {
  _RecordingConversationRepository({
    this.result,
    this.failOnce = false,
    this.failures = const [],
  });

  final Future<AiQuestion>? result;
  final bool failOnce;
  final List<Object> failures;
  int callCount = 0;
  int? lastConversationId;
  NextQuestionRequest? lastRequest;
  String? lastIdempotencyKey;
  final List<String> idempotencyKeys = [];
  final List<int?> basisAnalysisIds = [];
  final List<int?> previousAnswerMessageIds = [];

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async => 800;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async {
    callCount++;
    lastConversationId = conversationId;
    lastRequest = request;
    basisAnalysisIds.add(request.basisAnalysisId);
    previousAnswerMessageIds.add(request.previousAnswerMessageId);
    lastIdempotencyKey = idempotencyKey;
    idempotencyKeys.add(idempotencyKey);
    if (callCount <= failures.length) throw failures[callCount - 1];
    if (failOnce && callCount == 1) throw Exception('temporary failure');
    return result ?? _question;
  }
}

final _question = AiQuestion(
  messageId: 1,
  conversationId: 11,
  sequence: 1,
  text: '그림에는 누가 있어?',
  options: const [],
  ttsAvailable: true,
  createdAt: DateTime(2026, 7, 23),
);
