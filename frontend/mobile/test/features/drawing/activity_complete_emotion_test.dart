import 'dart:async';
import 'dart:convert';

import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/core/network/api_client.dart';
import 'package:dodam/core/network/api_error.dart';
import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/activity/presentation/widgets/emotion_selection_widgets.dart';
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
import 'package:flutter/services.dart';
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
      idempotencyKey: 'draft-save-key-0001',
    );

    final request = recorder.requests.single;
    expect(request.method, 'PUT');
    expect(request.uri.path, '/api/v1/drawing-sessions/42/draft');
    expect(request.headers['Idempotency-Key'], 'draft-save-key-0001');
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
    expect(find.text('조금 더 그릴래요'), findsOneWidget);
    expect(find.text('다 그렸어요'), findsOneWidget);
    final thinkingIllustration = tester.widget<Image>(
      find.byKey(const ValueKey('drawing-complete-thinking-illustration')),
    );
    expect(
      (thinkingIllustration.image as AssetImage).assetName,
      DodamDialogAssets.completeThinking,
    );
    expect(thinkingIllustration.fit, BoxFit.contain);
    expect(thinkingIllustration.excludeFromSemantics, isTrue);
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

  testWidgets('일반 그림은 drawing-complete에 보낸 최종 합성 PNG를 preview로 재사용한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _CompletionRepository();
    EmotionSelectRouteArguments? routeArguments;
    await _pumpDrawing(
      tester,
      repository: repository,
      onEmotionRouteArguments: (arguments) => routeArguments = arguments,
    );
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(repository.lastFinalImage, same(_png));
    expect(
      routeArguments?.completedDrawingImage,
      same(repository.lastFinalImage),
    );
    expect(find.bySemanticsLabel('내가 완성한 그림'), findsOneWidget);
    final preview = tester.widget<Image>(
      find.byKey(const ValueKey('emotion-drawing-preview-image')),
    );
    expect(preview.fit, BoxFit.contain);
    expect((preview.image as MemoryImage).bytes, _png.bytes);
    semantics.dispose();
  });

  testWidgets('대화를 먼저 종료한 그림은 완료 후 감정 선택 화면으로 이동한다', (tester) async {
    final repository = _CompletionRepository(
      completionResponse: _reflectionCompleteResponse,
    );

    await _pumpDrawing(tester, repository: repository);
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(repository.completeCalls, 1);
    expect(find.text('그림을 그리고 나니, 지금 마음은 어때?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emotion-confirmation-panel')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
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

  testWidgets('완료 API보다 pending stroke batch를 먼저 전송한다', (tester) async {
    final calls = <String>[];
    final repository = _CompletionRepository(calls: calls);
    await _pumpDrawing(tester, repository: repository);
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(calls.take(2), ['stroke', 'drawing-complete']);
    expect(repository.strokeCalls, 1);
    expect(repository.completeCalls, 1);
  });

  testWidgets('stroke batch 실패 시 완료 API를 호출하지 않고 Canvas를 유지한다', (tester) async {
    final repository = _CompletionRepository(
      strokeError: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    await _pumpDrawing(tester, repository: repository);
    await _drawStroke(tester);

    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    await tester.pumpAndSettle();

    expect(repository.strokeCalls, 1);
    expect(repository.completeCalls, 0);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.textContaining('그림은 그대로'), findsOneWidget);
  });

  for (final lifecycleState in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('완료 시작 뒤 ${lifecycleState.name}가 와도 Draft PUT을 시작하지 않는다', (
      tester,
    ) async {
      final completion = Completer<DrawingStageCompleteResponseDto>();
      final repository = _CompletionRepository(completer: completion);
      await _pumpDrawing(tester, repository: repository);
      await _drawStroke(tester);

      await tester.tap(find.byKey(const ValueKey('drawing-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 그렸어요'));
      await tester.pump();
      expect(repository.completeCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(lifecycleState);
      await tester.pump();

      expect(repository.draftCalls, 0);
      completion.complete(_completeResponse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.completeCalls, 1);
    });
  }

  testWidgets('완료 시작 전 in-flight Draft를 기다린 뒤 complete를 한 번 호출한다', (
    tester,
  ) async {
    final draft = Completer<DraftSaveResponseDto>();
    final repository = _CompletionRepository(draftCompleter: draft);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    await _pumpDrawing(
      tester,
      repository: repository,
      syncCoordinator: coordinator,
    );
    await _drawStroke(tester);
    coordinator.start(snapshotProvider: () async => _png);
    final saving = coordinator.saveDraftNow();
    await _pumpUntil(tester, () => repository.draftCalls == 1);

    // 저장 중에는 툴바가 진행 표시를 계속 돌리므로 pumpAndSettle 은 끝나지
    // 않는다(S15P11B209-805). 확인 창이 뜰 때까지만 돌린다.
    await tester.tap(find.byKey(const ValueKey('drawing-complete')));
    await _pumpUntil(tester, () => find.text('다 그렸어요').evaluate().isNotEmpty);
    await tester.tap(find.text('다 그렸어요'));
    await tester.pump();

    expect(repository.completeCalls, 0);
    draft.complete(_draftSaveResponse);
    await saving;
    await _pumpUntil(tester, () => repository.completeCalls == 1);

    expect(repository.draftCalls, 1);
    expect(repository.completeCalls, 1);
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

  testWidgets('감정 5개를 표시하고 대표 감정 하나만 선택한다', (tester) async {
    await _pumpEmotion(tester);

    expect(find.text('그림을 그리고 나니, 지금 마음은 어때?'), findsOneWidget);
    expect(find.text('지금 마음과 가장 비슷한 표정을 하나 골라줘.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emotion-confirmation-panel')),
      findsNothing,
    );
    for (final label in ['불안', '화남', '슬픔', '편안', '기쁨']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('모르겠어'), findsNothing);
    expect(find.text('다시 고를래'), findsNothing);
    expect(find.byKey(const ValueKey('emotion-skip')), findsOneWidget);
    final defaultBackground = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('emotion-background')),
    );
    expect(
      (defaultBackground.decoration! as BoxDecoration).color,
      AppColors.childCanvas,
    );

    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();
    expect(_choice(tester, '기쁨').isSelected, isTrue);
    expect(_choice(tester, '슬픔').isDimmed, isTrue);
    expect(find.byKey(const ValueKey('emotion-check-HAPPY')), findsOneWidget);
    expect(find.text('기쁜 마음을 골랐구나.'), findsOneWidget);
    expect(find.text('이 마음이 지금 마음과 가장 비슷해?'), findsOneWidget);
    expect(find.text('응! 맞아!'), findsOneWidget);
    final selectedBackground = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('emotion-background')),
    );
    expect(
      (selectedBackground.decoration! as BoxDecoration).color,
      emotionPresentationOf(DrawingEmotionType.happy).canvasBackground,
    );

    await tester.tap(find.byKey(const ValueKey('emotion-편안')));
    await tester.pumpAndSettle();

    expect(_choice(tester, '기쁨').isSelected, isFalse);
    expect(_choice(tester, '편안').isSelected, isTrue);
    expect(_choice(tester, '슬픔').isSelected, isFalse);
  });

  testWidgets('완료 이미지를 전달할 수 없는 예외 진입은 안전한 안내를 표시한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpEmotion(tester, completedDrawingImage: null);

    expect(find.bySemanticsLabel('내가 완성한 그림'), findsOneWidget);
    expect(find.text('완성한 그림을 불러오지 못했어요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emotion-drawing-preview-image')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('선택적 제목은 감정 선택 후에도 유지된다', (tester) async {
    await _pumpEmotion(tester);

    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '우리 가족 소풍',
    );
    await tester.tap(find.byKey(const ValueKey('emotion-편안')));
    await tester.pumpAndSettle();

    expect(find.text('우리 가족 소풍'), findsOneWidget);
    expect(_choice(tester, '편안').isSelected, isTrue);
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

  testWidgets('대표 감정 5개의 enum·asset 매핑을 로드하고 contain으로 표시한다', (tester) async {
    await _pumpEmotion(tester);

    expect(
      emotionChoicePresentations
          .map(
            (presentation) =>
                (presentation.emotion.apiValue, presentation.label),
          )
          .toList(),
      [
        ('HAPPY', '기쁨'),
        ('CALM', '편안'),
        ('SAD', '슬픔'),
        ('SCARED', '불안'),
        ('ANGRY', '화남'),
      ],
    );
    for (final presentation in emotionChoicePresentations) {
      final asset = await rootBundle.load(presentation.assetPath);
      expect(
        asset.lengthInBytes,
        greaterThan(0),
        reason: presentation.assetPath,
      );
      final image = tester.widget<Image>(
        find.byKey(ValueKey('emotion-image-${presentation.emotion.apiValue}')),
      );
      expect(image.fit, BoxFit.contain);
      expect(image.excludeFromSemantics, isTrue);
    }
  });

  testWidgets('감정 카드는 button·selected semantics와 48px 이상 터치 영역을 제공한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpEmotion(tester);

    final unselected = find.bySemanticsLabel('기쁨 감정 선택');
    expect(unselected, findsOneWidget);
    expect(
      tester.getSemantics(unselected),
      matchesSemantics(
        label: '기쁨 감정 선택',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    final cardSize = tester.getSize(find.byKey(const ValueKey('emotion-기쁨')));
    expect(cardSize.width, greaterThanOrEqualTo(48));
    expect(cardSize.height, greaterThanOrEqualTo(48));

    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();
    final selected = find.bySemanticsLabel('기쁨, 선택됨');
    expect(selected, findsOneWidget);
    expect(
      tester.getSemantics(selected),
      matchesSemantics(
        label: '기쁨, 선택됨',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      find.bySemanticsLabel('기쁜 마음을 골랐구나. 이 마음이 지금 마음과 가장 비슷해?'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('skip은 48dp button semantics와 아동 친화적 확인·focus 복원을 제공한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _CompletionRepository();
    await _pumpEmotion(tester, repository: repository, sessionId: 42);

    final skip = find.bySemanticsLabel('지금은 고르지 않을래');
    expect(skip, findsOneWidget);
    expect(
      tester.getSemantics(skip),
      matchesSemantics(
        label: '지금은 고르지 않을래',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    final skipSize = tester.getSize(find.byKey(const ValueKey('emotion-skip')));
    expect(skipSize.width, greaterThanOrEqualTo(48));
    expect(skipSize.height, greaterThanOrEqualTo(48));

    await _openSkipDialog(tester);
    expect(repository.reflectionCalls, 0);
    expect(find.text('지금은 마음을 고르지 않고 넘어갈까?'), findsOneWidget);
    expect(find.text('나중에 그림을 보면서 다시 이야기해도 괜찮아.'), findsOneWidget);
    expect(find.text('응, 넘어갈래'), findsOneWidget);
    expect(find.text('다시 생각해볼래'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('emotion-skip-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('emotion-skip-dialog')), findsNothing);
    expect(repository.reflectionCalls, 0);
    expect(
      tester
          .widget<EmotionSkipButton>(find.byKey(const ValueKey('emotion-skip')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('skip 로딩은 disabled button과 live-region semantics를 제공한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EmotionSkipButton(onPressed: () {}, isLoading: true),
          ),
        ),
      ),
    );

    expect(find.text('넘어갈 준비를 하고 있어요'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('emotion-skip-loading-semantics')),
      ),
      matchesSemantics(
        label: '넘어갈 준비를 하고 있어요',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        isLiveRegion: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('감정 선택 후 skip을 취소하면 대표 감정과 확인 패널을 유지한다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpEmotion(tester, repository: repository, sessionId: 42);
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();

    await _openSkipDialog(tester);
    expect(_choice(tester, '기쁨').isSelected, isTrue);
    expect(repository.reflectionCalls, 0);
    await tester.tap(find.byKey(const ValueKey('emotion-skip-cancel')));
    await tester.pumpAndSettle();

    expect(_choice(tester, '기쁨').isSelected, isTrue);
    expect(
      find.byKey(const ValueKey('emotion-confirmation-panel')),
      findsOneWidget,
    );
    expect(repository.reflectionCalls, 0);
  });

  testWidgets('별도 다시 고르기 없이 다른 카드를 누르면 대표 감정 하나가 교체된다', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = _CompletionRepository();
    await _pumpEmotion(tester, repository: repository, sessionId: 42);
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();
    expect(find.text('다시 고를래'), findsNothing);
    expect(find.bySemanticsLabel('응! 맞아!'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('emotion-슬픔')));
    await tester.pumpAndSettle();

    expect(_choice(tester, '기쁨').isSelected, isFalse);
    expect(_choice(tester, '슬픔').isSelected, isTrue);
    expect(
      find.byKey(const ValueKey('emotion-confirmation-panel')),
      findsOneWidget,
    );
    expect(repository.reflectionCalls, 0);
    semantics.dispose();
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
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '우리 가족 소풍',
    );
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 1);
    expect(repository.lastReflection?.title, '우리 가족 소풍');
    expect(repository.lastReflection?.selectedEmotions, [
      DrawingEmotionType.happy,
    ]);
    expect(repository.lastReflection?.expressedEmotionText, isNull);
    expect(repository.lastReflection?.skipped, isFalse);
    expect(repository.activityCompletionCalls, 1);
    expect(repository.lastActivityRequest?.conversationSkipped, isFalse);
    expect(repository.lastActivityRequest?.requestReport, isTrue);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    expect(
      find.text('더 그리고 싶으면 또 그려도 돼요.\n다 했으면 보호자에게 기기를 건네주세요.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-complete-draw-again')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity-complete-actions-row')),
      findsOneWidget,
    );
    final completeIllustration = tester.widget<Image>(
      find.byKey(const ValueKey('activity-complete-thumbsup-illustration')),
    );
    expect(
      (completeIllustration.image as AssetImage).assetName,
      DodamDialogAssets.completeThumbsUp,
    );
    expect(completeIllustration.fit, BoxFit.contain);
    expect(completeIllustration.excludeFromSemantics, isTrue);
  });

  testWidgets('완료 버튼은 넓은 화면에서 파스텔 가로 배치와 48dp 터치 영역을 유지한다', (tester) async {
    await _pumpComplete(tester, size: const Size(1280, 800));

    final drawAgain = find.byKey(
      const ValueKey('activity-complete-draw-again'),
    );
    final guardian = find.byKey(const ValueKey('guardian-handoff'));
    expect(
      find.byKey(const ValueKey('activity-complete-actions-row')),
      findsOneWidget,
    );
    expect(tester.getSize(drawAgain).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(guardian).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .widget<Material>(
            find
                .descendant(of: drawAgain, matching: find.byType(Material))
                .first,
          )
          .color,
      Colors.white,
    );
    expect(
      tester
          .widget<Material>(
            find
                .descendant(of: guardian, matching: find.byType(Material))
                .first,
          )
          .color,
      const Color(0xFFFFE2D0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('완료 버튼은 좁은 화면과 큰 글씨에서 세로로 쌓인다', (tester) async {
    await _pumpComplete(
      tester,
      size: const Size(390, 844),
      textScaler: const TextScaler.linear(2),
    );

    final drawAgain = find.byKey(
      const ValueKey('activity-complete-draw-again'),
    );
    final guardian = find.byKey(const ValueKey('guardian-handoff'));
    expect(
      find.byKey(const ValueKey('activity-complete-actions-column')),
      findsOneWidget,
    );
    expect(tester.getSize(drawAgain).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(guardian).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip 확인은 빈 감정·skipped true로 한 번 저장하고 일반 완료로 이동한다', (
    tester,
  ) async {
    final calls = <String>[];
    final repository = _CompletionRepository(calls: calls);
    final observer = _CompletionNavigationObserver();
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      navigatorObserver: observer,
    );
    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '말하지 않은 그림',
    );
    await _openSkipDialog(tester);
    expect(repository.reflectionCalls, 0);

    final confirm = find.byKey(const ValueKey('emotion-skip-confirm'));
    final confirmButton = tester.widget<AppButton>(confirm);
    confirmButton.onPressed!();
    confirmButton.onPressed!();
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 1);
    expect(repository.lastReflection?.title, '말하지 않은 그림');
    expect(repository.lastReflection?.selectedEmotions, isEmpty);
    expect(repository.lastReflection?.expressedEmotionText, isNull);
    expect(repository.lastReflection?.skipped, isTrue);
    expect(calls.take(3), ['detail', 'reflection', 'complete']);
    expect(repository.activityCompleteCalls, 1);
    expect(observer.activityCompleteReplacements, 1);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
  });

  testWidgets('활동이 그 자리에서 끝나는 완료 응답에도 아이 화면은 완료를 안내한다', (tester) async {
    // 회귀: 서버가 완료를 REPORTING 접수가 아니라 COMPLETED 종료로 돌려주게 된 뒤에도
    //   앱이 옛 계약만 검사해, 감정도 저장되고 완료도 접수됐는데 아이 화면에는
    //   "지금은 잘 안 돼요"만 떴다. 재시도해도 같은 멱등 키로 같은 응답이 와 길이 없었다.
    final calls = <String>[];
    final repository = _CompletionRepository(
      calls: calls,
      activityCompletedSessionStatus: 'COMPLETED',
      activityCompletedCurrentStage: 'COMPLETED',
    );
    final observer = _CompletionNavigationObserver();
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      navigatorObserver: observer,
    );

    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 1);
    expect(repository.activityCompleteCalls, 1);
    expect(observer.activityCompleteReplacements, 1);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    expect(find.textContaining('지금은 잘 안 돼요'), findsNothing);
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
    await tester.pumpAndSettle();
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
    expect(find.text('취소'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
    final guardianIllustration = tester.widget<Image>(
      find.byKey(const ValueKey('guardian-handhold-illustration')),
    );
    expect(
      (guardianIllustration.image as AssetImage).assetName,
      DodamDialogAssets.guardianHandhold,
    );
    expect(guardianIllustration.fit, BoxFit.contain);
    expect(guardianIllustration.excludeFromSemantics, isTrue);

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
    expect(find.text('보호자에게 알려 다시 확인해 주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-handoff')), findsNothing);
    // S15P11B209-820: 실패 안내와 함께 이탈 경로가 항상 있어야 한다.
    expect(
      find.byKey(const ValueKey('activity-completion-failure-appbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-completion-child-home')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-completion-guardian-home')),
      findsOneWidget,
    );
  });

  testWidgets('완료 실패에서 AppBar 뒤로가기는 아동 홈으로 나간다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );
    expect(find.text('활동을 마무리하지 못했어요'), findsOneWidget);

    await tester.tap(find.byTooltip('뒤로 가기'));
    await tester.pumpAndSettle();

    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(find.text('활동을 마무리하지 못했어요'), findsNothing);
    expect(observer.childHomePushes, 1);
    expect(repository.sessionStatusCalls, 1);
  });

  testWidgets('완료 실패에서 시스템 뒤로가기는 아동 홈으로 나간다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );
    expect(find.text('활동을 마무리하지 못했어요'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(observer.childHomePushes, 1);
  });

  testWidgets('완료 실패에서 아동 홈 CTA를 연달아 눌러도 한 번만 이동한다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );

    // 같은 좌표로 두 번 누른다. 첫 입력이 이동을 시작한 뒤 도착한 두 번째
    // 입력이 또 한 번 스택을 세우면 안 된다.
    final center = tester.getCenter(
      find.byKey(const ValueKey('activity-completion-child-home')),
    );
    await tester.tapAt(center);
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(observer.childHomePushes, 1);
    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('완료 실패에서 아동 홈과 보호자 이동을 겹쳐 눌러도 한 번만 이동한다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );

    final guardian = tester.getCenter(
      find.byKey(const ValueKey('activity-completion-guardian-home')),
    );
    final childHome = tester.getCenter(
      find.byKey(const ValueKey('activity-completion-child-home')),
    );
    // 아동 홈 이동이 먼저 확정되면 뒤이은 보호자 이동은 무시돼야 한다.
    await tester.tapAt(childHome);
    await tester.tapAt(guardian);
    await tester.pumpAndSettle();

    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(find.text('보호자 화면으로 이동할까요?'), findsNothing);
    expect(observer.childHomePushes, 1);
    expect(observer.guardianHomePushes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('완료 실패에서 시스템 뒤로가기를 다시 눌러도 아동 홈에 머문다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('아동 홈 테스트'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(observer.childHomePushes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('완료 실패 이탈 뒤에는 추가 상태 조회도 화면 복귀도 없다', (tester) async {
    final repository = _CompletionRepository(
      sessionStatuses: ['IN_PROGRESS', 'FAILED'],
    );
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );
    expect(repository.sessionStatusCalls, 2);

    await tester.tap(
      find.byKey(const ValueKey('activity-completion-child-home')),
    );
    await tester.pumpAndSettle();

    for (var pump = 0; pump < 5; pump += 1) {
      await tester.pump();
    }

    expect(repository.sessionStatusCalls, 2);
    expect(repository.activityCompletionCalls, 0);
    expect(repository.reflectionCalls, 0);
    expect(repository.completeCalls, 0);
    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(find.text('활동을 마무리하지 못했어요'), findsNothing);
    expect(observer.childHomePushes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('완료 실패의 보호자 이동은 기존 확인 절차를 거친다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );

    await tester.tap(
      find.byKey(const ValueKey('activity-completion-guardian-home')),
    );
    await tester.pumpAndSettle();

    expect(find.text('보호자 화면으로 이동할까요?'), findsOneWidget);
    expect(find.text('보호자 홈 테스트'), findsNothing);
    expect(observer.guardianHomePushes, 0);
  });

  testWidgets('완료 실패의 보호자 이동을 취소하면 실패 화면에 남는다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );

    await tester.tap(
      find.byKey(const ValueKey('activity-completion-guardian-home')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.text('활동을 마무리하지 못했어요'), findsOneWidget);
    expect(find.text('보호자 화면으로 이동할까요?'), findsNothing);
    expect(observer.guardianHomePushes, 0);
    expect(observer.childHomePushes, 0);

    // 취소 뒤에도 이탈 수단이 다시 동작해야 한다.
    await tester.tap(
      find.byKey(const ValueKey('activity-completion-child-home')),
    );
    await tester.pumpAndSettle();
    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(observer.childHomePushes, 1);
  });

  testWidgets('완료 실패의 보호자 이동을 확인하면 기존 Guardian Home 경로를 탄다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );

    await tester.tap(
      find.byKey(const ValueKey('activity-completion-guardian-home')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('보호자 홈 테스트'), findsOneWidget);
    expect(find.text('활동을 마무리하지 못했어요'), findsNothing);
    expect(observer.guardianHomePushes, 1);
    expect(observer.childHomePushes, 0);
    expect(repository.sessionStatusCalls, 1);
  });

  testWidgets('완료 polling 중에는 뒤로가기가 계속 차단된다', (tester) async {
    final sessionCompleter = Completer<DrawingSessionDto>();
    final repository = _CompletionRepository(
      sessionCompleter: sessionCompleter,
    );
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
      settle: false,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('activity-completion-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-completion-failure-appbar')),
      findsNothing,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('activity-completion-progress')),
      findsOneWidget,
    );
    expect(find.text('아동 홈 테스트'), findsNothing);
    expect(observer.childHomePushes, 0);

    sessionCompleter.complete(_sessionDto(sessionId: 42, status: 'COMPLETED'));
    await tester.pumpAndSettle();
  });

  testWidgets('완료 성공 화면에서는 뒤로가기가 계속 차단된다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['COMPLETED']);
    final observer = _LeaveNavigationObserver();

    await _pumpComplete(
      tester,
      repository: repository,
      sessionId: 42,
      pollInterval: Duration.zero,
      navigatorObserver: observer,
    );
    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity-completion-failure-appbar')),
      findsNothing,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    expect(find.text('아동 홈 테스트'), findsNothing);
    expect(observer.childHomePushes, 0);
  });

  testWidgets('세션 식별자 없는 완료 안내에서도 뒤로가기는 차단된다', (tester) async {
    final observer = _LeaveNavigationObserver();
    await _pumpComplete(tester, navigatorObserver: observer);

    expect(find.byKey(const ValueKey('guardian-handoff')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    expect(observer.childHomePushes, 0);
  });

  testWidgets('완료 실패 이탈은 이전 route가 남아 있어도 아동 홈으로 스택을 세운다', (tester) async {
    final repository = _CompletionRepository(sessionStatuses: ['FAILED']);
    final observer = _LeaveNavigationObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        routes: {
          AppRoutes.guardianHome: (_) =>
              const Scaffold(body: Text('보호자 홈 테스트')),
          AppRoutes.childModeHome('3'): (_) =>
              const Scaffold(body: Text('아동 홈 테스트')),
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: RouteSettings(
                    name: AppRoutes.activityComplete('3'),
                  ),
                  builder: (_) => ActivityCompleteScreen(
                    childId: '3',
                    sessionId: 42,
                    drawingRepository: repository,
                    pollInterval: Duration.zero,
                  ),
                ),
              ),
              child: const Text('완료 화면 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('완료 화면 열기'));
    await tester.pumpAndSettle();
    expect(find.text('활동을 마무리하지 못했어요'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('activity-completion-child-home')),
    );
    await tester.pumpAndSettle();

    // pop이 아니라 스택 재구성이라 직전 화면이 아니라 아동 홈이 남는다.
    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(find.text('완료 화면 열기'), findsNothing);
    expect(observer.childHomePushes, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('아동 홈 테스트'), findsOneWidget);
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

  testWidgets('또 그리기를 누르면 아동 홈으로 스택을 세워 새 활동을 시작한다', (tester) async {
    final observer = _LeaveNavigationObserver();
    await _pumpComplete(tester, navigatorObserver: observer);

    expect(
      find.byKey(const ValueKey('activity-complete-draw-again')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('activity-complete-draw-again')),
    );
    await tester.pumpAndSettle();

    // 완료 확인 Dialog 없이 곧바로 아동 홈으로 이동한다.
    expect(find.text('아동 홈 테스트'), findsOneWidget);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsNothing);
    expect(observer.childHomePushes, 1);
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

  testWidgets('확인 전에는 Reflection을 호출하지 않고 목업 기능을 표시하지 않는다', (tester) async {
    final repository = _CompletionRepository();
    await _pumpEmotion(tester, repository: repository, sessionId: 42);
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 0);
    for (final removedCopy in [
      '얼마나 그런 기분이야?',
      '조금',
      '보통',
      '많이',
      '왜 그런 기분인지 말해줄래?',
      '크레용',
      '그림첩에 저장하기',
      '보여주기',
      '또 그리기',
    ]) {
      expect(find.text(removedCopy), findsNothing);
    }
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });

  testWidgets('Reflection 실패 시 감정과 제목을 유지해 재시도할 수 있다', (tester) async {
    final repository = _CompletionRepository(reflectionError: StateError('x'));
    await _pumpEmotion(tester, repository: repository, sessionId: 42);
    await tester.tap(find.byKey(const ValueKey('emotion-화남')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '화난 그림',
    );
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(_choice(tester, '화남').isSelected, isTrue);
    expect(find.text('화난 그림'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emotion-drawing-preview-image')),
      findsOneWidget,
    );
    expect(find.textContaining('고른 마음은 그대로'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('일시 오류는 같은 대표 감정으로 재시도하고 성공 시 한 번 이동한다', (tester) async {
    final failures = <Object>[
      const ApiTransportFailure(type: ApiTransportFailureType.connection),
      const ApiTransportFailure(type: ApiTransportFailureType.receiveTimeout),
      _reflectionFailure(500),
      _reflectionFailure(502),
      _reflectionFailure(503),
    ];
    for (final failure in failures) {
      final repository = _CompletionRepository(reflectionError: failure);
      await _pumpEmotion(tester, repository: repository, sessionId: 42);
      await tester.tap(find.byKey(const ValueKey('emotion-슬픔')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('emotion-submit')));
      await tester.pumpAndSettle();

      expect(repository.reflectionCalls, 1, reason: '$failure');
      expect(_choice(tester, '슬픔').isSelected, isTrue);
      expect(
        find.byKey(const ValueKey('emotion-submit-error')),
        findsOneWidget,
      );
      repository.reflectionError = null;

      await tester.tap(find.byKey(const ValueKey('emotion-submit')));
      await tester.pumpAndSettle();
      expect(repository.reflectionCalls, 2, reason: '$failure');
      expect(repository.activityCompleteCalls, 1, reason: '$failure');
      expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    }
  });

  testWidgets('영구 오류와 취소는 기술 정보를 숨기고 추가 Reflection 요청을 막는다', (tester) async {
    final failures = <Object>[
      for (final status in [400, 401, 403, 404, 409, 422])
        _reflectionFailure(status),
      const ApiTransportFailure(type: ApiTransportFailureType.cancelled),
    ];
    for (final failure in failures) {
      final repository = _CompletionRepository(reflectionError: failure);
      await _pumpEmotion(tester, repository: repository, sessionId: 42);
      await tester.tap(find.byKey(const ValueKey('emotion-불안')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('emotion-submit')));
      await tester.pumpAndSettle();

      expect(repository.reflectionCalls, 1, reason: '$failure');
      expect(_choice(tester, '불안').isSelected, isTrue);
      expect(find.textContaining('SECRET_REFLECTION'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('emotion-submit')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(repository.reflectionCalls, 1, reason: '$failure');
    }
  });

  testWidgets('skip 일시 오류는 같은 빈 감정 요청으로 재시도해 한 번 이동한다', (tester) async {
    final failures = <Object>[
      const ApiTransportFailure(type: ApiTransportFailureType.connection),
      const ApiTransportFailure(type: ApiTransportFailureType.receiveTimeout),
      _reflectionFailure(500),
      _reflectionFailure(502),
      _reflectionFailure(503),
    ];
    for (final failure in failures) {
      final repository = _CompletionRepository(reflectionError: failure);
      final observer = _CompletionNavigationObserver();
      await _pumpEmotion(
        tester,
        repository: repository,
        sessionId: 42,
        navigatorObserver: observer,
      );
      await tester.tap(find.byKey(const ValueKey('emotion-편안')));
      await tester.pumpAndSettle();
      await _confirmSkip(tester);

      expect(repository.reflectionCalls, 1, reason: '$failure');
      expect(repository.lastReflection?.selectedEmotions, isEmpty);
      expect(repository.lastReflection?.skipped, isTrue);
      expect(_choice(tester, '편안').isSelected, isTrue);
      expect(find.byKey(const ValueKey('emotion-skip-error')), findsOneWidget);
      expect(find.textContaining('SECRET_REFLECTION'), findsNothing);
      repository.reflectionError = null;

      await _confirmSkip(tester);
      expect(repository.reflectionCalls, 2, reason: '$failure');
      expect(repository.lastReflection?.selectedEmotions, isEmpty);
      expect(repository.lastReflection?.skipped, isTrue);
      expect(repository.activityCompleteCalls, 1, reason: '$failure');
      expect(observer.activityCompleteReplacements, 1, reason: '$failure');
    }
  });

  testWidgets('skip 영구 오류와 취소는 기술 정보를 숨기고 추가 요청을 막는다', (tester) async {
    final failures = <Object>[
      for (final status in [400, 401, 403, 404, 409, 422])
        _reflectionFailure(status),
      const ApiTransportFailure(type: ApiTransportFailureType.cancelled),
    ];
    for (final failure in failures) {
      final repository = _CompletionRepository(reflectionError: failure);
      await _pumpEmotion(tester, repository: repository, sessionId: 42);
      await tester.tap(find.byKey(const ValueKey('emotion-불안')));
      await tester.pumpAndSettle();
      await _confirmSkip(tester);

      expect(repository.reflectionCalls, 1, reason: '$failure');
      expect(repository.lastReflection?.selectedEmotions, isEmpty);
      expect(repository.lastReflection?.skipped, isTrue);
      expect(_choice(tester, '불안').isSelected, isTrue);
      expect(find.textContaining('SECRET_REFLECTION'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('emotion-skip')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('emotion-skip-dialog')), findsNothing);
      expect(repository.reflectionCalls, 1, reason: '$failure');
    }
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
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('drawing-title')),
      '잠근 제목',
    );

    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pump();

    expect(repository.reflectionCalls, 1);
    final loadingStatus = find.bySemanticsLabel('마음을 저장하고 있어요');
    expect(loadingStatus, findsOneWidget);
    expect(
      tester.getSemantics(loadingStatus),
      matchesSemantics(
        label: '마음을 저장하고 있어요',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        isLiveRegion: true,
      ),
    );
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

    await tester.tap(
      find.byKey(const ValueKey('emotion-skip')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('emotion-skip-dialog')), findsNothing);
    expect(repository.reflectionCalls, 1);

    reflectionCompleter.complete();
    await tester.pumpAndSettle();

    expect(repository.activityCompleteCalls, 1);
    expect(observer.activityCompleteReplacements, 1);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
  });

  testWidgets('skip 요청 중 카드·감정 확인을 잠그고 연속 입력에도 요청은 하나다', (tester) async {
    final reflectionCompleter = Completer<void>();
    final repository = _CompletionRepository(
      reflectionCompleter: reflectionCompleter,
    );
    final observer = _CompletionNavigationObserver();
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      navigatorObserver: observer,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-슬픔')));
    await tester.pumpAndSettle();
    await _openSkipDialog(tester);
    final confirm = find.byKey(const ValueKey('emotion-skip-confirm'));
    final confirmButton = tester.widget<AppButton>(confirm);
    confirmButton.onPressed!();
    confirmButton.onPressed!();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repository.reflectionCalls, 1);
    expect(repository.lastReflection?.selectedEmotions, isEmpty);
    expect(repository.lastReflection?.skipped, isTrue);
    expect(_choice(tester, '슬픔').isSelected, isTrue);
    expect(_choice(tester, '기쁨').onTap, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('emotion-skip')),
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('emotion-screen-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    expect(
      tester
          .widget<EmotionSkipButton>(find.byKey(const ValueKey('emotion-skip')))
          .isLoading,
      isTrue,
    );
    expect(find.text('넘어갈 준비를 하고 있어요'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('emotion-skip')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('emotion-submit')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('emotion-기쁨')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repository.reflectionCalls, 1);
    expect(_choice(tester, '슬픔').isSelected, isTrue);

    reflectionCompleter.complete();
    await tester.pumpAndSettle();
    expect(repository.activityCompleteCalls, 1);
    expect(observer.activityCompleteReplacements, 1);
  });

  testWidgets('감정 화면 dispose 후 늦은 Reflection 성공은 완료 화면으로 이동하지 않는다', (
    tester,
  ) async {
    final reflectionCompleter = Completer<void>();
    final repository = _CompletionRepository(
      reflectionCompleter: reflectionCompleter,
    );
    final observer = _CompletionNavigationObserver();
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      navigatorObserver: observer,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pump();
    expect(repository.reflectionCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    reflectionCompleter.complete();
    await tester.pumpAndSettle();

    expect(repository.activityCompleteCalls, 0);
    expect(observer.activityCompleteReplacements, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('감정 화면 dispose 후 늦은 skip 성공은 후속 API와 이동을 시작하지 않는다', (
    tester,
  ) async {
    final reflectionCompleter = Completer<void>();
    final repository = _CompletionRepository(
      reflectionCompleter: reflectionCompleter,
    );
    final observer = _CompletionNavigationObserver();
    await _pumpEmotion(
      tester,
      repository: repository,
      sessionId: 42,
      navigatorObserver: observer,
    );
    await _openSkipDialog(tester);
    await tester.tap(find.byKey(const ValueKey('emotion-skip-confirm')));
    await tester.pump();
    expect(repository.reflectionCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    reflectionCompleter.complete();
    await tester.pumpAndSettle();

    expect(repository.activityCompleteCalls, 0);
    expect(observer.activityCompleteReplacements, 0);
    expect(tester.takeException(), isNull);
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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 0);
    expect(find.textContaining('아직 마음을 저장할 수 없어요'), findsWidgets);
  });

  testWidgets('감정 화면은 360×640·textScale 2·tablet 세로·가로에서 overflow가 없다', (
    tester,
  ) async {
    await _pumpEmotion(tester, size: const Size(1200, 600));
    expect(
      find.byKey(const ValueKey('emotion-compact-layout')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('emotion-기쁨')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('emotion-screen-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('emotion-submit')), findsOneWidget);

    await _pumpEmotion(
      tester,
      size: const Size(360, 640),
      textScaler: const TextScaler.linear(2),
    );
    expect(
      find.byKey(const ValueKey('emotion-compact-layout')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('emotion-skip')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('emotion-screen-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _openSkipDialog(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('emotion-skip-confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('emotion-skip-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('emotion-skip-cancel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('emotion-불안')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('emotion-screen-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-불안')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('emotion-submit')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('emotion-submit'))).bottom,
      lessThanOrEqualTo(640),
    );

    await _pumpEmotion(tester, size: const Size(800, 1280));
    expect(
      find.byKey(const ValueKey('emotion-compact-layout')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('emotion-편안')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('emotion-screen-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-편안')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _pumpEmotion(tester, size: const Size(1280, 800));
    expect(
      find.byKey(const ValueKey('emotion-compact-layout')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Image>(
            find.byKey(const ValueKey('emotion-drawing-preview-image')),
          )
          .fit,
      BoxFit.contain,
    );
    expect(tester.takeException(), isNull);
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
  ValueChanged<EmotionSelectRouteArguments>? onEmotionRouteArguments,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        AppRoutes.emotionSelect('3'): (context) {
          final arguments =
              ModalRoute.of(context)!.settings.arguments!
                  as EmotionSelectRouteArguments;
          onEmotionRouteArguments?.call(arguments);
          return EmotionSelectScreen(
            childId: '3',
            completedDrawingImage: arguments.completedDrawingImage,
          );
        },
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
  TextScaler textScaler = TextScaler.noScaling,
  DrawingRepository? repository,
  int? sessionId,
  DrawingActivityCompletionController? activityCompletionController,
  NavigatorObserver? navigatorObserver,
  bool conversationSkipped = true,
  BinaryUploadDto? completedDrawingImage = _png,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      navigatorObservers: [?navigatorObserver],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
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
        completedDrawingImage: completedDrawingImage,
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
  NavigatorObserver? navigatorObserver,
  bool settle = true,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      navigatorObservers: [?navigatorObserver],
      routes: {
        AppRoutes.guardianHome: (_) => const Scaffold(body: Text('보호자 홈 테스트')),
        AppRoutes.childModeHome(childId): (_) =>
            const Scaffold(body: Text('아동 홈 테스트')),
      },
      home: ActivityCompleteScreen(
        childId: childId,
        sessionId: sessionId,
        drawingRepository: repository,
        pollInterval: pollInterval,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _drawStroke(WidgetTester tester) async {
  final center = tester.getCenter(find.byKey(const ValueKey('drawing-canvas')));
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(const Offset(30, 20));
  await gesture.up();
  await tester.pump();
}

Future<void> _openSkipDialog(WidgetTester tester) async {
  final skip = find.byKey(const ValueKey('emotion-skip'));
  await tester.scrollUntilVisible(
    skip,
    220,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('emotion-screen-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(skip);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('emotion-skip-dialog')), findsOneWidget);
}

Future<void> _confirmSkip(WidgetTester tester) async {
  await _openSkipDialog(tester);
  await tester.tap(find.byKey(const ValueKey('emotion-skip-confirm')));
  await tester.pumpAndSettle();
}

EmotionChoiceCard _choice(WidgetTester tester, String label) =>
    tester.widget<EmotionChoiceCard>(find.byKey(ValueKey('emotion-$label')));

const _png = BinaryUploadDto(
  bytes: [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    2,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    244,
    34,
    127,
    138,
    0,
    0,
    0,
    14,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    248,
    207,
    192,
    0,
    66,
    255,
    1,
    15,
    249,
    3,
    253,
    133,
    17,
    153,
    118,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ],
  fileName: 'final.png',
  mimeType: 'image/png',
);

const _draftSaveResponse = DraftSaveResponseDto(
  drawingAssetId: 1,
  assetVersion: 1,
  lastEventSequence: 2,
  savedAt: '2026-07-22T00:00:00Z',
  expiresAt: null,
);

ApiResponseFailure _reflectionFailure(int statusCode) => ApiResponseFailure(
  statusCode: statusCode,
  error: const ApiError(
    code: 'SECRET_REFLECTION',
    message: 'internal reflection failure',
  ),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await tester.pump();
  }
  fail('condition was not met');
}

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

const _reflectionCompleteResponse = DrawingStageCompleteResponseDto(
  drawingSessionId: 42,
  finalAssetId: 140,
  sessionStatus: 'IN_PROGRESS',
  currentStage: 'REFLECTION',
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
    this.strokeError,
    this.draftCompleter,
    this.activityCompletedSessionStatus = 'IN_PROGRESS',
    this.activityCompletedCurrentStage = 'REPORTING',
  }) : _sessionStatuses = List.of(sessionStatuses),
       _sessionFailures = List.of(sessionFailures);

  /// 활동 완료 접수가 돌려주는 상태. 기본값은 HTP 묶음이 남기는 접수 형태다.
  ///
  /// 일반 활동은 이제 `COMPLETED`/`COMPLETED`로 그 자리에서 끝난다 — 그 형태를 앱이
  /// 거부해 **서버가 성공한 활동이 아이 화면에서 실패로 보인** 적이 있다(2026-08-08 실측).
  final String activityCompletedSessionStatus;
  final String activityCompletedCurrentStage;

  final Completer<DrawingStageCompleteResponseDto>? completer;
  final DrawingStageCompleteResponseDto completionResponse;
  Object? completionError;
  int completeCalls = 0;
  BinaryUploadDto? lastFinalImage;
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
  int strokeCalls = 0;
  final Object? strokeError;
  final Completer<DraftSaveResponseDto>? draftCompleter;
  int draftCalls = 0;

  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) {
    calls?.add('drawing-complete');
    completeCalls += 1;
    lastFinalImage = finalImage;
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
      sessionStatus: activityCompletedSessionStatus,
      currentStage: activityCompletedCurrentStage,
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
  ) async {
    calls?.add('stroke');
    strokeCalls += 1;
    if (strokeError case final error?) throw error;
    return StrokeBatchResponseDto(
      batchId: strokeCalls,
      batchSequence: request.batchSequence,
      acceptedEventCount: request.events.length,
      lastEventSequence: request.lastEventSequence,
      receivedAt: '2026-07-22T00:00:00Z',
    );
  }

  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState, {
    required String idempotencyKey,
  }) {
    draftCalls += 1;
    calls?.add('draft');
    return draftCompleter?.future ?? Future.value(_draftSaveResponse);
  }

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

/// 완료 실패 화면 이탈이 몇 번 일어났는지 센다(S15P11B209-820 single-flight).
final class _LeaveNavigationObserver extends NavigatorObserver {
  final List<String> pushedRoutes = [];

  int get childHomePushes =>
      pushedRoutes.where((name) => name == AppRoutes.childModeHome('3')).length;

  int get guardianHomePushes =>
      pushedRoutes.where((name) => name == AppRoutes.guardianHome).length;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) pushedRoutes.add(name);
    super.didPush(route, previousRoute);
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
