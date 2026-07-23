import '../models/conversation_end.dart';

// Mock과 실제 API가 공유하는 대화 종료 계약
abstract interface class ConversationEndRepository {
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  });
}
