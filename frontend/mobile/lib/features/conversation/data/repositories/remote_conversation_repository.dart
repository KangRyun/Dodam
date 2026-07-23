import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/ai_question.dart';
import '../../domain/repositories/conversation_repository.dart';

// 백엔드 다음 질문 API 연결
final class RemoteConversationRepository implements ConversationRepository {
  const RemoteConversationRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'conversations/$conversationId/next-question',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    // 공통 응답 래퍼와 직접 응답 형식 모두 지원
    final body = response.data!;
    final payload = body['data'] is Map
        ? Map<String, dynamic>.from(body['data']! as Map)
        : body;
    return AiQuestion.fromJson(payload);
  }
}
