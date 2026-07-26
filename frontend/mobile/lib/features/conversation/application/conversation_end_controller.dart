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

  bool get completed => status == ConversationEndStatus.success;

  Future<bool> submit({required int? lastQuestionMessageId}) async {
    if (status == ConversationEndStatus.submitting || completed) return false;
    status = ConversationEndStatus.submitting;
    _pendingIdempotencyKey ??= idempotencyKeyProvider();
    notifyListeners();

    try {
      final result = await _repository.endConversation(
        conversationId: conversationId,
        request: ConversationEndRequest(
          reason: ConversationCompletionReason.childRequest,
          lastQuestionMessageId: lastQuestionMessageId,
        ),
        idempotencyKey: _pendingIdempotencyKey!,
      );
      if (!result.completed) throw StateError('Conversation was not completed');
      status = ConversationEndStatus.success;
      _pendingIdempotencyKey = null;
      notifyListeners();
      return true;
    } catch (_) {
      status = ConversationEndStatus.failure;
      notifyListeners();
      return false;
    }
  }
}
