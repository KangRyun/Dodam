import '../models/stt_result.dart';

abstract interface class SttResultRepository {
  Future<SttResult> getResult({
    required int conversationId,
    required int messageId,
    required int afterSequence,
  });
}
