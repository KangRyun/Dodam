import '../models/ai_question.dart';

// Mock과 실제 API가 공유하는 대화 시작·질문 조회 계약
abstract interface class ConversationRepository {
  /// 그림 활동에 연결된 대화 세션을 생성하고 conversationId를 반환한다.
  ///
  /// 이미 진행 중인 대화가 있으면(409 ACTIVE_CONVERSATION_EXISTS) 기존
  /// conversationId를 반환한다.
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  });

  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  });
}
