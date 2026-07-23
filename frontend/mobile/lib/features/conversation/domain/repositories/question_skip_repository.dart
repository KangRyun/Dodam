import '../models/question_skip.dart';

// Mock과 실제 API가 공유하는 질문 건너뛰기 계약
abstract interface class QuestionSkipRepository {
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  });
}
