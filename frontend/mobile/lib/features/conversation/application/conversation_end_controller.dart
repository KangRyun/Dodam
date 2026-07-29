import 'package:flutter/foundation.dart';

import '../domain/models/conversation_end.dart';
import '../domain/repositories/conversation_end_repository.dart';

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
  String? _pendingIdempotencyKey;
  ConversationEndRequest? _pendingRequest;

  bool get completed => status == ConversationEndStatus.success;
  String? get requestIdempotencyKey => _pendingIdempotencyKey;
  ConversationEndRequest? get requestSnapshot => _pendingRequest;

  Future<bool> submit({
    required int? lastQuestionMessageId,
    ConversationCompletionReason reason = ConversationEndReason.childRequest,
  }) async {
    if (status == ConversationEndStatus.submitting || completed) return false;
    status = ConversationEndStatus.submitting;
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
      status = ConversationEndStatus.success;
      notifyListeners();
      return true;
    } catch (_) {
      status = ConversationEndStatus.failure;
      notifyListeners();
      return false;
    }
  }
}
