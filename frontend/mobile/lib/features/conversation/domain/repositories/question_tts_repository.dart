import '../models/question_tts.dart';

abstract interface class QuestionTtsRepository {
  Future<QuestionTtsAudio> loadQuestionAudio(
    int messageId, {
    QuestionTtsRequest request = const QuestionTtsRequest(),
  });
}
