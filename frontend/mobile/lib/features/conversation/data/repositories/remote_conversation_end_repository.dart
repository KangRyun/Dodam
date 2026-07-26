import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/conversation_end.dart';
import '../../domain/repositories/conversation_end_repository.dart';

final class RemoteConversationEndRepository
    implements ConversationEndRepository {
  const RemoteConversationEndRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'conversations/$conversationId/end',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final payload = envelopeObject(response.data);
    return ConversationEndResult(completed: payload['completed'] == true);
  }
}
