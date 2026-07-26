import 'package:dio/dio.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/drawing/application/activity_completion_controller.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('완료 접수 실패 후 같은 멱등 키와 요청으로 재시도한다', () async {
    final interceptor = _FailOnceCompletionInterceptor();
    final controller = ActivityCompletionController(
      RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [interceptor],
        ),
      ),
      sessionId: 91,
      conversationSkipped: false,
      idempotencyKeyProvider: () => 'stable-activity-key',
    );

    expect(await controller.submit(), isFalse);
    expect(controller.status, ActivityCompletionStatus.failure);
    expect(await controller.submit(), isTrue);
    expect(controller.status, ActivityCompletionStatus.accepted);
    expect(
      interceptor.requests.map((request) {
        return request.headers['Idempotency-Key'];
      }),
      ['stable-activity-key', 'stable-activity-key'],
    );
    expect(interceptor.requests.map((request) => request.data), [
      {'conversationSkipped': false, 'requestReport': true},
      {'conversationSkipped': false, 'requestReport': true},
    ]);
  });

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
}

final class _FailOnceCompletionInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (requests.length == 1) {
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
        statusCode: 202,
        data: const {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': {
            'drawingSessionId': 91,
            'sessionStatus': 'IN_PROGRESS',
            'currentStage': 'REPORTING',
            'analysisId': 801,
            'analysisStatus': 'PENDING',
            'reportId': 901,
            'reportStatus': 'GENERATING',
          },
        },
      ),
    );
  }
}

final class _CompletionStatusInterceptor extends Interceptor {
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
            status: requestCount == 1 ? 'IN_PROGRESS' : 'COMPLETED',
            stage: requestCount == 1 ? 'REPORTING' : 'COMPLETED',
          ),
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
  'childId': 3,
  'drawingType': {'id': 1, 'code': 'HTP', 'name': '집-나무-사람'},
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
