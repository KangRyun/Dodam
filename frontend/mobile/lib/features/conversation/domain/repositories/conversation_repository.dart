import '../models/ai_question.dart';
import '../models/conversation_start.dart';

// Mock과 실제 API가 공유하는 대화 시작·질문 조회 계약
abstract interface class ConversationRepository {
  /// 그림 활동에 연결된 대화 세션을 생성하고 그 결과를 반환한다.
  ///
  /// 이미 진행 중인 대화가 있으면(409 ACTIVE_CONVERSATION_EXISTS) 기존
  /// conversationId를 반환한다.
  ///
  /// 질문 수 상한은 보내지 않는다 — 활동 유형(HTP 주제당 · 그림일기)에 따라
  /// 서버가 정하고, 앱은 응답의 maxQuestionCount 를 받아 쓴다(S15P11B209-976).
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  });

  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  });
}
