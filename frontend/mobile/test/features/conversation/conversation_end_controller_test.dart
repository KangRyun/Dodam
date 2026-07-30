import 'dart:async';

import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('마지막 질문 ID를 전달하고 대화 종료 성공 상태를 저장한다', () async {
    final repository = _RecordingEndRepository();
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'end-key-1',
    );

    final ended = await controller.submit(lastQuestionMessageId: 10);

    expect(ended, isTrue);
    expect(controller.completed, isTrue);
    expect(controller.requestIdempotencyKey, 'end-key-1');
    expect(controller.requestSnapshot?.toJson(), {
      'reason': 'CHILD_REQUEST',
      'lastQuestionMessageId': 10,
    });
    expect(repository.conversationId, 20);
    expect(
      repository.request?.reason,
      ConversationCompletionReason.childRequest,
    );
    expect(repository.request?.lastQuestionMessageId, 10);
    expect(repository.idempotencyKeys, ['end-key-1']);
  });

  test('질문 없음 자동 종료 사유를 종료 API에 전달한다', () async {
    final repository = _RecordingEndRepository(
      result: Future.value(
        const ConversationEndResult(
          conversationId: 20,
          conversationStatus: 'COMPLETED',
          completed: true,
          completionReason: 'NO_MORE_QUESTION',
          completedAt: '2026-07-29T12:00:00',
          nextStage: 'REFLECTION',
        ),
      ),
    );
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'end-key-1',
    );

    final ended = await controller.submit(
      lastQuestionMessageId: 10,
      reason: ConversationCompletionReason.noMoreQuestion,
    );

    expect(ended, isTrue);
    expect(repository.request?.toJson(), {
      'reason': 'NO_MORE_QUESTION',
      'lastQuestionMessageId': 10,
    });
  });

  test('중간 대화 종료의 DRAWING과 ANALYZING 단계를 정상 응답으로 처리한다', () async {
    for (final nextStage in ['DRAWING', 'ANALYZING']) {
      final controller = ConversationEndController(
        _RecordingEndRepository(
          result: Future.value(
            ConversationEndResult(
              conversationId: 20,
              conversationStatus: 'COMPLETED',
              completed: true,
              completionReason: 'CHILD_REQUEST',
              completedAt: '2026-07-30T12:00:00',
              nextStage: nextStage,
            ),
          ),
        ),
        conversationId: 20,
        idempotencyKeyProvider: () => 'end-key-$nextStage',
      );

      expect(await controller.submit(lastQuestionMessageId: 10), isTrue);
      expect(controller.completed, isTrue);
      expect(controller.nextStage, nextStage);
    }
  });

  test('응답 유실 후 다시 요청하면 같은 멱등성 키와 Body로 재시도한다', () async {
    final repository = _RecordingEndRepository(
      firstFailure: const ApiTransportFailure(
        type: ApiTransportFailureType.receiveTimeout,
      ),
    );
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'stable-key',
    );

    expect(await controller.submit(lastQuestionMessageId: 10), isFalse);
    expect(controller.status, ConversationEndStatus.failure);

    expect(await controller.submit(lastQuestionMessageId: 99), isTrue);
    expect(repository.idempotencyKeys, ['stable-key', 'stable-key']);
    expect(repository.requests.map((request) => request.toJson()), [
      {'reason': 'CHILD_REQUEST', 'lastQuestionMessageId': 10},
      {'reason': 'CHILD_REQUEST', 'lastQuestionMessageId': 10},
    ]);
  });

  test('Conversation End 5xx 후에도 같은 멱등성 키와 Body를 유지한다', () async {
    final repository = _RecordingEndRepository(
      firstFailure: const ApiResponseFailure(statusCode: 503, error: null),
    );
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'stable-key',
    );

    expect(await controller.submit(lastQuestionMessageId: 10), isFalse);
    expect(await controller.submit(lastQuestionMessageId: 99), isTrue);
    expect(repository.idempotencyKeys, ['stable-key', 'stable-key']);
    expect(
      repository.requests.map((request) => request.toJson()),
      everyElement({'reason': 'CHILD_REQUEST', 'lastQuestionMessageId': 10}),
    );
  });

  test('응답의 conversationId와 완료 상태 및 다음 단계가 모두 일치해야 성공한다', () async {
    final invalidResults = [
      const ConversationEndResult(
        conversationId: 99,
        conversationStatus: 'COMPLETED',
        completed: true,
        completionReason: 'CHILD_REQUEST',
        completedAt: '2026-07-26T12:00:00',
        nextStage: 'REFLECTION',
      ),
      const ConversationEndResult(
        conversationId: 20,
        conversationStatus: 'IN_PROGRESS',
        completed: true,
        completionReason: 'CHILD_REQUEST',
        completedAt: '2026-07-26T12:00:00',
        nextStage: 'REFLECTION',
      ),
      const ConversationEndResult(
        conversationId: 20,
        conversationStatus: 'COMPLETED',
        completed: false,
        completionReason: 'CHILD_REQUEST',
        completedAt: '2026-07-26T12:00:00',
        nextStage: 'REFLECTION',
      ),
      const ConversationEndResult(
        conversationId: 20,
        conversationStatus: 'COMPLETED',
        completed: true,
        completionReason: 'CHILD_REQUEST',
        completedAt: '2026-07-26T12:00:00',
        nextStage: 'REPORTING',
      ),
    ];

    for (final result in invalidResults) {
      final controller = ConversationEndController(
        _RecordingEndRepository(result: Future.value(result)),
        conversationId: 20,
        idempotencyKeyProvider: () => 'end-key-1',
      );

      expect(await controller.submit(lastQuestionMessageId: 10), isFalse);
      expect(controller.status, ConversationEndStatus.failure);
    }
  });

  test('종료 요청 중 연속 호출은 중복 저장하지 않는다', () async {
    final completer = Completer<ConversationEndResult>();
    final repository = _RecordingEndRepository(result: completer.future);
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'end-key-1',
    );

    final first = controller.submit(lastQuestionMessageId: 10);
    final second = await controller.submit(lastQuestionMessageId: 10);

    expect(second, isFalse);
    expect(repository.callCount, 1);
    completer.complete(_completedResult);
    expect(await first, isTrue);
  });

  test('dispose 뒤 늦게 도착한 응답은 완료로 바꾸지 않는다', () async {
    final completer = Completer<ConversationEndResult>();
    final controller = ConversationEndController(
      _RecordingEndRepository(result: completer.future),
      conversationId: 20,
      idempotencyKeyProvider: () => 'end-key-1',
    );

    final pending = controller.submit(lastQuestionMessageId: 10);
    controller.dispose();
    completer.complete(_completedResult);

    expect(await pending, isFalse);
    expect(controller.completed, isFalse);
    expect(controller.status, ConversationEndStatus.submitting);
  });

  test('dispose 뒤에는 새 종료 요청을 보내지 않는다', () async {
    final repository = _RecordingEndRepository();
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'end-key-1',
    );

    controller.dispose();

    expect(await controller.submit(lastQuestionMessageId: 10), isFalse);
    expect(repository.callCount, 0);
  });
}

final class _RecordingEndRepository implements ConversationEndRepository {
  _RecordingEndRepository({this.firstFailure, this.result});

  final Object? firstFailure;
  final Future<ConversationEndResult>? result;
  int callCount = 0;
  int? conversationId;
  ConversationEndRequest? request;
  final List<ConversationEndRequest> requests = [];
  final List<String> idempotencyKeys = [];

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    callCount++;
    this.conversationId = conversationId;
    this.request = request;
    requests.add(request);
    idempotencyKeys.add(idempotencyKey);
    if (callCount == 1 && firstFailure != null) throw firstFailure!;
    return result ?? _completedResult;
  }
}

const _completedResult = ConversationEndResult(
  conversationId: 20,
  conversationStatus: 'COMPLETED',
  completed: true,
  completionReason: 'CHILD_REQUEST',
  completedAt: '2026-07-26T12:00:00',
  nextStage: 'REFLECTION',
);
