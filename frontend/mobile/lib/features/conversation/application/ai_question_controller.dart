import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../domain/models/conversation_end.dart';
import '../domain/models/ai_question.dart';
import '../domain/repositories/conversation_repository.dart';

enum AiQuestionStatus {
  initial,
  loading,
  success,
  conversationComplete,
  failure,
}

// 질문 요청과 화면 상태 관리
final class AiQuestionController extends ChangeNotifier {
  AiQuestionController(
    this._repository, {
    required this.conversationId,
    this.basisAnalysisId,
    this.previousAnswerMessageId,
    String Function()? idempotencyKeyProvider,
  }) : _idempotencyKeyProvider = idempotencyKeyProvider ?? _createKey;

  final ConversationRepository _repository;
  final int conversationId;
  final int? basisAnalysisId;
  final int? previousAnswerMessageId;
  final String Function() _idempotencyKeyProvider;

  AiQuestionStatus status = AiQuestionStatus.initial;
  AiQuestion? question;
  Object? error;
  ConversationCompletionReason? completionReason;
  String? _requestKey;
  int? _requestBasisAnalysisId;
  int? _requestPreviousAnswerMessageId;

  bool get isLoading => status == AiQuestionStatus.loading;

  Future<void> load() => _load(
    _requestBasisAnalysisId ?? basisAnalysisId,
    previousAnswerMessageId: _requestPreviousAnswerMessageId,
  );

  /// 새 객체 탐지 결과를 기준으로 다음 질문을 요청한다.
  Future<void> loadForAnalysis(int analysisId) =>
      _load(analysisId, previousAnswerMessageId: null);

  /// 저장된 답변 또는 건너뛰기 뒤 같은 그림을 기준으로 후속 질문을 요청한다.
  Future<void> loadNext({int? previousAnswerMessageId}) => _load(
    _requestBasisAnalysisId ?? basisAnalysisId,
    previousAnswerMessageId: previousAnswerMessageId,
    forceNext: true,
  );

  Future<void> _load(
    int? analysisId, {
    required int? previousAnswerMessageId,
    bool forceNext = false,
  }) async {
    if (analysisId != null && analysisId <= 0) return;
    // 한 요청이 처리되는 동안 답변 버튼 연타로 생기는 중복 질문을 차단
    if (isLoading) return;
    if (!forceNext &&
        status == AiQuestionStatus.success &&
        _requestBasisAnalysisId == analysisId) {
      return;
    }
    final requestChanged =
        _requestBasisAnalysisId != analysisId ||
        _requestPreviousAnswerMessageId != previousAnswerMessageId ||
        forceNext;
    // 답변마다 새로운 질문 생성 요청이므로 별도 멱등성 키를 사용
    if (requestChanged) {
      _requestBasisAnalysisId = analysisId;
      _requestPreviousAnswerMessageId = previousAnswerMessageId;
      _requestKey = null;
      question = null;
    }
    // 실패 재시도는 같은 요청 키를 재사용
    _requestKey ??= _idempotencyKeyProvider();
    status = AiQuestionStatus.loading;
    error = null;
    completionReason = null;
    notifyListeners();

    try {
      question = await _repository.requestNextQuestion(
        conversationId: conversationId,
        request: NextQuestionRequest(
          basisAnalysisId: analysisId,
          previousAnswerMessageId: previousAnswerMessageId,
        ),
        idempotencyKey: _requestKey!,
      );
      status = AiQuestionStatus.success;
    } on ApiResponseFailure catch (caught) {
      final reason = _completionReasonFor(caught);
      if (reason != null) {
        completionReason = reason;
        status = AiQuestionStatus.conversationComplete;
      } else {
        error = caught;
        status = AiQuestionStatus.failure;
      }
    } catch (caught) {
      error = caught;
      status = AiQuestionStatus.failure;
    }
    notifyListeners();
  }

  ConversationCompletionReason? _completionReasonFor(
    ApiResponseFailure failure,
  ) {
    return switch (failure.error?.code) {
      'CONVERSATION_409_001' || 'QUESTION_LIMIT_REACHED' =>
        ConversationCompletionReason.questionLimitReached,
      'NO_MORE_QUESTION' => ConversationCompletionReason.noMoreQuestion,
      _ => null,
    };
  }

  static String _createKey() {
    final random = Random.secure();
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'question-$now-${random.nextInt(1 << 32)}';
  }
}
