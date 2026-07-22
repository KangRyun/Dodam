import 'dart:async';
import 'dart:ui';

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Draft multipart에 PNG MIME과 lastEventSequence를 포함한다', () {
    final form = buildDraftFormData(
      const BinaryUploadDto(
        bytes: [1, 2, 3],
        fileName: 'draft.png',
        mimeType: 'image/png',
      ),
      lastEventSequence: 17,
    );

    expect(form.files.single.key, 'image');
    expect(form.files.single.value.filename, 'draft.png');
    expect(form.files.single.value.contentType?.toString(), 'image/png');
    expect(
      form.fields
          .singleWhere((field) => field.key == 'lastEventSequence')
          .value,
      '17',
    );
  });

  test('Draft 저장 중 성공 상태와 snapshot 시점의 마지막 seq를 전달한다', () async {
    final completer = Completer<DrawingAssetDto>();
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

    completer.complete(_asset);
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
  });

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

const _asset = DrawingAssetDto(
  assetId: 1,
  assetType: 'DRAFT',
  assetVersion: 1,
  fileUrl: 'https://example.test/draft.png',
  mimeType: 'image/png',
  widthPx: 100,
  heightPx: 100,
);

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

  Completer<DrawingAssetDto>? saveCompleter;
  Object? saveError;
  int strokeCalls = 0;
  int draftCalls = 0;
  int? lastEventSequence;

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async {
    strokeCalls += 1;
    return StrokeBatchResponseDto(
      strokeBatchId: 1,
      batchSequence: request.batchSequence,
      eventCount: request.events.length,
      receivedAt: '2026-07-22T00:00:00Z',
    );
  }

  @override
  Future<DrawingAssetDto> saveDraft(
    int sessionId,
    BinaryUploadDto image, {
    int? lastEventSequence,
  }) async {
    draftCalls += 1;
    this.lastEventSequence = lastEventSequence;
    if (saveError case final error?) throw error;
    return saveCompleter?.future ?? _asset;
  }

  @override
  Future<CompleteDrawingResponseDto> completeDrawing(
    int sessionId, {
    BinaryUploadDto? image,
    int? lastEventSequence,
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
  Future<DrawingSessionDto> getSession(int sessionId) =>
      throw UnimplementedError();
  @override
  Future<DrawingTypePage> getDrawingTypes({int? childId, String? ageGroup}) =>
      throw UnimplementedError();
  @override
  Future<AnalysisAcceptedDto> requestAnalysis(
    int sessionId,
    RequestAnalysisDto request, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  }) => throw UnimplementedError();
}
