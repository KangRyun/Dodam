import 'dart:async';

import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('마지막 질문 ID를 전달하고 대화 종료 성공 상태를 저장한다', () async {
    final repository = _RecordingEndRepository();
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'end-key',
    );

    final ended = await controller.submit(lastQuestionMessageId: 10);

    expect(ended, isTrue);
    expect(controller.completed, isTrue);
    expect(repository.conversationId, 20);
    expect(
      repository.request?.reason,
      ConversationCompletionReason.childRequest,
    );
    expect(repository.request?.lastQuestionMessageId, 10);
    expect(repository.idempotencyKeys, ['end-key']);
  });

  test('실패 후 다시 요청하면 같은 멱등성 키로 재시도한다', () async {
    final repository = _RecordingEndRepository(failOnce: true);
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'stable-key',
    );

    expect(await controller.submit(lastQuestionMessageId: 10), isFalse);
    expect(controller.status, ConversationEndStatus.failure);

    expect(await controller.submit(lastQuestionMessageId: 10), isTrue);
    expect(repository.idempotencyKeys, ['stable-key', 'stable-key']);
  });

  test('종료 요청 중 연속 호출은 중복 저장하지 않는다', () async {
    final completer = Completer<ConversationEndResult>();
    final repository = _RecordingEndRepository(result: completer.future);
    final controller = ConversationEndController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'end-key',
    );

    final first = controller.submit(lastQuestionMessageId: 10);
    final second = await controller.submit(lastQuestionMessageId: 10);

    expect(second, isFalse);
    expect(repository.callCount, 1);
    completer.complete(const ConversationEndResult(completed: true));
    expect(await first, isTrue);
  });
}

final class _RecordingEndRepository implements ConversationEndRepository {
  _RecordingEndRepository({this.failOnce = false, this.result});

  final bool failOnce;
  final Future<ConversationEndResult>? result;
  int callCount = 0;
  int? conversationId;
  ConversationEndRequest? request;
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
    idempotencyKeys.add(idempotencyKey);
    if (failOnce && callCount == 1) throw Exception('temporary failure');
    return result ?? const ConversationEndResult(completed: true);
  }
}
