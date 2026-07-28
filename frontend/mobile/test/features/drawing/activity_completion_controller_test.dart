import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/drawing/application/activity_completion_controller.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('REPORTING 세션은 COMPLETED가 될 때까지 조회한다', () async {
    final interceptor = _CompletionStatusInterceptor();
    final controller = ActivityCompletionController.forStatus(
      RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [interceptor],
        ),
      ),
      sessionId: 91,
      pollInterval: Duration.zero,
      maxPollAttempts: 3,
    );

    expect(await controller.pollUntilTerminal(), isTrue);
    expect(controller.status, ActivityCompletionStatus.completed);
    expect(interceptor.requestCount, 2);
  });

  test('REPORTING 세션이 FAILED가 되면 종단 실패로 처리한다', () async {
    final controller = ActivityCompletionController.forStatus(
      RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [
            _CompletionStatusInterceptor(terminalStatus: 'FAILED'),
          ],
        ),
      ),
      sessionId: 91,
      pollInterval: Duration.zero,
      maxPollAttempts: 3,
    );

    expect(await controller.pollUntilTerminal(), isFalse);
    expect(controller.status, ActivityCompletionStatus.terminalFailure);
  });

  test('완료 상태 조회가 실패해도 활동 자체를 실패로 단정하지 않는다', () async {
    final controller = ActivityCompletionController.forStatus(
      RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [_FailingStatusInterceptor()],
        ),
      ),
      sessionId: 91,
      pollInterval: Duration.zero,
      maxPollAttempts: 1,
    );

    expect(await controller.pollUntilTerminal(), isFalse);
    expect(controller.status, ActivityCompletionStatus.pollingFailure);
  });

  test('상태 조회 네트워크 실패 후 수동 재확인할 수 있다', () async {
    final interceptor = _FailOnceStatusInterceptor();
    final controller = ActivityCompletionController.forStatus(
      RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [interceptor],
        ),
      ),
      sessionId: 91,
      pollInterval: Duration.zero,
      maxPollAttempts: 1,
    );

    expect(await controller.pollUntilTerminal(), isFalse);
    expect(controller.status, ActivityCompletionStatus.pollingFailure);
    expect(await controller.pollUntilTerminal(), isTrue);
    expect(controller.status, ActivityCompletionStatus.completed);
    expect(interceptor.requestCount, 2);
  });

  test('dispose 후 진행 중 조회가 끝나도 추가 GET과 상태 알림이 없다', () async {
    final interceptor = _DelayedStatusInterceptor();
    final controller = ActivityCompletionController.forStatus(
      RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [interceptor],
        ),
      ),
      sessionId: 91,
      pollInterval: Duration.zero,
      maxPollAttempts: 3,
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    final polling = controller.pollUntilTerminal();
    await interceptor.requested.future;
    expect(notifications, 1);
    controller.dispose();
    interceptor.complete();

    expect(await polling, isFalse);
    expect(interceptor.requestCount, 1);
    expect(notifications, 1);
  });
}

final class _CompletionStatusInterceptor extends Interceptor {
  _CompletionStatusInterceptor({this.terminalStatus = 'COMPLETED'});

  final String terminalStatus;
  int requestCount = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requestCount += 1;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': _session(
            status: requestCount == 1 ? 'IN_PROGRESS' : terminalStatus,
            stage: requestCount == 1
                ? 'REPORTING'
                : terminalStatus == 'COMPLETED'
                ? 'COMPLETED'
                : 'REPORTING',
          ),
        },
      ),
    );
  }
}

final class _FailOnceStatusInterceptor extends Interceptor {
  int requestCount = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requestCount += 1;
    if (requestCount == 1) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': _session(status: 'COMPLETED', stage: 'COMPLETED'),
        },
      ),
    );
  }
}

final class _DelayedStatusInterceptor extends Interceptor {
  final Completer<void> requested = Completer<void>();
  RequestOptions? _options;
  RequestInterceptorHandler? _handler;
  int requestCount = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requestCount += 1;
    _options = options;
    _handler = handler;
    requested.complete();
  }

  void complete() {
    _handler!.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: _options!,
        statusCode: 200,
        data: {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': _session(status: 'IN_PROGRESS', stage: 'REPORTING'),
        },
      ),
    );
  }
}

final class _FailingStatusInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
  }
}

Map<String, dynamic> _session({
  required String status,
  required String stage,
}) => {
  'drawingSessionId': 91,
  'child': {'childId': 3, 'nickname': '도담'},
  'drawingType': {'drawingTypeId': 1, 'code': 'HTP', 'name': '집-나무-사람'},
  'inputMethod': 'TOUCH',
  'title': null,
  'sessionStatus': status,
  'currentStage': stage,
  'selectedEmotions': const <String>[],
  'expressedEmotionText': null,
  'startedAt': '2026-07-26T10:00:00Z',
  'completedAt': status == 'COMPLETED' ? '2026-07-26T10:10:00Z' : null,
  'conversation': null,
  'latestAnalysis': null,
  'assets': const <Map<String, dynamic>>[],
};
