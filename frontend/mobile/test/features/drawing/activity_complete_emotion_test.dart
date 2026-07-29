import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_error.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_activity_completion_controller.dart';
import 'package:dodam/features/drawing/application/drawing_event_journal.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
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
    expect(form.fields, isEmpty);
    expect(
      form.files.map((part) => part.key),
      containsAll(['preview', 'canvasState']),
    );
    final canvasState = form.files.singleWhere(
      (part) => part.key == 'canvasState',
    );
    expect(canvasState.value.contentType?.toString(), 'application/json');
    expect(jsonDecode(utf8.decode(await _multipartBytes(canvasState.value))), {
      'lastEventSequence': 17,
      'clientSavedAt': '2026-07-22T10:00:00Z',
    });
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
      'triggerReason': 'USER_REQUEST',
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

      final response = await repository.completeDrawingStage(
        42,
        finalImage: _png,
        metadata: const DrawingCompleteMetadataDto(
          lastEventSequence: 17,
          drawingDurationMs: 1000,
          clientCompletedAt: '2026-07-22T19:00:00+09:00',
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
      expect(form.fields, isEmpty);
      final finalImage = form.files.singleWhere(
        (part) => part.key == 'finalImage',
      );
      expect(finalImage.value.filename, 'drawing.png');
      expect(finalImage.value.contentType?.toString(), 'image/png');
      expect(await _multipartBytes(finalImage.value), _png.bytes);
      final metadata = form.files.singleWhere((part) => part.key == 'metadata');
      expect(metadata.value.filename, 'metadata.json');
      expect(metadata.value.contentType?.toString(), 'application/json');
      expect(jsonDecode(utf8.decode(await _multipartBytes(metadata.value))), {
        'lastEventSequence': 17,
        'drawingDurationMs': 1000,
        'clientCompletedAt': '2026-07-22T19:00:00+09:00',
      });
      expect(recorder.requests, hasLength(1));
      expect(
        recorder.requests.where(
          (request) => request.uri.path.endsWith('/analyses'),
        ),
        isEmpty,
      );
      expect(response.currentStage, 'CONVERSING');
      expect(response.nextAction, 'SELECT_EMOTION');

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

  test('Drawing Complete metadata는 선택적 sourceAssetId를 보존한다', () {
    expect(
      const DrawingCompleteMetadataDto(
        sourceAssetId: 88,
        lastEventSequence: 17,
        drawingDurationMs: 1000,
        clientCompletedAt: '2026-07-22T19:00:00+09:00',
      ).toJson(),
      {
        'sourceAssetId': 88,
        'lastEventSequence': 17,
        'drawingDurationMs': 1000,
        'clientCompletedAt': '2026-07-22T19:00:00+09:00',
      },
    );
  });

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
    final logs = await _captureDebugPrint(() async {
      await _pumpDrawing(tester, repository: const MockDrawingRepository());
      await _drawStroke(tester);

      await tester.tap(find.byKey(const ValueKey('drawing-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 그렸어요'));
      await tester.pumpAndSettle();
    });

    expect(find.text('내 마음 고르기'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
    expect(
      logs,
      contains(
        '[DRAWING_COMPLETE] success '
        'currentStage=CONVERSING nextAction=SELECT_EMOTION',
      ),
    );
  });

  testWidgets('생성된 대화를 종료하기 전에는 감정 선택 화면으로 이동하지 않는다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpDrawing(
      tester,
      repository: repository,
      conversationId: 99,
      conversationRepository: const MockConversationRepository(
        delay: Duration.zero,
      ),
    );
    await _drawStroke(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('drawing-complete')));
    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(repository.completeCalls, 0);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.text('대화를 먼저 마친 뒤 그림 활동을 완료해 주세요.'), findsOneWidget);
  });

  testWidgets('그림 단계 완료 후 대화를 열고 회고로 바로 넘어가지 않는다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpDrawing(
      tester,
      repository: repository,
      conversationRepository: const MockConversationRepository(
        delay: Duration.zero,
      ),
    );
    await _drawStroke(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('drawing-complete')));
    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    // 대화가 열리면 질문 노출 타이머가 계속 돌아 pumpAndSettle이 끝나지 않는다.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(repository.completeCalls, 1);
    // 대화 단계에 머무르므로 회고 화면으로 넘어가지 않는다.
    expect(find.text('내 마음 고르기'), findsNothing);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    // 그림 단계는 끝났으므로 완료 요청이 다시 나가지 않는다.
    await tester.tap(
      find.byKey(const ValueKey('drawing-complete')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repository.completeCalls, 1);
  });

  testWidgets('0ms 완료도 Backend 최소 duration인 1ms를 전송한다', (tester) async {
    final repository = _CompletionRepository();
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      journal: DrawingEventJournal(sessionClock: Stopwatch()),
    );
    await _pumpDrawing(
      tester,
      repository: repository,
      syncCoordinator: coordinator,
    );
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(repository.completionMetadata.single.drawingDurationMs, 1);
    coordinator.dispose();
  });

  testWidgets('양수 경과 시간은 Drawing Complete metadata에 그대로 유지한다', (tester) async {
    final clock = Stopwatch()..start();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    clock.stop();
    final elapsedMilliseconds = clock.elapsedMilliseconds;
    expect(elapsedMilliseconds, greaterThan(1));
    final repository = _CompletionRepository();
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      journal: DrawingEventJournal(sessionClock: clock),
    );
    await _pumpDrawing(
      tester,
      repository: repository,
      syncCoordinator: coordinator,
    );
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(
      repository.completionMetadata.single.drawingDurationMs,
      elapsedMilliseconds,
    );
    coordinator.dispose();
  });

  testWidgets('완료 응답 stage가 다르면 Canvas를 유지하고 이동하지 않는다', (tester) async {
    final repository = _CompletionRepository(
      completionResponse: _unexpectedStageResponse,
    );
    final logs = await _captureDebugPrint(() async {
      await _pumpDrawing(tester, repository: repository);
      await _drawStroke(tester);

      await tester.tap(find.byKey(const ValueKey('drawing-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 그렸어요'));
      await tester.pumpAndSettle();
    });

    expect(repository.completeCalls, 1);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.textContaining('그림은 그대로'), findsOneWidget);
    expect(find.text('내 마음 고르기'), findsNothing);
    expect(
      logs.singleWhere((line) => line.contains('contract_mismatch')),
      allOf(
        contains('currentStage=ANALYZING'),
        contains('nextAction=SELECT_EMOTION'),
        contains('exceptionType=StateError'),
      ),
    );
  });

  // 명세 §10.8은 nextAction으로 감정 선택을 가리키지만 정본 활동 흐름 §23.1은 대화
  // 뒤에 회고를 둔다. 그래서 다음 화면은 nextAction이 아니라 currentStage로 정한다.
  testWidgets('완료 응답 nextAction이 달라도 stage가 CONVERSING이면 다음 단계로 넘어간다', (
    tester,
  ) async {
    final repository = _CompletionRepository(
      completionResponse: _unexpectedNextActionResponse,
    );
    final logs = await _captureDebugPrint(() async {
      await _pumpDrawing(tester, repository: repository);
      await _drawStroke(tester);

      await tester.tap(find.byKey(const ValueKey('drawing-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 그렸어요'));
      await tester.pumpAndSettle();
    });

    expect(repository.completeCalls, 1);
    expect(find.textContaining('그림은 그대로'), findsNothing);
    // 대화 저장소가 없는 구성이므로 대화를 열지 못하고 회고 화면으로 넘어간다.
    expect(find.text('내 마음 고르기'), findsOneWidget);
    expect(
      logs,
      contains(
        '[DRAWING_COMPLETE] success currentStage=CONVERSING '
        'nextAction=POLL_ANALYSIS',
      ),
    );
  });

  testWidgets('완료 실패 시 Canvas와 Stroke를 유지하고 이동하지 않는다', (tester) async {
    final logs = await _captureDebugPrint(() async {
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
    });

    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.textContaining('그림은 그대로'), findsOneWidget);
    expect(find.text('내 마음 고르기'), findsNothing);
    expect(
      logs.singleWhere((line) => line.contains('request_transport_failure')),
      allOf(
        contains('transportType=connection'),
        contains('exceptionType=ApiTransportFailure'),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Canvas PNG가 null이면 캡처 실패를 구분하고 완료 예외를 삼킨다', (tester) async {
    final logs = await _captureDebugPrint(() async {
      await _pumpDrawing(
        tester,
        repository: const MockDrawingRepository(),
        completionSnapshotProvider: () async => null,
      );
      await _drawStroke(tester);

      await tester.tap(find.byKey(const ValueKey('drawing-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 그렸어요'));
      await tester.pumpAndSettle();
    });

    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.textContaining('그림은 그대로'), findsOneWidget);
    expect(
      logs.singleWhere((line) => line.contains('canvas_capture_failure')),
      allOf(contains('kind=null'), contains('exceptionType=StateError')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('HTTP 실패는 status와 Backend 오류 계약만 안전하게 기록한다', (tester) async {
    final repository = _CompletionRepository(
      completionError: const ApiResponseFailure(
        statusCode: 409,
        error: ApiError(
          code: 'DRAWING_409_001',
          message: '현재 단계에서는 그림을 완료할 수 없습니다.',
        ),
      ),
    );
    final logs = await _captureDebugPrint(() async {
      await _pumpDrawing(tester, repository: repository);
      await _drawStroke(tester);

      await tester.tap(find.byKey(const ValueKey('drawing-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 그렸어요'));
      await tester.pumpAndSettle();
    });

    expect(
      logs.singleWhere((line) => line.contains('http_failure')),
      allOf(
        contains('status=409'),
        contains('code=DRAWING_409_001'),
        contains('message=현재 단계에서는 그림을 완료할 수 없습니다.'),
        contains('exceptionType=ApiResponseFailure'),
      ),
    );
    expect(find.textContaining('그림은 그대로'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('성공 응답 DTO 파싱 예외는 요청 전송 실패와 구분한다', (tester) async {
    final repository = _CompletionRepository(
      completionError: const FormatException('invalid response fixture'),
    );
    final logs = await _captureDebugPrint(() async {
      await _pumpDrawing(tester, repository: repository);
      await _drawStroke(tester);

      await tester.tap(find.byKey(const ValueKey('drawing-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 그렸어요'));
      await tester.pumpAndSettle();
    });

    expect(
      logs.singleWhere((line) => line.contains('response_parse_failure')),
      contains('exceptionType=FormatException'),
    );
    expect(find.textContaining('그림은 그대로'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(
      repository.completionMetadata[1].drawingDurationMs,
      repository.completionMetadata[0].drawingDurationMs,
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
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      conversationSkipped: false,
    );
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
    expect(repository.activityCompletionCalls, 1);
    expect(repository.lastActivityRequest?.conversationSkipped, isFalse);
    expect(repository.lastActivityRequest?.requestReport, isTrue);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    expect(find.text('이제 보호자에게 기기를 건네주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
  });

  testWidgets('다 했어요는 상세 조회 후 End, Reflection, Complete를 순서대로 호출한다', (
    tester,
  ) async {
    final calls = <String>[];
    final repository = _CompletionRepository(
      calls: calls,
      existingConversationId: 20,
    );
    final conversationEndRepository = _CompletionConversationEndRepository(
      calls,
    );
    final keys = ['conversation-key', 'activity-key'].iterator;
    final controller = DrawingActivityCompletionController(
      drawingRepository: repository,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: conversationEndRepository,
      idempotencyKeyProvider: () {
        keys.moveNext();
        return keys.current;
      },
    );
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      activityCompletionController: controller,
    );

    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(calls.take(4), ['detail', 'end', 'reflection', 'complete']);
    expect(conversationEndRepository.conversationId, 20);
    expect(repository.lastActivityRequest?.conversationSkipped, isFalse);
    expect(repository.lastActivityRequest?.requestReport, isTrue);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
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

  testWidgets('REPORTING 상태는 COMPLETED가 될 때까지 조회한 뒤 완료를 안내한다', (tester) async {
    final repository = _CompletionRepository(
      sessionStatuses: ['IN_PROGRESS', 'COMPLETED'],
    );

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
    );

    expect(repository.sessionStatusCalls, 2);
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity-completion-progress')),
      findsNothing,
    );
  });

  testWidgets('REPORTING 다음 FAILED이면 완료 실패 UI를 표시한다', (tester) async {
    final repository = _CompletionRepository(
      sessionStatuses: ['IN_PROGRESS', 'FAILED'],
    );

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
    );

    expect(repository.sessionStatusCalls, 2);
    expect(find.text('활동을 마무리하지 못했어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-handoff')), findsNothing);
  });

  testWidgets('상태 조회 네트워크 실패 후 완료 화면에서 수동 재확인한다', (tester) async {
    final repository = _CompletionRepository(
      sessionFailures: [StateError('network')],
    );

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
    );
    expect(
      find.byKey(const ValueKey('activity-completion-retry')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('activity-completion-retry')));
    await tester.pumpAndSettle();

    expect(repository.sessionStatusCalls, 2);
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
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

  testWidgets('Reflection 전송 후 입력을 잠그고 중복 탭 없이 완료 화면으로 한 번 이동한다', (
    tester,
  ) async {
    final reflectionCompleter = Completer<void>();
    final repository = _CompletionRepository(
      reflectionCompleter: reflectionCompleter,
    );
    final controller = DrawingActivityCompletionController(
      drawingRepository: repository,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
    );
    final observer = _CompletionNavigationObserver();
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      activityCompletionController: controller,
      navigatorObserver: observer,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '잠근 제목',
    );

    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pump();

    expect(repository.reflectionCalls, 1);
    expect(
      tester
          .widget<AppTextField>(find.byKey(const ValueKey('drawing-title')))
          .enabled,
      isFalse,
    );
    expect(_choice(tester, '기쁨').onTap, isNull);
    expect(
      find.byKey(const ValueKey('reflection-input-locked-message')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('emotion-submit')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repository.reflectionCalls, 1);

    reflectionCompleter.complete();
    await tester.pumpAndSettle();

    expect(repository.activityCompleteCalls, 1);
    expect(observer.activityCompleteReplacements, 1);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
  });

  testWidgets('HTTP 202 직후 완료 상태 화면으로 이동하고 그 화면에서만 조회한다', (tester) async {
    final sessionCompleter = Completer<DrawingSessionDto>();
    final repository = _CompletionRepository(
      sessionCompleter: sessionCompleter,
    );
    final observer = _CompletionNavigationObserver();
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      navigatorObserver: observer,
      conversationSkipped: false,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    for (var pump = 0; pump < 5; pump += 1) {
      await tester.pump();
    }

    expect(repository.activityCompleteCalls, 1);
    expect(observer.activityCompleteReplacements, 1);
    expect(
      find.byKey(const ValueKey('activity-completion-progress')),
      findsOneWidget,
    );
    expect(repository.sessionStatusCalls, 1);

    sessionCompleter.complete(_sessionDto(sessionId: 42, status: 'COMPLETED'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
  });

  testWidgets('완료 화면 dispose 후 진행 중 조회가 끝나도 추가 GET이 없다', (tester) async {
    final sessionCompleter = Completer<DrawingSessionDto>();
    final repository = _CompletionRepository(
      sessionCompleter: sessionCompleter,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityCompleteScreen(
          childId: '3',
          sessionId: 42,
          drawingRepository: repository,
          pollInterval: Duration.zero,
        ),
      ),
    );
    await tester.pump();
    expect(repository.sessionStatusCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    sessionCompleter.complete(
      _sessionDto(sessionId: 42, status: 'IN_PROGRESS'),
    );
    await tester.pumpAndSettle();

    expect(repository.sessionStatusCalls, 1);
    expect(tester.takeException(), isNull);
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
  DrawingSyncCoordinator? syncCoordinator,
  int? conversationId,
  ConversationRepository? conversationRepository,
  Future<BinaryUploadDto?> Function()? completionSnapshotProvider,
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
        syncCoordinator: syncCoordinator,
        conversationId: conversationId,
        conversationRepository: conversationRepository,
        completionSnapshotProvider:
            completionSnapshotProvider ?? () async => _png,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byKey(const ValueKey('draft-start-new')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('draft-start-new')));
    await tester.pump();
  }
}

Future<List<String>> _captureDebugPrint(Future<void> Function() action) async {
  final logs = <String>[];
  final originalDebugPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
  }
  return logs;
}

Future<void> _pumpEmotion(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  DrawingRepository? repository,
  int? sessionId,
  DrawingActivityCompletionController? activityCompletionController,
  NavigatorObserver? navigatorObserver,
  bool conversationSkipped = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [?navigatorObserver],
      routes: {
        AppRoutes.guardianHome: (_) => const Scaffold(body: Text('보호자 홈 테스트')),
      },
      onGenerateRoute: (settings) {
        if (settings.name != AppRoutes.activityComplete('3')) return null;
        final arguments = settings.arguments! as ActivityCompleteRouteArguments;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ActivityCompleteScreen(
            childId: '3',
            sessionId: arguments.sessionId,
            drawingRepository: arguments.repository,
            pollInterval: Duration.zero,
          ),
        );
      },
      home: EmotionSelectScreen(
        childId: '3',
        sessionId: sessionId,
        drawingRepository: repository,
        conversationId: conversationSkipped ? null : 20,
        conversationAlreadyEnded: !conversationSkipped,
        activityCompletionController: activityCompletionController,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpComplete(
  WidgetTester tester, {
  String childId = '3',
  Size size = const Size(1200, 800),
  DrawingRepository? repository,
  int? sessionId,
  Duration pollInterval = const Duration(seconds: 2),
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
      home: ActivityCompleteScreen(
        childId: childId,
        sessionId: sessionId,
        drawingRepository: repository,
        pollInterval: pollInterval,
      ),
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

Future<List<int>> _multipartBytes(MultipartFile file) => file
    .finalize()
    .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));

const _completeResponse = DrawingStageCompleteResponseDto(
  drawingSessionId: 42,
  finalAssetId: 140,
  sessionStatus: 'IN_PROGRESS',
  currentStage: 'CONVERSING',
  analysis: DrawingStageAnalysisDto(
    analysisId: 700,
    analysisType: 'OBJECT_DETECTION',
    status: 'SUCCEEDED',
  ),
  nextAction: 'SELECT_EMOTION',
);

const _unexpectedStageResponse = DrawingStageCompleteResponseDto(
  drawingSessionId: 42,
  finalAssetId: 140,
  sessionStatus: 'IN_PROGRESS',
  currentStage: 'ANALYZING',
  analysis: DrawingStageAnalysisDto(
    analysisId: 700,
    analysisType: 'OBJECT_DETECTION',
    status: 'SUCCEEDED',
  ),
  nextAction: 'SELECT_EMOTION',
);

const _unexpectedNextActionResponse = DrawingStageCompleteResponseDto(
  drawingSessionId: 42,
  finalAssetId: 140,
  sessionStatus: 'IN_PROGRESS',
  currentStage: 'CONVERSING',
  analysis: DrawingStageAnalysisDto(
    analysisId: 700,
    analysisType: 'OBJECT_DETECTION',
    status: 'SUCCEEDED',
  ),
  nextAction: 'POLL_ANALYSIS',
);

final class _CompletionRepository implements DrawingRepository {
  _CompletionRepository({
    this.completer,
    this.completionError,
    this.completionResponse = _completeResponse,
    this.reflectionError,
    this.reflectionCompleter,
    List<String> sessionStatuses = const ['COMPLETED'],
    List<Object> sessionFailures = const [],
    this.sessionCompleter,
    this.calls,
    this.existingConversationId,
  }) : _sessionStatuses = List.of(sessionStatuses),
       _sessionFailures = List.of(sessionFailures);

  final Completer<DrawingStageCompleteResponseDto>? completer;
  final DrawingStageCompleteResponseDto completionResponse;
  Object? completionError;
  int completeCalls = 0;
  final List<String> completionKeys = [];
  final List<DrawingCompleteMetadataDto> completionMetadata = [];
  int reflectionCalls = 0;
  int activityCompleteCalls = 0;
  Object? reflectionError;
  final Completer<void>? reflectionCompleter;
  final Completer<DrawingSessionDto>? sessionCompleter;
  final List<String>? calls;
  final int? existingConversationId;
  SaveDrawingReflectionRequestDto? lastReflection;
  int activityCompletionCalls = 0;
  CompleteActivityRequestDto? lastActivityRequest;
  final List<String> _sessionStatuses;
  final List<Object> _sessionFailures;
  int sessionStatusCalls = 0;

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
    return completer?.future ?? Future.value(completionResponse);
  }

  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    calls?.add('reflection');
    reflectionCalls += 1;
    lastReflection = request;
    if (reflectionError case final error?) throw error;
    if (reflectionCompleter case final completer?) await completer.future;
  }

  @override
  Future<DrawingCompletionResponseDto> completeActivity(
    int sessionId, {
    required CompleteActivityRequestDto request,
    required String idempotencyKey,
  }) async {
    calls?.add('complete');
    activityCompleteCalls += 1;
    activityCompletionCalls += 1;
    lastActivityRequest = request;
    return DrawingCompletionResponseDto(
      drawingSessionId: sessionId,
      sessionStatus: 'IN_PROGRESS',
      currentStage: 'REPORTING',
      analysisId: 801,
      analysisStatus: 'PENDING',
      reportId: 901,
      reportStatus: 'GENERATING',
    );
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async => null;
  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;
  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) =>
      throw UnimplementedError();
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
  Future<DrawingSessionDto> getSession(int sessionId) async {
    calls?.add('detail');
    sessionStatusCalls += 1;
    if (_sessionFailures.isNotEmpty) throw _sessionFailures.removeAt(0);
    if (sessionCompleter case final completer?) return completer.future;
    if (sessionStatusCalls == 1 && existingConversationId != null) {
      return _sessionDto(
        sessionId: sessionId,
        status: 'IN_PROGRESS',
        currentStage: 'CONVERSING',
        conversationId: existingConversationId,
      );
    }
    final status = _sessionStatuses.length > 1
        ? _sessionStatuses.removeAt(0)
        : _sessionStatuses.single;
    return _sessionDto(sessionId: sessionId, status: status);
  }

  @override
  Future<DrawingTypePage> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) => throw UnimplementedError();
  @override
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

DrawingSessionDto _sessionDto({
  required int sessionId,
  required String status,
  String? currentStage,
  int? conversationId,
}) => DrawingSessionDto.fromDetailJson({
  'drawingSessionId': sessionId,
  'child': {'childId': 3, 'nickname': '도담'},
  'drawingType': {'drawingTypeId': 1, 'code': 'HTP', 'name': '집-나무-사람'},
  'inputMethod': 'TOUCH',
  'title': null,
  'sessionStatus': status,
  'currentStage':
      currentStage ?? (status == 'COMPLETED' ? 'COMPLETED' : 'REPORTING'),
  'selectedEmotions': const <String>[],
  'expressedEmotionText': null,
  'startedAt': '2026-07-26T10:00:00Z',
  'completedAt': status == 'COMPLETED' ? '2026-07-26T10:10:00Z' : null,
  'conversation': null,
  'conversationId': conversationId,
  'latestAnalysis': null,
  'assets': const <Map<String, dynamic>>[],
});

final class _CompletionConversationEndRepository
    implements ConversationEndRepository {
  _CompletionConversationEndRepository(this.calls);

  final List<String> calls;
  int? conversationId;

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    calls.add('end');
    this.conversationId = conversationId;
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: request.reason.apiValue,
      completedAt: '2026-07-28T10:00:00+09:00',
      nextStage: 'REFLECTION',
    );
  }
}

final class _CompletionNavigationObserver extends NavigatorObserver {
  int activityCompleteReplacements = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute?.settings.name == AppRoutes.activityComplete('3')) {
      activityCompleteReplacements += 1;
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
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
            'success': true,
            'code': 'COMMON_200',
            'message': '요청에 성공했습니다.',
            'data': {
              'drawingAssetId': 140,
              'assetVersion': 4,
              'lastEventSequence': 17,
              'savedAt': '2026-07-22T10:00:01Z',
              'expiresAt': '2026-07-29T10:00:01Z',
            },
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
            'success': true,
            'code': 'COMMON_200',
            'message': '요청에 성공했습니다.',
            'data': {
              'drawingSessionId': 42,
              'finalAssetId': 140,
              'sessionStatus': 'IN_PROGRESS',
              'currentStage': 'CONVERSING',
              'analysis': {
                'analysisId': 700,
                'analysisType': 'OBJECT_DETECTION',
                'status': 'SUCCEEDED',
              },
              'nextAction': 'SELECT_EMOTION',
            },
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
