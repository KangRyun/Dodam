import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../domain/models/conversation_end.dart';
import '../domain/models/ai_question.dart';
import '../domain/repositories/conversation_repository.dart';
import 'conversation_failure_log.dart';
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

  /// 조용한 재개 요청 하나의 Key와 대상 분석. 같은 그림 재시도는 같은 Key를 쓴다.
  String? _resumeKey;
  int? _resumeAnalysisId;
  bool _resumeInFlight = false;

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

  /// 끝난 대화를 새 그림 기준으로 다시 열어 달라고 조용히 청한다.
  ///
  /// 아이가 누른 조작이 아니라 그림이 바뀌어 생긴 배경 요청이다. 서버는 "질문 상한
  /// 으로 끝났고 절대 상한은 아직 남은" 대화만 다시 열어 주고, 그 밖의 종료(아이가
  /// 그만하기·보호자 종료·절대 상한 도달)는 거절한다. 그 거절은 고장이 아니라 정상
  /// 이므로 실패를 상태에 남기지 않는다 — [status]를 failure로 올리면 그림만 그리고
  /// 있던 아이 화면에 "질문을 불러오지 못했어요" 카드가 떠 없던 문제를 만든다
  /// (가드레일 9절).
  ///
  /// 그래서 성공했을 때만 상태를 success로 바꾸고 `true`를 돌려준다. 실패는 조용히
  /// `false`이고 이전 상태(대개 [AiQuestionStatus.conversationComplete])가 그대로
  /// 남는다.
  Future<bool> resumeForAnalysis(int analysisId) async {
    if (_disposed || analysisId <= 0 || isLoading || _resumeInFlight) {
      return false;
    }
    // 같은 그림으로 이미 질문을 받았으면 다시 청하지 않는다.
    if (status == AiQuestionStatus.success &&
        _requestBasisAnalysisId == analysisId) {
      return false;
    }
    if (_resumeAnalysisId != analysisId) {
      _resumeAnalysisId = analysisId;
      _resumeKey = null;
    }
    // 같은 그림 재시도는 같은 Key를 재사용한다 — Body가 같으니 fingerprint도 같다.
    final key = _resumeKey ??= _idempotencyKeyProvider();
    // 상태를 건드리지 않으므로 세대도 올리지 않는다. 요청이 도는 사이 다른 경로가
    // 상태를 바꾸면 세대가 어긋나 이 응답은 버려진다.
    final generation = _generation;
    _resumeInFlight = true;
    try {
      final loaded = await _repository.requestNextQuestion(
        conversationId: conversationId,
        request: NextQuestionRequest(
          basisAnalysisId: analysisId,
          previousAnswerMessageId: null,
        ),
        idempotencyKey: key,
      );
      if (!_isCurrent(generation)) return false;
      _requestBasisAnalysisId = analysisId;
      _requestPreviousAnswerMessageId = null;
      _requestKey = key;
      _resumeKey = null;
      _resumeAnalysisId = null;
      question = loaded;
      error = null;
      completionReason = null;
      conversationAlreadyEnded = false;
      status = AiQuestionStatus.success;
      notifyListeners();
      return true;
    } on Object catch (caught) {
      // 화면에는 남기지 않지만 개발 터미널에서는 거절 사유를 구분할 수 있어야 한다.
      debugConversationFailure(operation: 'conversation_resume', error: caught);
      // 저장 전 거절이 확정된 실패는 보류 Key를 버려 새 요청을 허용한다.
      if (!shouldKeepRequestSnapshot(
        caught,
        endpoint: ConversationRequestEndpoint.nextQuestion,
      )) {
        _resumeKey = null;
      }
      return false;
    } finally {
      _resumeInFlight = false;
    }
  }

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
