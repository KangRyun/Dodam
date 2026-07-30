import 'dart:async';

import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

AiQuestionOption _option(String optionId) => AiQuestionOption(
  optionId: optionId,
  type: 'EMOTION',
  label: '기뻤어요',
  value: 'HAPPY',
  emoji: '😊',
);

void main() {
  test('선택한 선택지를 제출하고 성공 상태를 저장한다', () async {
    final repository = _RecordingAnswerRepository();
    final controller = OptionAnswerSubmissionController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'answer-key',
    );

    final submitted = await controller.submit(
      questionMessageId: 10,
      option: _option('2'),
    );

    expect(submitted, isTrue);
    expect(controller.status, OptionAnswerSubmissionStatus.success);
    expect(controller.selectedOptionId, '2');
    expect(controller.answerMessageId, 30);
    expect(repository.conversationId, 20);
    expect(repository.request?.questionMessageId, 10);
    expect(
      repository.request?.selectedOptions.map((o) => o.optionId).toList(),
      ['2'],
    );
    expect(repository.idempotencyKeys, ['answer-key']);
  });

  test('요청 JSON은 백엔드 계약(selectedOptions 스냅샷)으로 직렬화된다', () {
    final json = OptionAnswerRequest(
      questionMessageId: 10,
      selectedOptions: [_option('2')],
    ).toJson();

    expect(json['questionMessageId'], 10);
    expect(json['selectedOptions'], [
      {
        'optionId': '2',
        // 질문 응답의 노출 type과 별개인 백엔드 저장 스냅샷 값
        'type': 'STATIC',
        'value': 'HAPPY',
        // BE 계약 필드명은 labelSnapshot — 답변 시점 라벨 보존
        'labelSnapshot': '기뻤어요',
      },
    ]);
    expect(json['directText'], isNull);
  });

  test('원본 List 변경 뒤에도 선택 순서와 실제 전송 Body snapshot은 불변이다', () {
    final source = [_option('1'), _option('2')];
    final request = OptionAnswerRequest(
      questionMessageId: 10,
      selectedOptions: source,
      directText: '직접 입력',
    );
    final identityBody = request.toJson();

    source
      ..clear()
      ..add(_option('3'));

    expect(request.selectedOptions.map((option) => option.optionId).toList(), [
      '1',
      '2',
    ]);
    expect(request.toJson(), identityBody);
    expect(request.toJson()['directText'], '직접 입력');
    expect(
      () => request.selectedOptions.add(_option('3')),
      throwsUnsupportedError,
    );
  });

  test('실패 후 다시 누르면 같은 멱등성 키로 재시도한다', () async {
    final repository = _RecordingAnswerRepository(failOnce: true);
    final controller = OptionAnswerSubmissionController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'stable-key',
    );

    expect(
      await controller.submit(questionMessageId: 10, option: _option('1')),
      isFalse,
    );
    expect(controller.status, OptionAnswerSubmissionStatus.failure);

    expect(
      await controller.submit(questionMessageId: 10, option: _option('1')),
      isTrue,
    );
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

    final first = controller.submit(
      questionMessageId: 10,
      option: _option('1'),
    );
    final second = await controller.submit(
      questionMessageId: 10,
      option: _option('2'),
    );

    expect(second, isFalse);
    expect(repository.callCount, 1);
    completer.complete(const OptionAnswerResult(answerMessageId: 30));
    expect(await first, isTrue);
  });

  test('dispose 뒤 늦게 도착한 응답은 상태를 바꾸지 않는다', () async {
    final completer = Completer<OptionAnswerResult>();
    final controller = OptionAnswerSubmissionController(
      _RecordingAnswerRepository(result: completer.future),
      conversationId: 20,
      idempotencyKeyProvider: () => 'answer-key',
    );

    final pending = controller.submit(
      questionMessageId: 10,
      option: _option('1'),
    );
    controller.dispose();
    completer.complete(const OptionAnswerResult(answerMessageId: 30));

    expect(await pending, isFalse);
    expect(controller.status, OptionAnswerSubmissionStatus.submitting);
    expect(controller.answerMessageId, isNull);
  });

  test('dispose 뒤에는 새 제출을 보내지 않는다', () async {
    final repository = _RecordingAnswerRepository();
    final controller = OptionAnswerSubmissionController(
      repository,
      conversationId: 20,
      idempotencyKeyProvider: () => 'answer-key',
    );

    controller.dispose();

    expect(
      await controller.submit(questionMessageId: 10, option: _option('1')),
      isFalse,
    );
    expect(repository.callCount, 0);
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
