import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../domain/models/conversation_end.dart';
import '../domain/models/ai_question.dart';
import '../domain/repositories/conversation_repository.dart';
import 'conversation_retry_policy.dart';

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

  /// 서버가 이미 종료된 대화라고 응답했는지.
  ///
  /// 이 경우 종료 사유는 서버가 처음 저장한 값이라 다음 질문 응답으로는 알 수
  /// 없다. 이미 완료된 상태를 바꿀 필요가 없고 불필요한 네트워크 요청을 피하기
  /// 위해, 화면은 [completionReason] 없이 이 값만 보고 다음 단계로 넘어간다.
  bool conversationAlreadyEnded = false;

  String? _requestKey;
  int? _requestBasisAnalysisId;
  int? _requestPreviousAnswerMessageId;
  int _generation = 0;
  bool _disposed = false;

  bool get isLoading => status == AiQuestionStatus.loading;
  bool get canRetry =>
      status == AiQuestionStatus.failure &&
      canRetryConversationRequest(
        error,
        endpoint: ConversationRequestEndpoint.nextQuestion,
      );

  /// 서버에 저장된 미응답 질문을 새 질문 생성 요청 없이 화면에 복원한다.
  void restore(AiQuestion restoredQuestion) {
    if (_disposed || restoredQuestion.conversationId != conversationId) return;
    _generation += 1;
    question = restoredQuestion;
    status = AiQuestionStatus.success;
    error = null;
    completionReason = null;
    conversationAlreadyEnded = false;
    notifyListeners();
  }

  Future<void> load() => _load(
    _requestBasisAnalysisId ?? basisAnalysisId,
    previousAnswerMessageId: _requestPreviousAnswerMessageId,
  );

  /// 새 객체 탐지 결과를 기준으로 다음 질문을 요청한다.
  Future<void> loadForAnalysis(int analysisId) =>
      _load(analysisId, previousAnswerMessageId: null);

  /// 저장된 답변 또는 건너뛰기 뒤 같은 그림을 기준으로 후속 질문을 요청한다.
  Future<void> loadNext({int? basisAnalysisId, int? previousAnswerMessageId}) =>
      _load(
        basisAnalysisId ?? _requestBasisAnalysisId ?? this.basisAnalysisId,
        previousAnswerMessageId: previousAnswerMessageId,
        forceNext: true,
      );

  Future<void> _load(
    int? analysisId, {
    required int? previousAnswerMessageId,
    bool forceNext = false,
  }) async {
    if (_disposed) return;
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
    final generation = ++_generation;
    status = AiQuestionStatus.loading;
    error = null;
    completionReason = null;
    conversationAlreadyEnded = false;
    notifyListeners();

    final AiQuestion? loaded;
    try {
      loaded = await _repository.requestNextQuestion(
        conversationId: conversationId,
        request: NextQuestionRequest(
          basisAnalysisId: analysisId,
          previousAnswerMessageId: previousAnswerMessageId,
        ),
        idempotencyKey: _requestKey!,
      );
    } on ApiResponseFailure catch (caught) {
      // 화면을 떠난 뒤 도착한 응답은 상태를 되돌리지 않는다.
      if (!_isCurrent(generation)) return;
      _applyFailure(caught);
      notifyListeners();
      return;
    } catch (caught) {
      if (!_isCurrent(generation)) return;
      error = caught;
      status = AiQuestionStatus.failure;
      if (!shouldKeepRequestSnapshot(
        caught,
        endpoint: ConversationRequestEndpoint.nextQuestion,
      )) {
        _requestKey = null;
      }
      notifyListeners();
      return;
    }
    if (!_isCurrent(generation)) return;
    question = loaded;
    status = AiQuestionStatus.success;
    notifyListeners();
  }

  /// 실패 응답을 정상 종료와 재시도 대상 실패로 나눈다.
  ///
  /// 다음 질문 API가 실제로 내려주는 종료성 오류만 완료로 다룬다. 같은 409라도
  /// `INVALID_STATE_TRANSITION`·`CONVERSATION_409_002`는 종료가 아니므로 기존
  /// 실패 처리를 유지한다.
  void _applyFailure(ApiResponseFailure failure) {
    switch (failure.error?.code) {
      // 질문 한도 소진 — 아직 대화가 열려 있어 종료 요청이 필요하다.
      case 'CONVERSATION_409_001':
      case 'QUESTION_LIMIT_REACHED':
        completionReason = ConversationCompletionReason.questionLimitReached;
        status = AiQuestionStatus.conversationComplete;
      // 이미 종료된 대화 — 종료 요청을 다시 보내면 안 된다.
      case 'CONVERSATION_ALREADY_COMPLETED':
        conversationAlreadyEnded = true;
        status = AiQuestionStatus.conversationComplete;
      default:
        error = failure;
        status = AiQuestionStatus.failure;
        if (!shouldKeepRequestSnapshot(
          failure,
          endpoint: ConversationRequestEndpoint.nextQuestion,
        )) {
          _requestKey = null;
        }
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }

  static String _createKey() {
    final random = Random.secure();
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'question-$now-${random.nextInt(1 << 32)}';
  }
}
