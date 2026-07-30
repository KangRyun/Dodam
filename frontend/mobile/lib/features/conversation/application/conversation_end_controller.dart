import 'package:flutter/foundation.dart';

import '../domain/models/conversation_end.dart';
import '../domain/repositories/conversation_end_repository.dart';
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
          result.nextStage != 'REFLECTION') {
        throw StateError('Unexpected conversation end result.');
      }
      // 화면을 떠난 뒤 도착한 응답은 상태를 되돌리지 않는다.
      if (_disposed) return false;
      status = ConversationEndStatus.success;
      notifyListeners();
      return true;
    } catch (caught) {
      if (_disposed) return false;
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
