import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/ai_question.dart';
import '../../domain/repositories/conversation_repository.dart';

// 백엔드 다음 질문 API 연결
final class RemoteConversationRepository implements ConversationRepository {
  const RemoteConversationRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        'drawing-sessions/$drawingSessionId/conversations',
        data: {'analysisId': ?analysisId, 'maxQuestionCount': ?maxQuestionCount},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      final id = _conversationIdOrNull(response.data);
      if (id == null) {
        throw const FormatException('conversationId missing in response');
      }
      return id;
    } on ApiResponseFailure catch (failure) {
      // 이미 진행 중인 대화가 있으면 기존 대화를 이어서 사용한다.
      if (failure.error?.code == 'ACTIVE_CONVERSATION_EXISTS') {
        final existing = _conversationIdOrNull(failure.responseBody);
        if (existing != null) return existing;
      }
      rethrow;
    }
  }

  // 공통 응답 래퍼(data)와 직접 응답 형식 모두에서 conversationId를 추출한다.
  int? _conversationIdOrNull(Object? body) {
    if (body is! Map) return null;
    final data = body['data'];
    final source = data is Map ? data : body;
    final id = source['conversationId'];
    return id is int ? id : (id is num ? id.toInt() : null);
  }

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
