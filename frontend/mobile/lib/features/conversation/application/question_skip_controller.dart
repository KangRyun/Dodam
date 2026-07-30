import 'package:flutter/foundation.dart';

import '../domain/models/question_skip.dart';
import '../domain/repositories/question_skip_repository.dart';
import 'conversation_retry_policy.dart';

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
  Object? error;

  /// 보류 중인 건너뛰기의 Key. 대상 질문이 Body 전체이므로 질문 ID와 함께 움직인다.
  String? _pendingIdempotencyKey;
  int? _pendingQuestionMessageId;
  int _generation = 0;
  int? _questionMessageId;
  bool _disposed = false;

  /// 재시도 조작을 노출해도 되는 실패인지.
  bool get canRetry =>
      status == QuestionSkipStatus.failure &&
      canRetryConversationRequest(
        error,
        endpoint: ConversationRequestEndpoint.questionSkip,
      );

  Future<bool> submit({required int questionMessageId}) async {
    if (_disposed || status == QuestionSkipStatus.submitting) return false;
    if (status == QuestionSkipStatus.failure &&
        blocksConversationAction(error)) {
      return false;
    }
    // 다른 질문의 보류 Key를 물려받으면 Body가 달라져 IDEMPOTENCY_KEY_REUSED가 된다.
    if (_pendingQuestionMessageId != questionMessageId) {
      _pendingIdempotencyKey = null;
    }
    final key = _pendingIdempotencyKey ??= idempotencyKeyProvider();
    _pendingQuestionMessageId = questionMessageId;
    _questionMessageId = questionMessageId;
    final generation = _generation;

    status = QuestionSkipStatus.submitting;
    error = null;
    notifyListeners();

    try {
      final result = await _repository.skipQuestion(
        conversationId: conversationId,
        request: QuestionSkipRequest(questionMessageId: questionMessageId),
        idempotencyKey: key,
      );
      if (!result.skipped) throw StateError('Question was not skipped');
      if (!_isCurrent(generation, questionMessageId)) return false;
      status = QuestionSkipStatus.success;
      _pendingIdempotencyKey = null;
      _pendingQuestionMessageId = null;
      notifyListeners();
      return true;
    } catch (caught) {
      if (!_isCurrent(generation, questionMessageId)) return false;
      error = caught;
      status = QuestionSkipStatus.failure;
      // 저장 전 거절이 확정된 실패는 Key를 버린다 — 같은 Key 재시도는 무의미하다.
      if (!shouldKeepRequestSnapshot(
        caught,
        endpoint: ConversationRequestEndpoint.questionSkip,
      )) {
        _pendingIdempotencyKey = null;
        _pendingQuestionMessageId = null;
      }
      notifyListeners();
      return false;
    }
  }

  /// 새 질문으로 넘어가며 이전 질문의 응답을 모두 무효화한다.
  void beginQuestion(int questionMessageId) {
    if (_disposed) return;
    _generation += 1;
    _questionMessageId = questionMessageId;
    _pendingIdempotencyKey = null;
    _pendingQuestionMessageId = null;
    status = QuestionSkipStatus.idle;
    error = null;
    notifyListeners();
  }

  bool _isCurrent(int generation, int questionMessageId) =>
      !_disposed &&
      generation == _generation &&
      questionMessageId == _questionMessageId;

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
