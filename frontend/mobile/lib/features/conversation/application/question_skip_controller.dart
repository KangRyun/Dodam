import 'package:flutter/foundation.dart';

import '../domain/models/question_skip.dart';
import '../domain/repositories/question_skip_repository.dart';

enum QuestionSkipStatus { idle, submitting, success, failure }

// 질문 건너뛰기 제출 상태 관리
final class QuestionSkipController extends ChangeNotifier {
  QuestionSkipController(
    this._repository, {
    required this.conversationId,
    required this.idempotencyKeyProvider,
  });

  final QuestionSkipRepository _repository;
  final int conversationId;
  final String Function() idempotencyKeyProvider;

  QuestionSkipStatus status = QuestionSkipStatus.idle;
  String? _pendingIdempotencyKey;

  Future<bool> submit({required int questionMessageId}) async {
    if (status == QuestionSkipStatus.submitting) return false;
    status = QuestionSkipStatus.submitting;
    _pendingIdempotencyKey ??= idempotencyKeyProvider();
    notifyListeners();

    try {
      final result = await _repository.skipQuestion(
        conversationId: conversationId,
        request: QuestionSkipRequest(questionMessageId: questionMessageId),
        idempotencyKey: _pendingIdempotencyKey!,
      );
      if (!result.skipped) throw StateError('Question was not skipped');
      status = QuestionSkipStatus.success;
      _pendingIdempotencyKey = null;
      notifyListeners();
      return true;
    } catch (_) {
      status = QuestionSkipStatus.failure;
      notifyListeners();
      return false;
    }
  }

  void beginQuestion() {
    status = QuestionSkipStatus.idle;
    _pendingIdempotencyKey = null;
    notifyListeners();
  }
}
