import 'package:flutter/foundation.dart';

import '../domain/models/option_answer.dart';
import '../domain/repositories/conversation_answer_repository.dart';

enum OptionAnswerSubmissionStatus { idle, submitting, success, failure }

// 선택지 답변 제출 상태 관리
final class OptionAnswerSubmissionController extends ChangeNotifier {
  OptionAnswerSubmissionController(
    this._repository, {
    required this.conversationId,
    required this.idempotencyKeyProvider,
  });

  final ConversationAnswerRepository _repository;
  final int conversationId;
  final String Function() idempotencyKeyProvider;

  OptionAnswerSubmissionStatus status = OptionAnswerSubmissionStatus.idle;
  int? selectedOptionId;
  int? answerMessageId;
  String? _pendingIdempotencyKey;

  Future<bool> submit({
    required int questionMessageId,
    required int optionId,
  }) async {
    if (status == OptionAnswerSubmissionStatus.submitting) return false;
    selectedOptionId = optionId;
    status = OptionAnswerSubmissionStatus.submitting;
    _pendingIdempotencyKey ??= idempotencyKeyProvider();
    notifyListeners();

    try {
      final result = await _repository.submitOptionAnswer(
        conversationId: conversationId,
        request: OptionAnswerRequest(
          questionMessageId: questionMessageId,
          selectedOptionIds: [optionId],
        ),
        idempotencyKey: _pendingIdempotencyKey!,
      );
      answerMessageId = result.answerMessageId;
      status = OptionAnswerSubmissionStatus.success;
      _pendingIdempotencyKey = null;
      notifyListeners();
      return true;
    } catch (_) {
      status = OptionAnswerSubmissionStatus.failure;
      notifyListeners();
      return false;
    }
  }

  void beginQuestion() {
    status = OptionAnswerSubmissionStatus.idle;
    selectedOptionId = null;
    answerMessageId = null;
    _pendingIdempotencyKey = null;
    notifyListeners();
  }
}
