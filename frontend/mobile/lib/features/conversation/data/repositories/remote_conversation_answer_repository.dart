import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/option_answer.dart';
import '../../domain/repositories/conversation_answer_repository.dart';

// 백엔드 선택지 답변 저장 API 연결 (POST /conversations/{id}/answers/option)
final class RemoteConversationAnswerRepository
    implements ConversationAnswerRepository {
  const RemoteConversationAnswerRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'conversations/$conversationId/answers/option',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    // 공통 응답 래퍼({success,code,message,data})와 직접 응답 형식 모두 지원
    final payload = envelopeObject(response.data);
    return OptionAnswerResult(answerMessageId: payload['messageId'] as int);
  }
}
