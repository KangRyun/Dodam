import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Activity Complete는 202 REPORTING 응답과 전체 요청 계약을 처리한다', () async {
    final interceptor = _ActivityCompletionInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final response = await repository.completeActivity(
      42,
      request: const DrawingActivityCompleteRequestDto(
        conversationSkipped: false,
      ),
      idempotencyKey: 'activity-complete-key',
    );

    final request = interceptor.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/drawing-sessions/42/complete');
    expect(request.headers['Idempotency-Key'], 'activity-complete-key');
    expect(request.data, {'conversationSkipped': false, 'requestReport': true});
    expect(response.sessionStatus, 'IN_PROGRESS');
    expect(response.currentStage, 'REPORTING');
    expect(response.analysisStatus, 'PENDING');
    expect(response.reportId, 501);
    expect(response.reportStatus, 'GENERATING');
  });

  test('Activity Complete는 정상 Body여도 HTTP 202가 아니면 거부한다', () async {
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [_ActivityCompletionInterceptor(statusCode: 200)],
      ),
    );

    await expectLater(
      repository.completeActivity(
        42,
        request: const DrawingActivityCompleteRequestDto(
          conversationSkipped: false,
        ),
        idempotencyKey: 'activity-complete-key',
      ),
      throwsStateError,
    );
  });

  test('Drawing Session 상세의 완료 상태와 분석·reportId를 파싱한다', () async {
    final interceptor = _SessionDetailInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final detail = await repository.getSessionCompletionStatus(42);

    final request = interceptor.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/drawing-sessions/42');
    expect(detail.sessionStatus, 'COMPLETED');
    expect(detail.currentStage, 'COMPLETED');
    expect(detail.latestAnalysis?.drawingAnalysisId, 700);
    expect(detail.latestAnalysis?.analysisStatus, 'SUCCESS');
    expect(detail.reportId, 501);
    expect(detail.conversationId, 20);
  });
}

final class _ActivityCompletionInterceptor extends Interceptor {
  _ActivityCompletionInterceptor({this.statusCode = 202});

  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: statusCode,
        data: const {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': {
            'drawingSessionId': 42,
            'sessionStatus': 'IN_PROGRESS',
            'currentStage': 'REPORTING',
            'analysisId': 700,
            'analysisStatus': 'PENDING',
            'reportId': 501,
            'reportStatus': 'GENERATING',
          },
        },
      ),
    );
  }
}

final class _SessionDetailInterceptor extends Interceptor {
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
            'drawingSessionId': 42,
            'sessionStatus': 'COMPLETED',
            'currentStage': 'COMPLETED',
            'latestAnalysis': {
              'drawingAnalysisId': 700,
              'analysisScope': 'FINAL',
              'analysisType': 'ACTIVITY_REPORT',
              'analysisStatus': 'SUCCESS',
            },
            'reportId': 501,
            'conversationId': 20,
          },
        },
      ),
    );
  }
}
