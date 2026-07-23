import 'dart:async';

import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('선택한 optionId를 제출하고 성공 상태를 저장한다', () async {
    final repository = _RecordingAnswerRepository();
    final controller = OptionAnswerSubmissionController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'answer-key',
    );

    final submitted = await controller.submit(
      questionMessageId: 10,
      optionId: '2',
    );

    expect(submitted, isTrue);
    expect(controller.status, OptionAnswerSubmissionStatus.success);
    expect(controller.answerMessageId, 30);
    expect(repository.conversationId, 20);
    expect(repository.request?.questionMessageId, 10);
    expect(repository.request?.selectedOptionIds, ['2']);
    expect(repository.idempotencyKeys, ['answer-key']);
  });

  test('실패 후 다시 누르면 같은 멱등성 키로 재시도한다', () async {
    final repository = _RecordingAnswerRepository(failOnce: true);
    final controller = OptionAnswerSubmissionController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'stable-key',
    );

    expect(
      await controller.submit(questionMessageId: 10, optionId: '1'),
      isFalse,
    );
    expect(controller.status, OptionAnswerSubmissionStatus.failure);

    expect(await controller.submit(questionMessageId: 10, optionId: '1'), isTrue);
    expect(repository.idempotencyKeys, ['stable-key', 'stable-key']);
  });

  test('제출 중 연속 선택은 중복 요청하지 않는다', () async {
    final completer = Completer<OptionAnswerResult>();
    final repository = _RecordingAnswerRepository(result: completer.future);
    final controller = OptionAnswerSubmissionController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'answer-key',
    );

    final first = controller.submit(questionMessageId: 10, optionId: '1');
    final second = await controller.submit(questionMessageId: 10, optionId: '2');

    expect(second, isFalse);
    expect(repository.callCount, 1);
    completer.complete(const OptionAnswerResult(answerMessageId: 30));
    expect(await first, isTrue);
  });
}

final class _RecordingAnswerRepository implements ConversationAnswerRepository {
  _RecordingAnswerRepository({this.failOnce = false, this.result});

  final bool failOnce;
  final Future<OptionAnswerResult>? result;
  int callCount = 0;
  int? conversationId;
  OptionAnswerRequest? request;
  final List<String> idempotencyKeys = [];

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async {
    callCount++;
    this.conversationId = conversationId;
    this.request = request;
    idempotencyKeys.add(idempotencyKey);
    if (failOnce && callCount == 1) throw Exception('temporary failure');
    return result ?? const OptionAnswerResult(answerMessageId: 30);
  }
}
