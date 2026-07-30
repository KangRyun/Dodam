import 'dart:async';

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

  testWidgets('긴 STT 결과와 큰 글자도 화면 경계 안에서 스크롤해 확인한다', (tester) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SttResultController(
      const _FakeSttResultRepository(
        SttResult(
          messageId: 31,
          status: SttSpeechStatus.success,
          text: '엄마 아빠와 강아지가 거실에 함께 앉아서 오늘 있었던 일을 아주 천천히 이야기하고 있어요.',
        ),
      ),
      conversationId: 20,
      pollInterval: Duration.zero,
      maxAttempts: 1,
    );
    addTearDown(controller.dispose);
    await controller.watch(messageId: 31, sequence: 4);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SttResultPanel(controller: controller, maxHeight: 150),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final panel = find.byKey(const ValueKey('stt-result-panel'));
    expect(panel, findsOneWidget);
    final panelRect = tester.getRect(panel);
    expect(panelRect.left, greaterThanOrEqualTo(0));
    expect(panelRect.right, lessThanOrEqualTo(320));
    expect(panelRect.top, greaterThanOrEqualTo(0));
    expect(panelRect.bottom, lessThanOrEqualTo(180));

    await tester.drag(
      find.byKey(const ValueKey('stt-result-scroll')),
      const Offset(0, -200),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final dismissSize = tester.getSize(
      find.byKey(const ValueKey('stt-result-dismiss')),
    );
    expect(dismissSize.width, greaterThanOrEqualTo(48));
    expect(dismissSize.height, greaterThanOrEqualTo(48));
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

  test('dispose 뒤 늦게 도착한 polling 응답은 상태를 바꾸지 않는다', () async {
    final completer = Completer<SttResult>();
    final controller = SttResultController(
      _PendingSttRepository(completer.future),
      conversationId: 20,
      pollInterval: Duration.zero,
      delay: (_) async {},
    );

    final pending = controller.watch(messageId: 30, sequence: 3);
    controller.dispose();
    completer.complete(
      const SttResult(
        messageId: 30,
        status: SttSpeechStatus.success,
        text: '완성된 문장',
      ),
    );

    await expectLater(pending, completes);
    expect(controller.status, SttResultStatus.polling);
    expect(controller.text, isNull);
  });

  test('dispose 뒤에는 새 polling을 시작하지 않는다', () async {
    final repository = _CountingSttRepository();
    final controller = SttResultController(
      repository,
      conversationId: 20,
      pollInterval: Duration.zero,
      delay: (_) async {},
    );

    controller.dispose();
    await controller.watch(messageId: 30, sequence: 3);

    expect(repository.callCount, 0);
  });
}

final class _PendingSttRepository implements SttResultRepository {
  const _PendingSttRepository(this.pending);

  final Future<SttResult> pending;

  @override
  Future<SttResult> getResult({
    required int conversationId,
    required int messageId,
    required int afterSequence,
  }) => pending;
}

final class _CountingSttRepository implements SttResultRepository {
  int callCount = 0;

  @override
  Future<SttResult> getResult({
    required int conversationId,
    required int messageId,
    required int afterSequence,
  }) async {
    callCount += 1;
    return const SttResult(
      messageId: 30,
      status: SttSpeechStatus.success,
      text: '완성된 문장',
    );
  }
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
