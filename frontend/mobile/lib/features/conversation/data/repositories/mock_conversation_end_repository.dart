import '../../domain/models/conversation_end.dart';
import '../../domain/repositories/conversation_end_repository.dart';

// 백엔드 미연동 환경용 대화 종료 처리
final class MockConversationEndRepository implements ConversationEndRepository {
  const MockConversationEndRepository({
    this.delay = const Duration(milliseconds: 600),
    this.shouldFail = false,
  });

  final Duration delay;
  final bool shouldFail;

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(delay);
    if (shouldFail) throw Exception('Mock conversation end failed');
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: request.reason.apiValue,
      completedAt: '2026-07-26T12:00:00Z',
      nextStage: 'REFLECTION',
    );
  }
}
