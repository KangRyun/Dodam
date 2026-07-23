import '../models/ai_question.dart';

// Mock과 실제 API가 공유하는 질문 조회 계약
abstract interface class ConversationRepository {
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  });
}
