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
