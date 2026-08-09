import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/ai_question.dart';
import '../../domain/models/conversation_start.dart';
import '../../domain/repositories/conversation_repository.dart';

// 백엔드 다음 질문 API 연결
final class RemoteConversationRepository implements ConversationRepository {
  const RemoteConversationRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        'drawing-sessions/$drawingSessionId/conversations',
        // maxQuestionCount 는 싣지 않는다 — 상한을 정하는 것은 서버다(S15P11B209-976).
        // 예전에는 앱 상수 10을 항상 보내서 서버 정책이 한 번도 발동하지 못했다.
        data: {'analysisId': ?analysisId},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      final started = _startResultOrNull(response.data);
      if (started == null) {
        throw const FormatException('conversationId missing in response');
      }
      return started;
    } on ApiResponseFailure catch (failure) {
      // 이미 진행 중인 대화가 있으면 기존 대화를 이어서 사용한다. 이 응답에는
      // conversationId만 실려 상한은 알 수 없다 — 그 경우 상한 도달은 next-question의
      // CONVERSATION_409_001로 알려진다.
      if (failure.error?.code == 'ACTIVE_CONVERSATION_EXISTS') {
        final existing = _startResultOrNull(failure.responseBody);
        if (existing != null) return existing;
      }
      rethrow;
    }
  }

  // 공통 응답 래퍼(data)와 직접 응답 형식 모두에서 시작 결과를 추출한다.
  ConversationStartResult? _startResultOrNull(Object? body) {
    if (body is! Map) return null;
    final data = body['data'];
    final source = data is Map ? data : body;
    final id = _intOrNull(source['conversationId']);
    if (id == null) return null;
    return ConversationStartResult(
      conversationId: id,
      maxQuestionCount: _intOrNull(source['maxQuestionCount']),
    );
  }

  int? _intOrNull(Object? value) =>
      value is int ? value : (value is num ? value.toInt() : null);

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
