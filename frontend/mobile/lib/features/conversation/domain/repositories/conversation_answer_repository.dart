import '../models/option_answer.dart';

// Mock과 실제 API가 공유하는 선택지 답변 제출 계약
abstract interface class ConversationAnswerRepository {
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  });
}
