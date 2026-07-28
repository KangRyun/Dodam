import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_draft_restore_controller.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sessionId가 없으면 Draft API를 호출하지 않고 바로 그릴 수 있다', () async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(
      sessionId: null,
      repository: repository,
    );
    final controller = DrawingDraftRestoreController(
      sessionId: null,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();

    expect(repository.getDraftCalls, 0);
    expect(controller.status, DrawingDraftRestoreStatus.unavailable);
    expect(controller.canDraw, isTrue);
  });

  test('Draft 없음은 오류가 아닌 새 Canvas 상태로 처리한다', () async {
    final repository = _DraftRepository(scenario: _Scenario.absent);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.status, DrawingDraftRestoreStatus.noDraft);
    expect(controller.canDraw, isTrue);
  });

  test('빈 Draft 응답도 오류가 아닌 새 Canvas 상태로 처리한다', () async {
    final repository = _DraftRepository(scenario: _Scenario.empty);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.status, DrawingDraftRestoreStatus.noDraft);
    expect(controller.canDraw, isTrue);
  });

  test('Draft 조회 실패와 이미지 실패를 구분하고 재시도할 수 있다', () async {
    final repository = _DraftRepository(scenario: _Scenario.failure);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
      imageProviderFactory: (_) => MemoryImage(Uint8List.fromList([0])),
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.status, DrawingDraftRestoreStatus.queryFailed);

    repository.scenario = _Scenario.found;
    await controller.load();
    await controller.continueDrawing();
    controller.markImageFailed();
    expect(controller.status, DrawingDraftRestoreStatus.imageFailed);

    await controller.retryImage();
    expect(controller.status, DrawingDraftRestoreStatus.loadingImage);
  });

  test('이어 그리기는 Repository에서 인증된 이미지 bytes를 내려받는다', () async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    await controller.continueDrawing();

    expect(repository.downloadDraftPreviewCalls, 1);
    expect(repository.downloadedPreviewUrl, _asset.fileUrl);
    expect(controller.backgroundImage, isA<MemoryImage>());
    expect(controller.status, DrawingDraftRestoreStatus.loadingImage);
  });

  test('복구 뒤 event와 batch 시퀀스를 모두 이어받는다', () async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    final events = sync.recordStroke(_stroke(), const Size(100, 100));
    await sync.flushEvents();

    expect(events.first.seq, 1106);
    expect(events.last.seq, 1107);
    // batchSequence도 Draft의 lastEventSequence(1105) 뒤인 1106부터 시작해야 이미
    // 저장된 batchSequence=1과 충돌(DRAWING_409_019)하지 않는다.
    expect(repository.lastBatch?.batchSequence, 1106);
    expect(repository.lastBatch?.firstEventSequence, events.last.seq);
    expect(repository.lastBatch?.lastEventSequence, events.last.seq);
    expect(sync.journal.events, hasLength(2));
    expect(sync.journal.lastEventSequence, events.last.seq);
  });

  test('서버 시퀀스가 null이면 기존 로컬 기본값을 유지한다', () async {
    final repository = _DraftRepository(nullSequences: true);
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final controller = DrawingDraftRestoreController(
      sessionId: 42,
      repository: repository,
      syncCoordinator: sync,
    );
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);

    await controller.load();
    final events = sync.recordStroke(_stroke(), const Size(100, 100));
    await sync.flushEvents();

    expect(events.first.seq, 1);
    expect(repository.lastBatch?.batchSequence, 1);
  });

  testWidgets('복구 이미지를 배경으로 표시하고 새 Stroke와 Undo를 분리한다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final restore = await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
    );

    expect(find.text('그리던 그림이 있어요'), findsOneWidget);
    expect(find.text('이어서 그릴까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-primary-action')));
    restore.markImageLoaded();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('draft-background-image')),
      findsOneWidget,
    );
    expect(find.text('그리던 그림이 있어요'), findsNothing);
    expect(_canvas(tester).strokes, isEmpty);

    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();
    expect(_canvas(tester).strokes, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(_canvas(tester).strokes, isEmpty);
    expect(
      find.byKey(const ValueKey('draft-background-image')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('새로 시작은 서버 Draft를 삭제하지 않고 빈 Canvas를 연다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    await _pumpScreen(tester, repository: repository, sync: sync);

    await tester.tap(find.byKey(const ValueKey('draft-start-new')));
    await tester.pump();

    expect(repository.deleteDraftCalls, 0);
    expect(find.byKey(const ValueKey('draft-background-image')), findsNothing);
    expect(_canvas(tester).strokes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('복구 배경과 새 Stroke는 같은 snapshot 경계 안에서 저장된다', (tester) async {
    final repository = _DraftRepository();
    final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
    final restore = await _pumpScreen(
      tester,
      repository: repository,
      sync: sync,
    );
    await tester.tap(find.byKey(const ValueKey('draft-primary-action')));
    restore.markImageLoaded();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump();
    await tester.runAsync(sync.saveDraftNow);

    expect(repository.savedImage?.mimeType, 'image/png');
    expect(repository.savedImage?.bytes, isNotEmpty);
    expect(repository.savedLastEventSequence, 1107);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('draft-background-image')),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });
}

Future<DrawingDraftRestoreController> _pumpScreen(
  WidgetTester tester, {
  required _DraftRepository repository,
  required DrawingSyncCoordinator sync,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final restore = DrawingDraftRestoreController(
    sessionId: 42,
    repository: repository,
    syncCoordinator: sync,
    imageProviderFactory: (_) => MemoryImage(_validPng),
  );
  addTearDown(restore.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '3',
        sessionId: 42,
        drawingRepository: repository,
        syncCoordinator: sync,
        draftRestoreController: restore,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return restore;
}

DrawingCanvas _canvas(WidgetTester tester) =>
    tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));

final _validPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

DrawingStroke _stroke() => const DrawingStroke(
  color: AppColors.drawingInk,
  thickness: 8,
  points: [
    DrawingPoint(position: Offset(10, 10), elapsedMilliseconds: 10),
    DrawingPoint(position: Offset(20, 20), elapsedMilliseconds: 20),
  ],
);

enum _Scenario { found, absent, empty, failure }

final class _DraftRepository implements DrawingRepository {
  _DraftRepository({
    this.scenario = _Scenario.found,
    this.nullSequences = false,
  });

  _Scenario scenario;
  final bool nullSequences;
  int getDraftCalls = 0;
  int downloadDraftPreviewCalls = 0;
  int deleteDraftCalls = 0;
  String? downloadedPreviewUrl;
  StrokeBatchRequestDto? lastBatch;
  BinaryUploadDto? savedImage;
  int? savedLastEventSequence;

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async {
    getDraftCalls += 1;
    if (scenario == _Scenario.failure) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    if (scenario == _Scenario.absent) {
      throw ApiResponseFailure(
        statusCode: 404,
        error: ApiError(
          timestamp: '2026-07-22T00:00:00Z',
          path: '/api/v1/drawing-sessions/$sessionId/draft',
          code: 'DRAWING_404_004',
          message: 'not found',
        ),
      );
    }
    if (scenario == _Scenario.empty) return null;
    return DraftRecoveryDto(
      previewUrl: _asset.fileUrl,
      canvasState: DraftCanvasStateDto(
        lastEventSequence: nullSequences ? null : 1105,
        toolState: null,
        viewport: null,
        clientSavedAt: '2026-07-21T09:41:10Z',
      ),
      assetVersion: 3,
    );
  }

  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) async {
    downloadDraftPreviewCalls += 1;
    downloadedPreviewUrl = previewUrl;
    if (scenario == _Scenario.failure) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    return _validPng;
  }

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async {
    lastBatch = request;
    return StrokeBatchResponseDto(
      batchId: 1,
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
    DraftCanvasStateDto canvasState,
  ) async {
    savedImage = preview;
    savedLastEventSequence = canvasState.lastEventSequence;
    return DraftSaveResponseDto(
      drawingAssetId: 1,
      assetVersion: 3,
      lastEventSequence: canvasState.lastEventSequence,
      savedAt: '2026-07-22T00:00:00Z',
      expiresAt: null,
    );
  }

  @override
  Future<void> deleteDraft(int sessionId) async => deleteDraftCalls += 1;

  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingCompletionResponseDto> completeActivity(
    int sessionId, {
    required CompleteActivityRequestDto request,
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingSessionDto> getSession(int sessionId) =>
      throw UnimplementedError();
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
    String? objectCode,
  }) => throw UnimplementedError();
}

const _asset = DrawingAssetDto(
  assetId: 120,
  assetType: 'DRAFT',
  assetVersion: 3,
  fileUrl: 'https://example.test/draft.png',
  mimeType: 'image/png',
  widthPx: 100,
  heightPx: 100,
);
