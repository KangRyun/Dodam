import '../../../../core/network/network.dart';
import '../../domain/models/stt_result.dart';
import '../../domain/repositories/stt_result_repository.dart';

// 대화 내역에서 업로드한 음성 메시지의 STT 상태 조회
final class RemoteSttResultRepository implements SttResultRepository {
  const RemoteSttResultRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<SttResult> getResult({
    required int conversationId,
    required int messageId,
    required int afterSequence,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      'conversations/$conversationId/messages',
      queryParameters: {'page': 0, 'size': 10, 'afterSequence': afterSequence},
    );
    final body = response.data!;
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data']! as Map)
        : body;
    final content = data['content'] as List<dynamic>? ?? const [];
    final message = content
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where((item) => item['messageId'] == messageId)
        .firstOrNull;
    if (message == null) {
      return SttResult(messageId: messageId, status: SttSpeechStatus.pending);
    }
    return SttResult(
      messageId: messageId,
      status: switch (message['speechStatus']) {
        'PROCESSING' => SttSpeechStatus.processing,
        'SUCCESS' => SttSpeechStatus.success,
        'FAILED' => SttSpeechStatus.failed,
        _ => SttSpeechStatus.pending,
      },
      text: message['sttText'] as String?,
    );
  }
}
