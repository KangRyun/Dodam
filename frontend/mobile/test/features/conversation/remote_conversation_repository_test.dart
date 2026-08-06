import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 질문 수 상한의 주인이 앱에서 서버로 넘어간 자리 (S15P11B209-976).
///
/// 예전에는 앱 상수 10을 시작 요청에 항상 실어 보냈고, 서버는 그 값을 그대로 저장했다.
/// 여기서 보는 것은 두 가지다 — 앱이 값을 **보내지 않는가**, 그리고 서버가 정한 값을
/// **읽어 오는가**. 둘 중 하나만 되면 정책이 화면까지 도달하지 못한다.
void main() {
  test('대화 시작 요청에 maxQuestionCount를 싣지 않는다', () async {
    final interceptor = _ConversationStartInterceptor();
    final repository = _repository(interceptor);

    await repository.startConversation(
      drawingSessionId: 100,
      analysisId: 700,
      idempotencyKey: 'conversation-start-key',
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/drawing-sessions/100/conversations');
    expect(request.headers['Idempotency-Key'], 'conversation-start-key');
    expect(request.data, {'analysisId': 700});
    expect((request.data! as Map).containsKey('maxQuestionCount'), isFalse);
  });

  test('서버가 정한 maxQuestionCount를 응답에서 읽는다', () async {
    final repository = _repository(
      _ConversationStartInterceptor(maxQuestionCount: 3),
    );

    final started = await repository.startConversation(
      drawingSessionId: 100,
      idempotencyKey: 'conversation-start-key',
    );

    expect(started.conversationId, 8001);
    // HTP 주제당 상한. 앱은 이 숫자를 알지 못한 채 받아 쓴다.
    expect(started.maxQuestionCount, 3);
  });

  test('진행 중 대화를 이어받으면 상한은 알 수 없는 채로 남는다', () async {
    // 409 응답에는 conversationId만 실린다. 앱이 기본값을 지어내지 않고 null로 두어야
    // 서버보다 먼저 대화를 끊지 않는다 — 상한 도달은 next-question이 알려준다.
    final repository = _repository(const _ActiveConversationInterceptor());

    final started = await repository.startConversation(
      drawingSessionId: 100,
      idempotencyKey: 'conversation-start-key',
    );

    expect(started.conversationId, 7777);
    expect(started.maxQuestionCount, isNull);
  });
}

RemoteConversationRepository _repository(Interceptor interceptor) =>
    RemoteConversationRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

final class _ConversationStartInterceptor extends Interceptor {
  _ConversationStartInterceptor({this.maxQuestionCount = 5});

  final int maxQuestionCount;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 201,
        data: {
          'success': true,
          'code': 'COMMON_201',
          'message': '요청에 성공했습니다.',
          'data': {
            'conversationId': 8001,
            'drawingSessionId': 100,
            'status': 'CONVERSING',
            'difficulty': 'LOWER_ELEMENTARY',
            'maxQuestionCount': maxQuestionCount,
            'questionCount': 0,
            'nextAction': 'REQUEST_NEXT_QUESTION',
            'startedAt': '2026-08-06T01:00:00Z',
          },
        },
      ),
    );
  }
}

final class _ActiveConversationInterceptor extends Interceptor {
  const _ActiveConversationInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 409,
          data: const {
            'success': false,
            'code': 'ACTIVE_CONVERSATION_EXISTS',
            'message': '이미 진행 중인 대화가 있습니다.',
            'data': {'conversationId': 7777},
          },
        ),
      ),
    );
  }
}
