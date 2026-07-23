import '../../domain/models/option_answer.dart';
import '../../domain/repositories/conversation_answer_repository.dart';

// 백엔드 미연동 환경용 선택지 답변 저장
final class MockConversationAnswerRepository
    implements ConversationAnswerRepository {
  const MockConversationAnswerRepository({
    this.delay = const Duration(milliseconds: 600),
    this.shouldFail = false,
  });

  final Duration delay;
  final bool shouldFail;

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(delay);
    if (shouldFail) throw Exception('Mock option answer submission failed');
    return const OptionAnswerResult(answerMessageId: 9101);
  }
}
