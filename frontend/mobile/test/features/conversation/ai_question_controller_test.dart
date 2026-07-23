import 'dart:async';

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
  });
}

final class _RecordingConversationRepository implements ConversationRepository {
  _RecordingConversationRepository({this.result, this.failOnce = false});

  final Future<AiQuestion>? result;
  final bool failOnce;
  int callCount = 0;
  int? lastConversationId;
  NextQuestionRequest? lastRequest;
  String? lastIdempotencyKey;
  final List<String> idempotencyKeys = [];

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async {
    callCount++;
    lastConversationId = conversationId;
    lastRequest = request;
    lastIdempotencyKey = idempotencyKey;
    idempotencyKeys.add(idempotencyKey);
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
