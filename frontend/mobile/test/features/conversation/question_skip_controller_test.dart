import 'dart:async';

import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('현재 질문 ID를 전달하고 건너뛰기 성공 상태를 저장한다', () async {
    final repository = _RecordingSkipRepository();
    final controller = QuestionSkipController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'skip-key',
    );

    final skipped = await controller.submit(questionMessageId: 10);

    expect(skipped, isTrue);
    expect(controller.status, QuestionSkipStatus.success);
    expect(repository.conversationId, 20);
    expect(repository.request?.questionMessageId, 10);
    expect(repository.idempotencyKeys, ['skip-key']);
  });

  test('실패 후 다시 누르면 같은 멱등성 키로 재시도한다', () async {
    final repository = _RecordingSkipRepository(failOnce: true);
    final controller = QuestionSkipController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'stable-key',
    );

    expect(await controller.submit(questionMessageId: 10), isFalse);
    expect(controller.status, QuestionSkipStatus.failure);

    expect(await controller.submit(questionMessageId: 10), isTrue);
    expect(repository.idempotencyKeys, ['stable-key', 'stable-key']);
  });

  test('제출 중 연속 요청은 중복 저장하지 않는다', () async {
    final completer = Completer<QuestionSkipResult>();
    final repository = _RecordingSkipRepository(result: completer.future);
    final controller = QuestionSkipController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'skip-key',
    );

    final first = controller.submit(questionMessageId: 10);
    final second = await controller.submit(questionMessageId: 10);

    expect(second, isFalse);
    expect(repository.callCount, 1);
    completer.complete(const QuestionSkipResult(skipped: true));
    expect(await first, isTrue);
  });
}

final class _RecordingSkipRepository implements QuestionSkipRepository {
  _RecordingSkipRepository({this.failOnce = false, this.result});

  final bool failOnce;
  final Future<QuestionSkipResult>? result;
  int callCount = 0;
  int? conversationId;
  QuestionSkipRequest? request;
  final List<String> idempotencyKeys = [];

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) async {
    callCount++;
    this.conversationId = conversationId;
    this.request = request;
    idempotencyKeys.add(idempotencyKey);
    if (failOnce && callCount == 1) throw Exception('temporary failure');
    return result ?? const QuestionSkipResult(skipped: true);
  }
}
