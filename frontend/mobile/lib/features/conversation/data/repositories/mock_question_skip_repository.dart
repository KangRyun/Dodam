import '../../domain/models/question_skip.dart';
import '../../domain/repositories/question_skip_repository.dart';

// 백엔드 미연동 환경용 질문 건너뛰기 저장
final class MockQuestionSkipRepository implements QuestionSkipRepository {
  const MockQuestionSkipRepository({
    this.delay = const Duration(milliseconds: 500),
    this.shouldFail = false,
  });

  final Duration delay;
  final bool shouldFail;

  @override
  Future<QuestionSkipResult> skipQuestion({
    required int conversationId,
    required QuestionSkipRequest request,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(delay);
    if (shouldFail) throw Exception('Mock question skip failed');
    return const QuestionSkipResult(skipped: true);
  }
}
