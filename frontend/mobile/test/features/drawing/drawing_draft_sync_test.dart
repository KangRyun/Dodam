import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Draft multipart는 PNG와 JSON MIME part만 포함한다', () async {
    const canvasState = DraftCanvasStateDto(
      lastEventSequence: 17,
      toolState: null,
      viewport: null,
      clientSavedAt: '2026-07-22T09:00:00+09:00',
    );
    final form = buildDraftFormData(
      const BinaryUploadDto(
        bytes: [1, 2, 3],
        fileName: 'drawing-draft.png',
        mimeType: 'image/png',
      ),
      canvasState,
    );

    expect(form.fields, isEmpty);
    final preview = form.files.singleWhere((part) => part.key == 'preview');
    expect(preview.value.filename, 'drawing-draft.png');
    expect(preview.value.contentType?.toString(), 'image/png');
    expect(await _multipartBytes(preview.value), [1, 2, 3]);
    final request = form.files.singleWhere((part) => part.key == 'canvasState');
    expect(request.value.filename, 'canvas-state.json');
    expect(request.value.contentType?.toString(), 'application/json');
    expect(jsonDecode(utf8.decode(await _multipartBytes(request.value))), {
      'lastEventSequence': 17,
      'clientSavedAt': '2026-07-22T09:00:00+09:00',
    });
  });

  test('Draft 저장 중 성공 상태와 snapshot 시점의 마지막 seq를 전달한다', () async {
    final completer = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(saveCompleter: completer);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    final saving = coordinator.saveDraftNow();
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.saveStatus, DrawingSaveStatus.saving);
    expect(repository.lastEventSequence, 2);

    completer.complete(_draftSaveResponse);
    await saving;
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('Draft 실패는 입력을 막지 않고 retry 후 성공할 수 있다', () async {
    final repository = _FakeDrawingRepository(saveError: StateError('store'));
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.saveDraftNow();
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    final before = coordinator.journal.events.length;
    coordinator.recordStroke(_stroke(t: 30), const Size(100, 100));
    expect(coordinator.journal.events.length, greaterThan(before));

    repository.saveError = null;
    await coordinator.retry();
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
    expect(repository.draftCalls, 2);
    expect(
      identical(repository.draftPreviews.first, repository.draftPreviews.last),
      isTrue,
    );
    expect(
      identical(
        repository.draftCanvasStates.first,
        repository.draftCanvasStates.last,
      ),
      isTrue,
    );
    expect(repository.draftCanvasStates.last.lastEventSequence, 2);
    expect(
      repository.draftCanvasStates.last.clientSavedAt,
      repository.draftCanvasStates.first.clientSavedAt,
    );
  });

  test(
    'Undo가 마지막 Canvas event이면 Draft sequence에 Undo sequence를 유지한다',
    () async {
      final repository = _FakeDrawingRepository();
      final coordinator = DrawingSyncCoordinator(
        sessionId: 42,
        repository: repository,
      );
      addTearDown(coordinator.dispose);
      coordinator.recordStroke(_stroke(), const Size(100, 100));
      final undo = coordinator.recordUndo();
      coordinator.start(snapshotProvider: () async => _png);

      await coordinator.saveDraftNow();

      expect(undo?.seq, 3);
      expect(repository.lastEventSequence, 3);
    },
  );

  test('sessionId 미연결 상태에서는 journal만 기록하고 네트워크를 호출하지 않는다', () async {
    final repository = _FakeDrawingRepository();
    final coordinator = DrawingSyncCoordinator(
      sessionId: null,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.flushEvents();
    await coordinator.saveDraftNow();

    expect(coordinator.journal.events, hasLength(2));
    expect(coordinator.batchQueue.pendingBatches, hasLength(1));
    expect(repository.strokeCalls, 0);
    expect(repository.draftCalls, 0);
    expect(coordinator.saveStatus, DrawingSaveStatus.localOnly);
  });

  test('snapshot 생성 실패도 비차단 저장 실패 상태로 처리한다', () async {
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: _FakeDrawingRepository(),
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(
      snapshotProvider: () async => throw StateError('capture'),
    );

    await coordinator.saveDraftNow();

    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    coordinator.recordStroke(_stroke(t: 50), const Size(100, 100));
    expect(coordinator.journal.events, hasLength(4));
  });
}

const _png = BinaryUploadDto(
  bytes: [137, 80, 78, 71],
  fileName: 'draft.png',
  mimeType: 'image/png',
);

const _draftSaveResponse = DraftSaveResponseDto(
  drawingAssetId: 1,
  assetVersion: 1,
  lastEventSequence: 2,
  savedAt: '2026-07-22T00:00:00Z',
  expiresAt: null,
);

Future<List<int>> _multipartBytes(MultipartFile file) => file
    .finalize()
    .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));

DrawingStroke _stroke({int t = 10}) => DrawingStroke(
  color: AppColors.drawingInk,
  thickness: 8,
  points: [
    DrawingPoint(position: const Offset(10, 10), elapsedMilliseconds: t),
    DrawingPoint(position: const Offset(20, 20), elapsedMilliseconds: t + 10),
  ],
);

final class _FakeDrawingRepository implements DrawingRepository {
  _FakeDrawingRepository({this.saveCompleter, this.saveError});

  Completer<DraftSaveResponseDto>? saveCompleter;
  Object? saveError;
  int strokeCalls = 0;
  int draftCalls = 0;
  int? lastEventSequence;
  final List<BinaryUploadDto> draftPreviews = [];
  final List<DraftCanvasStateDto> draftCanvasStates = [];

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async {
    strokeCalls += 1;
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
    draftCalls += 1;
    lastEventSequence = canvasState.lastEventSequence;
    draftPreviews.add(preview);
    draftCanvasStates.add(canvasState);
    if (saveError case final error?) throw error;
    return saveCompleter?.future ?? _draftSaveResponse;
  }

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
  Future<DrawingActivityCompleteResponseDto> completeActivity(
    int sessionId, {
    required DrawingActivityCompleteRequestDto request,
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<void> deleteDraft(int sessionId) => throw UnimplementedError();
  @override
  Future<DraftRecoveryDto> getDraft(int sessionId) =>
      throw UnimplementedError();
  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;
  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) =>
      throw UnimplementedError();
  @override
  Future<DrawingSessionDto> getSession(int sessionId) =>
      throw UnimplementedError();
  @override
  Future<DrawingSessionCompletionStatusDto> getSessionCompletionStatus(
    int sessionId,
  ) => throw UnimplementedError();
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
