import 'package:flutter/foundation.dart';

import '../domain/models/conversation_end.dart';
import '../domain/repositories/conversation_end_repository.dart';
import 'conversation_failure_log.dart';
import 'conversation_retry_policy.dart';

enum ConversationEndStatus { idle, submitting, success, failure }

// 대화 종료 요청 상태 관리
final class ConversationEndController extends ChangeNotifier {
  ConversationEndController(
    this._repository, {
    required this.conversationId,
    required this.idempotencyKeyProvider,
  });

  final ConversationEndRepository _repository;
  final int conversationId;
  final String Function() idempotencyKeyProvider;

  ConversationEndStatus status = ConversationEndStatus.idle;
  Object? error;
  String? nextStage;

  /// 종료 요청의 Key와 Body. 재시도·다음 화면 인계 모두 이 짝을 그대로 쓴다.
  String? _pendingIdempotencyKey;
  ConversationEndRequest? _pendingRequest;
  bool _disposed = false;

  bool get completed => status == ConversationEndStatus.success;
  String? get requestIdempotencyKey => _pendingIdempotencyKey;
  ConversationEndRequest? get requestSnapshot => _pendingRequest;

  /// 재시도 조작을 노출해도 되는 실패인지.
  bool get canRetry =>
      status == ConversationEndStatus.failure &&
      canRetryConversationRequest(
        error,
        endpoint: ConversationRequestEndpoint.conversationEnd,
      );

  Future<bool> submit({
    required int? lastQuestionMessageId,
    ConversationCompletionReason reason = ConversationEndReason.childRequest,
  }) async {
    if (_disposed || status == ConversationEndStatus.submitting || completed) {
      return false;
    }
    if (status == ConversationEndStatus.failure &&
        blocksConversationAction(error)) {
      return false;
    }
    status = ConversationEndStatus.submitting;
    error = null;
    // Key와 Body를 한 번에 확정해 재시도가 항상 같은 fingerprint로 나가게 한다.
    _pendingIdempotencyKey ??= idempotencyKeyProvider();
    _pendingRequest ??= ConversationEndRequest(
      reason: reason,
      lastQuestionMessageId: lastQuestionMessageId,
    );
    notifyListeners();

    try {
      final result = await _repository.endConversation(
        conversationId: conversationId,
        request: _pendingRequest!,
        idempotencyKey: _pendingIdempotencyKey!,
      );
      if (result.conversationId != conversationId ||
          !result.completed ||
          result.conversationStatus != 'COMPLETED' ||
          !_validNextStages.contains(result.nextStage)) {
        throw StateError('Unexpected conversation end result.');
      }
      // 화면을 떠난 뒤 도착한 응답은 상태를 되돌리지 않는다.
      if (_disposed) return false;
      nextStage = result.nextStage;
      status = ConversationEndStatus.success;
      notifyListeners();
      return true;
    } catch (caught) {
      if (_disposed) return false;
      debugConversationFailure(operation: 'conversation_end', error: caught);
      error = caught;
      status = ConversationEndStatus.failure;
      if (!shouldKeepRequestSnapshot(
        caught,
        endpoint: ConversationRequestEndpoint.conversationEnd,
      )) {
        _pendingIdempotencyKey = null;
        _pendingRequest = null;
      }
      notifyListeners();
      return false;
    }
  }

  /// 서버가 대화를 다시 열어 줬을 때 종료 상태를 되돌린다.
  ///
  /// 그림일기는 대화가 끝난 뒤에도 아이가 그림을 더 그리면 서버가 새 질문과 함께
  /// 대화를 다시 연다. 종료 상태를 그대로 두면 화면은 '대화 끝'인 채로 새 질문을
  /// 받아, 아이가 답하기 전에 그림 활동이 완료돼 마지막 말이 기록에 남지 않는다.
  ///
  /// 보류 Key·Body도 함께 버린다. 다음 종료는 마지막 질문 ID가 달라진 다른 요청이라
  /// 같은 Key로 보내면 백엔드가 `IDEMPOTENCY_KEY_REUSED`(409)로 거절한다.
  ///
  /// 실패 상태는 건드리지 않는다 — 그때는 대화가 아직 끝나지 않아 되돌릴 것이 없고,
  /// 아이·보호자가 다시 시도할 수 있는 오류를 지우면 안 된다.
  void reopen() {
    if (_disposed || !completed) return;
    status = ConversationEndStatus.idle;
    error = null;
    nextStage = null;
    _pendingIdempotencyKey = null;
    _pendingRequest = null;
    notifyListeners();
  }

  // 중간 대화는 그림·분석 단계로, 최종 대화는 감정 선택 단계로 돌아간다.
  static const _validNextStages = {'DRAWING', 'ANALYZING', 'REFLECTION'};

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
