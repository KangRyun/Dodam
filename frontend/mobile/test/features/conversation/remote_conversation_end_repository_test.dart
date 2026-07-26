import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('대화 종료는 필수 사유와 멱등 키를 실제 API에 전달한다', () async {
    final interceptor = _ConversationEndInterceptor();
    final repository = RemoteConversationEndRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final result = await repository.endConversation(
      conversationId: 31,
      request: const ConversationEndRequest(
        reason: ConversationCompletionReason.childRequest,
        lastQuestionMessageId: 77,
      ),
      idempotencyKey: 'end-key-1234',
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/conversations/31/end');
    expect(request.headers['Idempotency-Key'], 'end-key-1234');
    expect(request.data, {
      'reason': 'CHILD_REQUEST',
      'lastQuestionMessageId': 77,
    });
    expect(result.completed, isTrue);
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
            'conversationId': 31,
            'conversationStatus': 'COMPLETED',
            'completed': true,
            'completionReason': 'CHILD_REQUEST',
            'completedAt': '2026-07-26T01:00:00Z',
            'nextStage': 'REFLECTION',
          },
        },
      ),
    );
  }
}
