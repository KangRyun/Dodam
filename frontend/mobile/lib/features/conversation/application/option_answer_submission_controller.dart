import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/models/ai_question.dart';
import '../domain/models/option_answer.dart';
import '../domain/repositories/conversation_answer_repository.dart';
import 'conversation_failure_log.dart';
import 'conversation_retry_policy.dart';

enum OptionAnswerSubmissionStatus { idle, submitting, success, failure }

/// 전송을 기다리는 선택형 답변 한 건. Key와 Body를 절대 분리하지 않는다.
///
/// [identity]는 실제로 전송할 JSON을 그대로 직렬화한 값이라 백엔드가 해시하는
/// 대상과 같다. `questionMessageId`·`selectedOptions`(순서 포함)·`directText`가
/// 모두 반영되므로 필드 목록을 따로 관리할 필요가 없다.
final class _PendingOptionAnswer {
  const _PendingOptionAnswer({
    required this.questionMessageId,
    required this.request,
    required this.idempotencyKey,
    required this.identity,
  });

  final int questionMessageId;
  final OptionAnswerRequest request;
  final String idempotencyKey;
  final String identity;
}

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
  String? selectedOptionId;
  int? answerMessageId;
  Object? error;
  bool conversationAlreadyEnded = false;

  _PendingOptionAnswer? _pending;
  int _generation = 0;
  int? _questionMessageId;
  bool _disposed = false;

  /// 재시도 조작을 노출해도 되는 실패인지.
  bool get canRetry =>
      status == OptionAnswerSubmissionStatus.failure &&
      canRetryConversationRequest(
        error,
        endpoint: ConversationRequestEndpoint.optionAnswer,
      );

  /// 현재 화면에서 선택지 조작 자체를 허용해도 되는지.
  ///
  /// 불확실 실패에서는 같은 pending 선택 재시도만 허용하고, cancelled는 UI
  /// 재시도를 숨긴다. 확정적이지만 수정 가능한 실패는 다른 선택으로 고칠 수 있다.
  bool get canSelectOption {
    if (status != OptionAnswerSubmissionStatus.failure) return true;
    if (blocksConversationAction(error)) return false;
    if (_pending != null) return canRetry;
    return true;
  }

  /// 서버 저장 여부가 불확실해 다른 선택으로 바꿔 보낼 수 없는 상태인지.
  ///
  /// 이 동안에는 보류 중인 답변만 그대로 재전송한다. 다른 선택지를 새 Key로
  /// 보내면 앞선 요청이 실제로 저장됐을 때 답변이 두 번 남는다.
  bool get isLockedToPendingAnswer =>
      status == OptionAnswerSubmissionStatus.failure && _pending != null;

  /// 보류 중인 답변이 가리키는 선택지 id. 잠금 상태에서 화면이 선택을 되돌릴 때 쓴다.
  String? get pendingOptionId =>
      _pending?.request.selectedOptions.firstOrNull?.optionId;

  Future<bool> submit({
    required int questionMessageId,
    required AiQuestionOption option,
    String? directText,
  }) async {
    if (_disposed ||
        status == OptionAnswerSubmissionStatus.submitting ||
        (status == OptionAnswerSubmissionStatus.success &&
            _questionMessageId == questionMessageId)) {
      return false;
    }
    if (status == OptionAnswerSubmissionStatus.failure &&
        blocksConversationAction(error)) {
      return false;
    }
    final request = OptionAnswerRequest(
      questionMessageId: questionMessageId,
      selectedOptions: [option],
      directText: directText,
    );
    final identity = jsonEncode(request.toJson());
    final pending = _pending;
    if (pending != null &&
        pending.identity != identity &&
        shouldKeepRequestSnapshot(
          error,
          endpoint: ConversationRequestEndpoint.optionAnswer,
        )) {
      // 앞선 요청이 저장됐을 수 있다 — 다른 답변을 새 Key로 보내지 않는다.
      return false;
    }
    if (status == OptionAnswerSubmissionStatus.failure &&
        pending == null &&
        !canRetry &&
        selectedOptionId == option.optionId) {
      // 완료 409 등 같은 실패를 새 Key로 무한 반복하지 않는다. 다른 선택은
      // 새 Body이므로 아래에서 새 snapshot을 만들 수 있다.
      return false;
    }
    // 같은 snapshot이면 Key를 재사용하고, 저장되지 않은 것이 확정된 뒤의 새
    // 선택이면 Key도 Body와 함께 새로 만든다.
    final snapshot = pending != null && pending.identity == identity
        ? pending
        : _PendingOptionAnswer(
            questionMessageId: questionMessageId,
            request: request,
            idempotencyKey: idempotencyKeyProvider(),
            identity: identity,
          );
    _pending = snapshot;
    _questionMessageId = questionMessageId;
    final generation = _generation;

    selectedOptionId = option.optionId;
    status = OptionAnswerSubmissionStatus.submitting;
    error = null;
    notifyListeners();

    try {
      final result = await _repository.submitOptionAnswer(
        conversationId: conversationId,
        request: snapshot.request,
        idempotencyKey: snapshot.idempotencyKey,
      );
      if (!_isCurrent(generation, questionMessageId)) return false;
      answerMessageId = result.answerMessageId;
      status = OptionAnswerSubmissionStatus.success;
      _pending = null;
      notifyListeners();
      return true;
    } catch (caught) {
      if (!_isCurrent(generation, questionMessageId)) return false;
      debugConversationFailure(operation: 'option_answer', error: caught);
      if (isConversationAlreadyCompleted(caught)) {
        conversationAlreadyEnded = true;
        status = OptionAnswerSubmissionStatus.success;
        _pending = null;
        notifyListeners();
        return true;
      }
      error = caught;
      status = OptionAnswerSubmissionStatus.failure;
      // 저장 전 거절이 확정된 실패는 snapshot을 버려 새 선택을 허용한다.
      if (!shouldKeepRequestSnapshot(
        caught,
        endpoint: ConversationRequestEndpoint.optionAnswer,
      )) {
        _pending = null;
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
    _pending = null;
    status = OptionAnswerSubmissionStatus.idle;
    selectedOptionId = null;
    answerMessageId = null;
    error = null;
    conversationAlreadyEnded = false;
    notifyListeners();
  }

  /// 이 응답이 아직 화면이 기다리는 질문의 것인지.
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
