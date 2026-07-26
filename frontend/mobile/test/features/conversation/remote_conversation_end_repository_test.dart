import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reason을 포함해 Conversation End를 요청하고 data 응답을 파싱한다', () async {
    final interceptor = _ConversationEndInterceptor();
    final repository = RemoteConversationEndRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final result = await repository.endConversation(
      conversationId: 20,
      request: const ConversationEndRequest(
        reason: ConversationEndReason.childRequest,
        lastQuestionMessageId: 31,
      ),
      idempotencyKey: 'conversation-end-key',
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/conversations/20/end');
    expect(request.headers['Idempotency-Key'], 'conversation-end-key');
    expect(request.data, {
      'reason': 'CHILD_REQUEST',
      'lastQuestionMessageId': 31,
    });
    expect(result.conversationId, 20);
    expect(result.conversationStatus, 'COMPLETED');
    expect(result.completed, isTrue);
    expect(result.completionReason, 'CHILD_REQUEST');
    expect(result.nextStage, 'REFLECTION');
  });
}

final class _ConversationEndInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': {
            'conversationId': 20,
            'conversationStatus': 'COMPLETED',
            'completed': true,
            'completionReason': 'CHILD_REQUEST',
            'completedAt': '2026-07-26T12:00:00',
            'nextStage': 'REFLECTION',
          },
        },
      ),
    );
  }
}
