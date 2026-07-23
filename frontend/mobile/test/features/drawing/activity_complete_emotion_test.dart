import 'dart:async';

import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/data/repositories/mock_drawing_repository.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Remote Draft 저장은 v1.0 PUT endpoint와 multipart를 사용한다', () async {
    final recorder = _RecordingInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [recorder],
      ),
    );

    final result = await repository.saveDraft(
      42,
      _png,
      const DraftCanvasStateDto(
        lastEventSequence: 17,
        toolState: null,
        viewport: null,
        clientSavedAt: '2026-07-22T10:00:00Z',
      ),
    );

    final request = recorder.requests.single;
    expect(request.method, 'PUT');
    expect(request.uri.path, '/api/v1/drawing-sessions/42/draft');
    final form = request.data as FormData;
    expect(form.files.single.key, 'preview');
    expect(form.fields.single.key, 'canvasState');
    expect(form.fields.single.value, contains('"lastEventSequence":17'));
    expect(form.fields.map((field) => field.key), isNot(contains('image')));
    expect(
      form.fields.map((field) => field.key),
      isNot(contains('lastEventSequence')),
    );
    expect(result.drawingAssetId, 140);
    expect(result.assetVersion, 4);
  });

  test('Remote 객체 탐지는 복수형 analyses endpoint와 최신 DRAFT ID를 사용한다', () async {
    final recorder = _RecordingInterceptor();
    final repository = RemoteDrawingRepository(
      ApiClient(
        environment: ApiEnvironment.fromBaseUrl('https://example.test'),
        interceptors: [recorder],
      ),
    );

    final result = await repository.requestObjectDetection(
      42,
      const ObjectDetectionRequestDto(drawingAssetId: 140),
    );

    final request = recorder.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/drawing-sessions/42/analyses');
    expect(request.uri.path.endsWith('/analysis'), isFalse);
    expect(request.data, {
      'drawingAssetId': 140,
      'analysisType': 'OBJECT_DETECTION',
    });
    expect(result.drawingAssetId, 140);
    expect(result.status, 'SUCCEEDED');
  });

  test(
    'Remote는 drawing-complete와 PUT reflection v1.0 endpoint를 사용한다',
    () async {
      final recorder = _RecordingInterceptor();
      final repository = RemoteDrawingRepository(
        ApiClient(
          environment: ApiEnvironment.fromBaseUrl('https://example.test'),
          interceptors: [recorder],
        ),
      );

      await repository.completeDrawingStage(
        42,
        finalImage: _png,
        metadata: const DrawingCompleteMetadataDto(
          lastEventSequence: 17,
          drawingDurationMs: 1000,
          clientCompletedAt: '2026-07-22T10:00:00Z',
        ),
        idempotencyKey: 'request-key',
      );
      expect(recorder.requests.first.method, 'POST');
      expect(
        recorder.requests.first.uri.path,
        '/api/v1/drawing-sessions/42/drawing-complete',
      );
      expect(recorder.requests.first.uri.path.endsWith('/complete'), isFalse);
      expect(recorder.requests.first.headers['Idempotency-Key'], 'request-key');
      final form = recorder.requests.first.data as FormData;
      expect(form.files.single.key, 'finalImage');
      expect(form.fields.single.key, 'metadata');
      expect(form.fields.single.value, contains('"lastEventSequence":17'));
      expect(form.fields.single.value, contains('"drawingDurationMs":1000'));
      expect(form.fields.single.value, contains('"clientCompletedAt"'));
      expect(form.fields.single.value, isNot(contains('sourceAssetId')));

      await repository.saveReflection(
        42,
        const SaveDrawingReflectionRequestDto(
          title: null,
          selectedEmotions: [DrawingEmotionType.happy],
          expressedEmotionText: null,
          skipped: false,
        ),
      );
      expect(recorder.requests.last.method, 'PUT');
      expect(
        recorder.requests.last.uri.path,
        '/api/v1/drawing-sessions/42/reflection',
      );
    },
  );

  testWidgets('완료 버튼은 확인 Dialog를 열고 조금 더 그리면 Canvas를 유지한다', (tester) async {
    await _pumpDrawing(tester, repository: const MockDrawingRepository());
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();

    expect(find.text('그림을 다 그렸나요?'), findsOneWidget);
    await tester.tap(find.text('조금 더 그릴래요'));
    await tester.pumpAndSettle();

    expect(find.text('그림을 다 그렸나요?'), findsNothing);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('완료 성공 시 감정 선택 화면으로 이동한다', (tester) async {
    await _pumpDrawing(tester, repository: const MockDrawingRepository());
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(find.text('내 마음 고르기'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
  });

  testWidgets('완료 실패 시 Canvas와 Stroke를 유지하고 이동하지 않는다', (tester) async {
    await _pumpDrawing(
      tester,
      repository: const MockDrawingRepository(
        completionScenario: MockCompletionScenario.failure,
      ),
    );
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.textContaining('그림은 그대로'), findsOneWidget);
    expect(find.text('내 마음 고르기'), findsNothing);
  });

  testWidgets('sessionId가 없으면 완료 API를 호출하지 않는다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpDrawing(tester, repository: repository, sessionId: null);
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(repository.completeCalls, 0);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.textContaining('아직 활동을 완료할 수 없어요'), findsOneWidget);
  });

  testWidgets('완료 제출 중 중복 요청을 보내지 않는다', (tester) async {
    final completer = Completer<DrawingStageCompleteResponseDto>();
    final repository = _CompletionRepository(completer: completer);
    await _pumpDrawing(tester, repository: repository);
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pump();

    expect(repository.completeCalls, 1);
    completer.complete(_completeResponse);
    await tester.pumpAndSettle();
    expect(find.text('내 마음 고르기'), findsOneWidget);
  });

  testWidgets('동일 Canvas 완료 재시도는 같은 Idempotency 요청을 재사용한다', (tester) async {
    final repository = _CompletionRepository(
      completionError: StateError('lost response'),
    );
    await _pumpDrawing(tester, repository: repository);
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    repository.completionError = null;
    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(repository.completionKeys, hasLength(2));
    expect(repository.completionKeys[1], repository.completionKeys[0]);
    expect(
      repository.completionMetadata[1],
      same(repository.completionMetadata[0]),
    );
  });

  testWidgets('감정 6개를 표시하고 여러 카드의 로컬 선택 상태를 유지한다', (tester) async {
    await _pumpEmotion(tester);

    for (final label in ['기쁨', '슬픔', '화남', '무서움', '편안함', '모르겠어']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.tap(find.byKey(const ValueKey('emotion-편안함')));
    await tester.pump();

    expect(_choice(tester, '기쁨').isSelected, isTrue);
    expect(_choice(tester, '편안함').isSelected, isTrue);
    expect(_choice(tester, '슬픔').isSelected, isFalse);
  });

  testWidgets('선택적 제목은 감정 선택 후에도 유지된다', (tester) async {
    await _pumpEmotion(tester);

    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '우리 가족 소풍',
    );
    await tester.tap(find.byKey(const ValueKey('emotion-편안함')));
    await tester.pump();

    expect(find.text('우리 가족 소풍'), findsOneWidget);
    expect(_choice(tester, '편안함').isSelected, isTrue);
  });

  test('Emotion API enum은 v1.0 값만 사용한다', () {
    expect(DrawingEmotionType.values.map((emotion) => emotion.apiValue), [
      'HAPPY',
      'SAD',
      'ANGRY',
      'SCARED',
      'CALM',
      'UNKNOWN',
    ]);
  });

  testWidgets('UNKNOWN과 일반 감정은 동시에 선택되지 않는다', (tester) async {
    await _pumpEmotion(tester);
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.tap(find.byKey(const ValueKey('emotion-편안함')));
    await tester.tap(find.byKey(const ValueKey('emotion-모르겠어')));
    await tester.pump();

    expect(_choice(tester, '기쁨').isSelected, isFalse);
    expect(_choice(tester, '편안함').isSelected, isFalse);
    expect(_choice(tester, '모르겠어').isSelected, isTrue);

    await tester.tap(find.byKey(const ValueKey('emotion-슬픔')));
    await tester.pump();
    expect(_choice(tester, '모르겠어').isSelected, isFalse);
    expect(_choice(tester, '슬픔').isSelected, isTrue);
  });

  testWidgets('Reflection 성공 시 아동 활동 완료 안내 화면으로 이동한다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpEmotion(tester, repository: repository, sessionId: 42);
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.tap(find.byKey(const ValueKey('emotion-편안함')));
    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '우리 가족 소풍',
    );
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 1);
    expect(repository.lastReflection?.title, '우리 가족 소풍');
    expect(
      repository.lastReflection?.selectedEmotions,
      containsAll([DrawingEmotionType.happy, DrawingEmotionType.calm]),
    );
    expect(repository.lastReflection?.expressedEmotionText, isNull);
    expect(repository.lastReflection?.skipped, isFalse);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    expect(find.text('이제 보호자에게 기기를 건네주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
  });

  testWidgets('보호자 확인을 취소하면 아동 완료 안내 화면을 유지한다', (tester) async {
    await _pumpComplete(tester);

    await tester.tap(find.byKey(const ValueKey('guardian-handoff')));
    await tester.pumpAndSettle();
    expect(find.text('보호자 화면으로 이동할까요?'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    expect(find.text('보호자 화면으로 이동할까요?'), findsNothing);
  });

  testWidgets('보호자 확인 후 스택을 정리해 Guardian Home으로 이동한다', (tester) async {
    await _pumpComplete(tester);

    await tester.tap(find.byKey(const ValueKey('guardian-handoff')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('보호자 홈 테스트'), findsOneWidget);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('보호자 홈 테스트'), findsOneWidget);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsNothing);
  });

  testWidgets('식별자가 비어 있고 높이가 작아도 완료 안내 화면은 안전하다', (tester) async {
    await _pumpComplete(tester, childId: '', size: const Size(600, 420));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('activity-complete-scroll')),
      const Offset(0, -500),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('건너뛰기는 빈 감정과 null 직접 표현을 제출한다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpEmotion(tester, repository: repository, sessionId: 42);
    await tester.tap(find.byKey(const ValueKey('emotion-skip')));
    await tester.pumpAndSettle();

    expect(repository.lastReflection?.selectedEmotions, isEmpty);
    expect(repository.lastReflection?.expressedEmotionText, isNull);
    expect(repository.lastReflection?.skipped, isTrue);
  });

  testWidgets('Reflection 실패 시 감정과 제목을 유지해 재시도할 수 있다', (tester) async {
    final repository = _CompletionRepository(reflectionError: StateError('x'));
    await _pumpEmotion(tester, repository: repository, sessionId: 42);
    await tester.tap(find.byKey(const ValueKey('emotion-화남')));
    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '화난 그림',
    );
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(_choice(tester, '화남').isSelected, isTrue);
    expect(find.text('화난 그림'), findsOneWidget);
    expect(find.textContaining('고른 내용은 그대로'), findsOneWidget);
  });

  testWidgets('sessionId가 없으면 Reflection을 호출하지 않는다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpEmotion(tester, repository: repository, sessionId: null);
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 0);
    expect(find.textContaining('아직 마음을 저장할 수 없어요'), findsWidgets);
  });

  testWidgets('감정 화면은 tablet landscape와 작은 높이에서 overflow가 없다', (tester) async {
    await _pumpEmotion(tester, size: const Size(1200, 600));
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey('emotion-screen-scroll')),
      const Offset(0, -1000),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('emotion-submit')), findsOneWidget);

    await _pumpEmotion(tester, size: const Size(600, 500));
    await tester.drag(
      find.byKey(const ValueKey('emotion-screen-scroll')),
      const Offset(0, -1000),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('emotion-submit')), findsOneWidget);
  });
}

Future<void> _pumpDrawing(
  WidgetTester tester, {
  required DrawingRepository repository,
  int? sessionId = 42,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        AppRoutes.emotionSelect('3'): (_) =>
            const EmotionSelectScreen(childId: '3'),
      },
      home: DrawingScreen(
        childId: '3',
        sessionId: sessionId,
        drawingRepository: repository,
        completionSnapshotProvider: () async => _png,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byKey(const ValueKey('draft-start-new')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('draft-start-new')));
    await tester.pump();
  }
}

Future<void> _pumpEmotion(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  DrawingRepository? repository,
  int? sessionId,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        AppRoutes.activityComplete('3'): (_) =>
            const ActivityCompleteScreen(childId: '3'),
        AppRoutes.guardianHome: (_) => const Scaffold(body: Text('보호자 홈 테스트')),
      },
      home: EmotionSelectScreen(
        childId: '3',
        sessionId: sessionId,
        drawingRepository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpComplete(
  WidgetTester tester, {
  String childId = '3',
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        AppRoutes.guardianHome: (_) => const Scaffold(body: Text('보호자 홈 테스트')),
      },
      home: ActivityCompleteScreen(childId: childId),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _drawStroke(WidgetTester tester) async {
  final center = tester.getCenter(find.byKey(const ValueKey('drawing-canvas')));
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(const Offset(30, 20));
  await gesture.up();
  await tester.pump();
}

AppChoiceCard _choice(WidgetTester tester, String label) =>
    tester.widget<AppChoiceCard>(find.byKey(ValueKey('emotion-$label')));

const _png = BinaryUploadDto(
  bytes: [137, 80, 78, 71],
  fileName: 'final.png',
  mimeType: 'image/png',
);

const _completeResponse = DrawingStageCompleteResponseDto(
  drawingSessionId: 42,
  finalAssetId: 140,
  sessionStatus: 'IN_PROGRESS',
  currentStage: 'ANALYZING',
  analysis: DrawingStageAnalysisDto(
    analysisId: 700,
    analysisType: 'INTERMEDIATE',
    status: 'PENDING',
  ),
  nextAction: 'POLL_ANALYSIS',
);

final class _CompletionRepository implements DrawingRepository {
  _CompletionRepository({
    this.completer,
    this.completionError,
    this.reflectionError,
  });

  final Completer<DrawingStageCompleteResponseDto>? completer;
  Object? completionError;
  int completeCalls = 0;
  final List<String> completionKeys = [];
  final List<DrawingCompleteMetadataDto> completionMetadata = [];
  int reflectionCalls = 0;
  Object? reflectionError;
  SaveDrawingReflectionRequestDto? lastReflection;

  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) {
    completeCalls += 1;
    completionKeys.add(idempotencyKey);
    completionMetadata.add(metadata);
    if (completionError case final error?) return Future.error(error);
    return completer?.future ?? Future.value(_completeResponse);
  }

  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    reflectionCalls += 1;
    lastReflection = request;
    if (reflectionError case final error?) throw error;
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async => null;
  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState,
  ) => throw UnimplementedError();
  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<void> deleteDraft(int sessionId) => throw UnimplementedError();
  @override
  Future<DrawingSessionDto> getSession(int sessionId) =>
      throw UnimplementedError();
  @override
  Future<DrawingTypePage> getDrawingTypes({int? childId, String? ageGroup}) =>
      throw UnimplementedError();
  @override
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  }) => throw UnimplementedError();
}

final class _RecordingInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (options.path.endsWith('/draft') && options.method == 'PUT') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const {
            'drawingAssetId': 140,
            'assetVersion': 4,
            'lastEventSequence': 17,
            'savedAt': '2026-07-22T10:00:01Z',
            'expiresAt': '2026-07-29T10:00:01Z',
          },
        ),
      );
      return;
    }
    if (options.path.endsWith('/drawing-complete')) {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const {
            'drawingSessionId': 42,
            'finalAssetId': 140,
            'sessionStatus': 'IN_PROGRESS',
            'currentStage': 'ANALYZING',
            'analysis': {
              'analysisId': 700,
              'analysisType': 'INTERMEDIATE',
              'status': 'PENDING',
            },
            'nextAction': 'POLL_ANALYSIS',
          },
        ),
      );
      return;
    }
    if (options.path.endsWith('/analyses')) {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 201,
          data: const {
            'data': {
              'drawingAnalysisId': 700,
              'drawingSessionId': 42,
              'drawingAssetId': 140,
              'requestId': '550e8400-e29b-41d4-a716-446655440000',
              'analysisType': 'OBJECT_DETECTION',
              'status': 'SUCCEEDED',
              'model': {'name': 'dodam-detector', 'version': '1.0'},
              'detections': [],
              'requestedAt': '2026-07-22T10:00:01Z',
              'processedAt': '2026-07-22T10:00:02Z',
            },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<void>(requestOptions: options, statusCode: 200));
  }
}
