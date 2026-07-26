import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/core/network/auth/access_token_provider.dart';
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

  test('Draft 저장은 JSON MIME multipart와 공통 응답 봉투를 처리한다', () async {
    final interceptor = _DraftInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final response = await repository.saveDraft(
      42,
      const BinaryUploadDto(
        bytes: [137, 80, 78, 71],
        fileName: 'drawing-draft.png',
        mimeType: 'image/png',
      ),
      const DraftCanvasStateDto(
        lastEventSequence: 17,
        toolState: null,
        viewport: null,
        clientSavedAt: '2026-07-25T17:00:00+09:00',
      ),
    );

    final request = interceptor.requests.single;
    expect(request.method, 'PUT');
    expect(request.uri.path, '/api/v1/drawing-sessions/42/draft');
    final form = request.data as FormData;
    expect(form.fields, isEmpty);
    final preview = form.files.singleWhere((part) => part.key == 'preview');
    expect(preview.value.filename, 'drawing-draft.png');
    expect(preview.value.contentType?.toString(), 'image/png');
    expect(await _multipartBytes(preview.value), [137, 80, 78, 71]);

    final canvasState = form.files.singleWhere(
      (part) => part.key == 'canvasState',
    );
    expect(canvasState.value.filename, 'canvas-state.json');
    expect(canvasState.value.contentType?.toString(), 'application/json');
    expect(jsonDecode(utf8.decode(await _multipartBytes(canvasState.value))), {
      'lastEventSequence': 17,
      'clientSavedAt': '2026-07-25T17:00:00+09:00',
    });
    expect(response.drawingAssetId, 140);
    expect(response.assetVersion, 4);
    expect(response.lastEventSequence, 17);
    expect(response.widthPx, isNull);
    expect(response.heightPx, 1080);
  });

  test('활성 그림 세션 조회는 공통 응답 data를 역직렬화한다', () async {
    final interceptor = _ActiveSessionInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [interceptor],
      ),
    );

    final session = await repository.getActiveSession(3);

    final request = interceptor.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/drawing-sessions/active');
    expect(request.queryParameters, {'childId': 3});
    expect(session?.drawingSessionId, 42);
    expect(session?.childId, 3);
    expect(session?.latestDraft?.drawingAssetId, 140);
  });

  test('활성 그림 세션 없음 오류는 null로 변환한다', () async {
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [_ActiveSessionInterceptor(errorCode: 'DRAWING_404_005')],
      ),
    );

    expect(await repository.getActiveSession(3), isNull);
  });

  test('최신 Draft 없음 오류는 null로 변환한다', () async {
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [_DraftQueryInterceptor(errorCode: 'DRAWING_404_004')],
      ),
    );

    expect(await repository.getDraft(42), isNull);
  });

  test('Draft preview는 Backend Asset 경로에서 bytes로 내려받는다', () async {
    final interceptor = _DraftPreviewInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        accessTokenProvider: const _AccessTokenProvider(),
        interceptors: [interceptor],
      ),
    );

    final bytes = await repository.downloadDraftPreview(
      '/api/v1/drawing-assets/140/file',
    );

    expect(bytes, Uint8List.fromList([137, 80, 78, 71]));
    final request = interceptor.requests.single;
    expect(request.uri.path, '/api/v1/drawing-assets/140/file');
    expect(request.responseType, ResponseType.bytes);
    expect(request.headers['Authorization'], 'Bearer access-token');
  });

  for (final invalidUrl in const [
    'https://evil.example/api/v1/drawing-assets/140/file',
    '/api/v1/drawing-assets/140/file?token=leak',
    '/api/v1/drawing-assets/0/file',
    '/api/v1/children/3/file',
  ]) {
    test('Draft preview는 허용되지 않은 URL을 요청하지 않는다: $invalidUrl', () async {
      final interceptor = _DraftPreviewInterceptor();
      final repository = RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [interceptor],
        ),
      );

      await expectLater(
        repository.downloadDraftPreview(invalidUrl),
        throwsArgumentError,
      );
      expect(interceptor.requests, isEmpty);
    });
  }

  for (final failure in const [
    (statusCode: 400, code: 'DRAWING_400_008'),
    (statusCode: 409, code: 'DRAWING_409_009'),
    (statusCode: 409, code: 'DRAWING_409_010'),
    (statusCode: 415, code: 'COMMON_415_001'),
  ]) {
    test('Draft 저장 ${failure.code} 응답을 ApiResponseFailure로 변환한다', () async {
      final repository = RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [
            _DraftInterceptor(
              errorStatusCode: failure.statusCode,
              errorCode: failure.code,
            ),
          ],
        ),
      );

      await expectLater(
        repository.saveDraft(
          42,
          const BinaryUploadDto(
            bytes: [137, 80, 78, 71],
            fileName: 'drawing-draft.png',
            mimeType: 'image/png',
          ),
          const DraftCanvasStateDto(
            lastEventSequence: 17,
            toolState: null,
            viewport: null,
            clientSavedAt: '2026-07-25T17:00:00+09:00',
          ),
        ),
        throwsA(
          isA<ApiResponseFailure>()
              .having(
                (failure) => failure.statusCode,
                'statusCode',
                failure.statusCode,
              )
              .having(
                (failure) => failure.error?.code,
                'error code',
                failure.code,
              ),
        ),
      );
    });
  }

  for (final statusCode in [201, 200]) {
    test('Stroke Batch HTTP $statusCode 응답과 공통 봉투를 처리한다', () async {
      final interceptor = _StrokeBatchInterceptor(statusCode: statusCode);
      final repository = RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [interceptor],
        ),
      );

      final response = await repository.sendStrokeBatch(42, _strokeRequest);

      final request = interceptor.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/drawing-sessions/42/stroke-batches');
      expect(request.contentType, Headers.jsonContentType);
      expect(request.headers, isNot(contains('Idempotency-Key')));
      expect(request.data, {
        'batchSequence': 7,
        'firstEventSequence': 13,
        'lastEventSequence': 14,
        'clientCreatedAt': '2026-07-25T08:00:00.000Z',
        'events': [
          {
            'sequence': 13,
            'eventType': 'STROKE',
            'tool': 'PEN',
            'color': '#E35D6A',
            'width': 8.0,
            'points': [
              {'x': 0.1, 'y': 0.2, 't': 0, 'pressure': 0.4},
              {'x': 0.3, 'y': 0.4, 't': 20},
            ],
          },
          {'sequence': 14, 'eventType': 'UNDO', 'points': <Object?>[]},
        ],
        'metrics': {
          'undoCountDelta': 1,
          'redoCountDelta': 0,
          'eraseCountDelta': 0,
          'pauseDurationMsDelta': 0,
        },
      });
      expect(response.batchId, 501);
      expect(response.batchSequence, 7);
      expect(response.acceptedEventCount, 2);
      expect(response.lastEventSequence, 14);
      expect(response.receivedAt, '2026-07-25T08:00:01Z');
    });
  }

  for (final statusCode in [400, 404, 409]) {
    test('Stroke Batch HTTP $statusCode를 ApiResponseFailure로 변환한다', () async {
      final repository = RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [_StrokeBatchInterceptor(errorStatusCode: statusCode)],
        ),
      );

      await expectLater(
        repository.sendStrokeBatch(42, _strokeRequest),
        throwsA(
          isA<ApiResponseFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            statusCode,
          ),
        ),
      );
    });
  }
}

const _strokeRequest = StrokeBatchRequestDto(
  batchSequence: 7,
  firstEventSequence: 13,
  lastEventSequence: 14,
  clientCreatedAt: '2026-07-25T08:00:00.000Z',
  events: [
    StrokeBatchEventDto(
      sequence: 13,
      eventType: 'STROKE',
      tool: 'PEN',
      color: '#E35D6A',
      width: 8,
      points: [
        StrokePointDto(x: 0.1, y: 0.2, t: 0, pressure: 0.4),
        StrokePointDto(x: 0.3, y: 0.4, t: 20),
      ],
    ),
    StrokeBatchEventDto(sequence: 14, eventType: 'UNDO', points: []),
  ],
  metrics: StrokeMetricsDto(undoCountDelta: 1),
);

Future<List<int>> _multipartBytes(MultipartFile file) => file
    .finalize()
    .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));

final class _DraftInterceptor extends Interceptor {
  _DraftInterceptor({this.errorStatusCode, this.errorCode});

  final int? errorStatusCode;
  final String? errorCode;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final failureStatus = errorStatusCode;
    if (failureStatus != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: failureStatus,
            data: {
              'success': false,
              'code': errorCode,
              'message': 'Draft 저장 요청 실패',
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {
          'success': true,
          'code': 'COMMON_200',
          'message': '요청에 성공했습니다.',
          'data': {
            'drawingAssetId': 140,
            'drawingSessionId': 42,
            'assetType': 'DRAFT',
            'assetVersion': 4,
            'lastEventSequence': 17,
            'finalSnapshot': false,
            'contentType': 'image/png',
            'fileSize': 4096,
            'widthPx': null,
            'heightPx': 1080,
            'clientSavedAt': '2026-07-25T08:00:00Z',
            'savedAt': '2026-07-25T08:00:01Z',
            'expiresAt': null,
            'previewUrl': '/api/v1/drawing-assets/140/file',
            'canvasState': {
              'lastEventSequence': 17,
              'clientSavedAt': '2026-07-25T08:00:00Z',
            },
          },
        },
      ),
    );
  }
}

final class _StrokeBatchInterceptor extends Interceptor {
  _StrokeBatchInterceptor({this.statusCode = 201, this.errorStatusCode});

  final int statusCode;
  final int? errorStatusCode;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final failureStatus = errorStatusCode;
    if (failureStatus != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: failureStatus,
            data: {
              'success': false,
              'code': 'DRAWING_$failureStatus',
              'message': 'Stroke Batch 요청 실패',
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: statusCode,
        data: const {
          'success': true,
          'code': 'COMMON_201',
          'message': '요청에 성공했습니다.',
          'data': {
            'batchId': 501,
            'batchSequence': 7,
            'acceptedEventCount': 2,
            'lastEventSequence': 14,
            'receivedAt': '2026-07-25T08:00:01Z',
          },
        },
      ),
    );
  }
}

final class _ActiveSessionInterceptor extends Interceptor {
  _ActiveSessionInterceptor({this.errorCode});

  final String? errorCode;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final code = errorCode;
    if (code != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 404,
            data: {
              'success': false,
              'code': code,
              'message': '활성 그림 세션이 없습니다.',
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }
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
            'childId': 3,
            'drawingType': {
              'drawingTypeId': 11,
              'code': 'FREE_DRAWING',
              'name': '자유 그리기',
            },
            'inputMethod': 'CANVAS',
            'sessionStatus': 'DRAWING',
            'currentStage': 'DRAWING',
            'startedAt': '2026-07-25T08:00:00Z',
            'latestDraft': {
              'drawingAssetId': 140,
              'assetVersion': 4,
              'lastEventSequence': 17,
              'savedAt': '2026-07-25T08:05:00Z',
            },
          },
        },
      ),
    );
  }
}

final class _DraftQueryInterceptor extends Interceptor {
  _DraftQueryInterceptor({required this.errorCode});

  final String errorCode;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 404,
          data: {
            'success': false,
            'code': errorCode,
            'message': '최신 Draft가 없습니다.',
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }
}

final class _DraftPreviewInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<List<int>>(
        requestOptions: options,
        statusCode: 200,
        data: const [137, 80, 78, 71],
      ),
    );
  }
}

final class _AccessTokenProvider implements AccessTokenProvider {
  const _AccessTokenProvider();

  @override
  Future<String?> readAccessToken() async => 'access-token';
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
