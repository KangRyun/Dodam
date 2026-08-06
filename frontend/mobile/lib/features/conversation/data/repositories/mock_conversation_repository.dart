import '../../domain/models/ai_question.dart';
import '../../domain/models/conversation_start.dart';
import '../../domain/repositories/conversation_repository.dart';

// AI·백엔드 미연동 환경용 질문 데이터
final class MockConversationRepository implements ConversationRepository {
  const MockConversationRepository({
    this.delay = const Duration(milliseconds: 700),
    this.shouldFail = false,
    this.maxQuestionCount = 5,
  });

  final Duration delay;
  final bool shouldFail;

  /// 서버가 정하는 값을 흉내 낸다 — 그림일기 정책(app.conversation.question-limit.art-diary)
  /// 과 같은 5를 기본으로 둔다(S15P11B209-976).
  final int maxQuestionCount;

  @override
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(delay);
    if (shouldFail) throw Exception('Mock conversation start failed');
    return ConversationStartResult(
      conversationId: 8001,
      maxQuestionCount: maxQuestionCount,
    );
  }

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(delay);
    if (shouldFail) throw Exception('Mock question request failed');

    return AiQuestion(
      messageId: 9001,
      conversationId: conversationId,
      sequence: 1,
      text: '그림 속에는 누가 함께 있어?',
      options: const [
        AiQuestionOption(
          optionId: '1',
          type: 'TEXT',
          label: '가족이 있어',
          value: '가족이 있어',
        ),
        AiQuestionOption(
          optionId: '2',
          type: 'TEXT',
          label: '친구가 있어',
          value: '친구가 있어',
        ),
      ],
      ttsAvailable: true,
      createdAt: DateTime(2026, 7, 23, 10),
    );
  }
}
