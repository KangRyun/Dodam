import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('대화 내역에서 업로드한 메시지의 STT 결과를 조회한다', () async {
    final interceptor = _SttMessageInterceptor();
    final repository = RemoteSttResultRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final result = await repository.getResult(
      conversationId: 20,
      messageId: 30,
      afterSequence: 2,
    );

    final request = interceptor.request!;
    expect(request.uri.path, '/api/v1/conversations/20/messages');
    expect(request.queryParameters['afterSequence'], 2);
    expect(result.status, SttSpeechStatus.success);
    expect(result.text, '강아지랑 같이 있어');
  });

  testWidgets('STT 성공 결과를 아동 화면에 표시한다', (tester) async {
    final controller = SttResultController(
      const _FakeSttResultRepository(
        SttResult(
          messageId: 30,
          status: SttSpeechStatus.success,
          text: '강아지랑 같이 있어',
        ),
      ),
      conversationId: 20,
      pollInterval: Duration.zero,
      maxAttempts: 1,
    );
    addTearDown(controller.dispose);

    await controller.watch(messageId: 30, sequence: 3);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SttResultPanel(controller: controller)),
      ),
    );

    expect(find.byKey(const ValueKey('stt-result-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('stt-result-text')), findsOneWidget);
    expect(find.text('강아지랑 같이 있어'), findsOneWidget);
  });

  test('PENDING이 계속되면 지연 상태로 전환한다', () async {
    final controller = SttResultController(
      const _FakeSttResultRepository(
        SttResult(messageId: 30, status: SttSpeechStatus.pending),
      ),
      conversationId: 20,
      pollInterval: Duration.zero,
      maxAttempts: 2,
      delay: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.watch(messageId: 30, sequence: 3);

    expect(controller.status, SttResultStatus.delayed);
  });
}

final class _SttMessageInterceptor extends Interceptor {
  RequestOptions? request;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    request = options;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {
          'data': {
            'content': [
              {
                'messageId': 30,
                'parentMessageId': 10,
                'sequence': 3,
                'messageType': 'ANSWER_VOICE',
                'sttText': '강아지랑 같이 있어',
                'speechStatus': 'SUCCESS',
              },
            ],
            'page': 0,
            'size': 10,
            'totalElements': 1,
            'totalPages': 1,
            'first': true,
            'last': true,
            'hasNext': false,
          },
        },
      ),
    );
  }
}

final class _FakeSttResultRepository implements SttResultRepository {
  const _FakeSttResultRepository(this.result);

  final SttResult result;

  @override
  Future<SttResult> getResult({
    required int conversationId,
    required int messageId,
    required int afterSequence,
  }) async => result;
}
