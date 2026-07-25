import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('별도 안내 문구가 없는 그림 유형도 역직렬화한다', () {
    final type = DrawingTypeDto.fromJson(const {
      'drawingTypeId': 12,
      'code': 'NO_GUIDE',
      'name': '안내 없는 활동',
      'activityCategory': 'GENERAL',
      'selectableBy': 'BOTH',
      'recommendedAgeMin': null,
      'recommendedAgeMax': null,
      'guideText': null,
      'displayOrder': 50,
    });

    expect(type.guideText, isNull);
  });

  test('그림 유형 조회는 최신 Query와 공통 응답 봉투를 처리한다', () async {
    final interceptor = _DrawingStartInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final page = await repository.getDrawingTypes(
      childId: 3,
      category: 'GENERAL',
      activeOnly: false,
    );

    final request = interceptor.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/drawing-types');
    expect(request.queryParameters, {
      'childId': 3,
      'category': 'GENERAL',
      'activeOnly': false,
    });
    expect(page.content.single.code, 'FREE_DRAWING');
    expect(page.content.single.guideText, '자유롭게 그려 보세요.');
  });

  test('그림 세션 생성은 공통 응답 봉투의 data를 역직렬화한다', () async {
    final interceptor = _DrawingStartInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final session = await repository.createSession(
      const CreateDrawingSessionRequestDto(
        childId: 3,
        drawingTypeId: 11,
        inputMethod: 'CANVAS',
        clientStartedAt: '2026-07-25T08:00:00.000Z',
      ),
    );

    final request = interceptor.requests.single;
    expect(request.uri.path, '/api/v1/drawing-sessions');
    expect(request.data, {
      'childId': 3,
      'drawingTypeId': 11,
      'inputMethod': 'CANVAS',
      'clientStartedAt': '2026-07-25T08:00:00.000Z',
    });
    expect(
      request.headers['Idempotency-Key'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(session.drawingSessionId, 42);
    expect(session.drawingType.code, 'FREE_DRAWING');
  });
}

final class _DrawingStartInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (options.uri.path.endsWith('/drawing-types')) {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const {
            'success': true,
            'code': 'COMMON_200',
            'message': '요청에 성공했습니다.',
            'data': {
              'content': [
                {
                  'drawingTypeId': 11,
                  'code': 'FREE_DRAWING',
                  'name': '자유 그리기',
                  'activityCategory': 'GENERAL',
                  'selectableBy': 'BOTH',
                  'recommendedAgeMin': 4,
                  'recommendedAgeMax': 12,
                  'guideText': '자유롭게 그려 보세요.',
                  'displayOrder': 20,
                },
              ],
              'page': 0,
              'size': 1,
              'totalElements': 1,
              'totalPages': 1,
              'hasNext': false,
            },
          },
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 201,
        data: const {
          'success': true,
          'code': 'COMMON_201',
          'message': '요청에 성공했습니다.',
          'data': {
            'drawingSessionId': 42,
            'childId': 3,
            'drawingType': {
              'drawingTypeId': 11,
              'code': 'FREE_DRAWING',
              'name': '자유 그리기',
            },
            'inputMethod': 'CANVAS',
            'title': null,
            'sessionStatus': 'DRAWING',
            'currentStage': 'DRAWING',
            'selectedEmotions': null,
            'expressedEmotionText': null,
            'startedAt': '2026-07-24T10:00:00Z',
            'completedAt': null,
            'conversation': null,
            'latestAnalysis': null,
            'assets': [],
            'guideText': '자유롭게 그려 보세요.',
          },
        },
      ),
    );
  }
}
