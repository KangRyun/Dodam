import '../models/voice_answer.dart';

abstract interface class VoiceAnswerRepository {
  Future<VoiceAnswerUploadResult> upload({
    required int conversationId,
    required VoiceAnswerUploadRequest request,
    required String idempotencyKey,
  });
}
