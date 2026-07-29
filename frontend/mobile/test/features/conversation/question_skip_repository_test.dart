import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('질문 건너뛰기를 CONV-08 계약으로 전송한다', () async {
    final interceptor = _SkipInterceptor();
    final repository = RemoteQuestionSkipRepository(_client(interceptor));

    final result = await repository.skipQuestion(
      conversationId: 20,
      request: const QuestionSkipRequest(questionMessageId: 803),
      idempotencyKey: 'skip-key-1234',
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/conversations/20/skip');
    expect(request.headers['Idempotency-Key'], 'skip-key-1234');
    expect(request.data, {'questionMessageId': 803});
    expect(result.skipped, isTrue);
  });

  test('이미 건너뛴 질문의 재요청도 성공으로 읽는다', () async {
    final interceptor = _SkipInterceptor(alreadySkipped: true);
    final repository = RemoteQuestionSkipRepository(_client(interceptor));

    final result = await repository.skipQuestion(
      conversationId: 20,
      request: const QuestionSkipRequest(questionMessageId: 803),
      idempotencyKey: 'skip-key-1234',
    );

    expect(result.skipped, isTrue);
  });

  test('서버가 건너뛰지 않았다고 응답하면 그대로 읽는다', () async {
    final interceptor = _SkipInterceptor(skipped: false);
    final repository = RemoteQuestionSkipRepository(_client(interceptor));

    final result = await repository.skipQuestion(
      conversationId: 20,
      request: const QuestionSkipRequest(questionMessageId: 803),
      idempotencyKey: 'skip-key-1234',
    );

    expect(result.skipped, isFalse);
  });
}

ApiClient _client(Interceptor interceptor) => ApiClient(
  environment: ApiEnvironment.fromBaseUrl('https://example.test'),
  interceptors: [interceptor],
);

final class _SkipInterceptor extends Interceptor {
  _SkipInterceptor({this.skipped = true, this.alreadySkipped = false});

  final bool skipped;
  final bool alreadySkipped;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'success': true,
          'code': 'OK',
          'message': '요청이 성공했습니다.',
          'data': {
            'conversationId': 20,
            'questionMessageId': 803,
            'skipped': skipped,
            'alreadySkipped': alreadySkipped,
            'skippedQuestionCount': alreadySkipped ? 1 : 2,
            'conversationStatus': 'CONVERSING',
          },
        },
      ),
    );
  }
}
