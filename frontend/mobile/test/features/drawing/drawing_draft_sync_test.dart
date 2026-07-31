import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dodam/core/network/network.dart';
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
    final key = repository.draftIdempotencyKeys.single;
    expect(key, matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
    expect(key.length, inInclusiveRange(8, 100));
  });

  test('Draft 실패는 입력을 막지 않고 retry 후 성공할 수 있다', () async {
    final repository = _FakeDrawingRepository(saveError: StateError('store'));
    var nextKey = 0;
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      idempotencyKeyProvider: () => 'draft-key-${++nextKey}'.padRight(16, '0'),
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
    expect(repository.draftCalls, 3);
    expect(
      identical(repository.draftPreviews.first, repository.draftPreviews[1]),
      isTrue,
    );
    expect(
      identical(
        repository.draftCanvasStates.first,
        repository.draftCanvasStates[1],
      ),
      isTrue,
    );
    expect(repository.draftCanvasStates[1].lastEventSequence, 2);
    expect(
      repository.draftCanvasStates[1].clientSavedAt,
      repository.draftCanvasStates.first.clientSavedAt,
    );
    expect(repository.draftCanvasStates.last.lastEventSequence, 4);
    expect(repository.draftIdempotencyKeys, [
      repository.draftIdempotencyKeys.first,
      repository.draftIdempotencyKeys.first,
      isNot(repository.draftIdempotencyKeys.first),
    ]);
  });

  for (final scenario in <({String name, Object failure})>[
    (
      name: 'network',
      failure: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    ),
    (
      name: 'timeout',
      failure: const ApiTransportFailure(
        type: ApiTransportFailureType.receiveTimeout,
      ),
    ),
    (name: '5xx', failure: ApiResponseFailure(statusCode: 503, error: null)),
  ]) {
    test('${scenario.name} 뒤 수동 재시도는 key·bytes·canvasState를 그대로 쓴다', () async {
      final mutableBytes = <int>[1, 2, 3, 4];
      var captures = 0;
      final repository = _FakeDrawingRepository(saveErrors: [scenario.failure]);
      final coordinator = DrawingSyncCoordinator(
        sessionId: 42,
        repository: repository,
        now: () => DateTime.utc(2026, 7, 31, 1, 2, 3),
        idempotencyKeyProvider: () => 'draft-retry-key-0001',
      );
      addTearDown(coordinator.dispose);
      coordinator.recordStroke(_stroke(), const Size(100, 100));
      coordinator.start(
        snapshotProvider: () async {
          captures += 1;
          return BinaryUploadDto(
            bytes: mutableBytes,
            fileName: 'draft.png',
            mimeType: 'image/png',
          );
        },
      );

      await coordinator.saveDraftNow();
      mutableBytes[0] = 99;
      expect(coordinator.canRetrySave, isTrue);
      await coordinator.retry();

      expect(repository.draftCalls, 2);
      expect(captures, 1);
      expect(repository.draftIdempotencyKeys, [
        'draft-retry-key-0001',
        'draft-retry-key-0001',
      ]);
      expect(repository.draftPreviews[0].bytes, [1, 2, 3, 4]);
      expect(repository.draftPreviews[1].bytes, [1, 2, 3, 4]);
      expect(
        identical(repository.draftPreviews[0], repository.draftPreviews[1]),
        isTrue,
      );
      expect(
        identical(
          repository.draftCanvasStates[0],
          repository.draftCanvasStates[1],
        ),
        isTrue,
      );
      expect(repository.draftCanvasStates[0].lastEventSequence, 2);
      expect(
        repository.draftCanvasStates[0].clientSavedAt,
        '2026-07-31T01:02:03.000Z',
      );
    });
  }

  test('cancelled 뒤 수동 재시도도 동일 request identity를 유지한다', () async {
    final repository = _FakeDrawingRepository(
      saveErrors: const [
        ApiTransportFailure(type: ApiTransportFailureType.cancelled),
      ],
    );
    var captures = 0;
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      idempotencyKeyProvider: () => 'draft-cancel-key-0001',
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(
      snapshotProvider: () async {
        captures += 1;
        return _png;
      },
    );

    await coordinator.saveDraftNow();
    expect(coordinator.canRetrySave, isTrue);
    await coordinator.retry();

    expect(captures, 1);
    expect(repository.draftIdempotencyKeys, [
      'draft-cancel-key-0001',
      'draft-cancel-key-0001',
    ]);
    expect(
      identical(repository.draftPreviews[0], repository.draftPreviews[1]),
      isTrue,
    );
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('DRAFT_SAVE_IN_PROGRESS는 bounded backoff 동안 동일 snapshot을 쓴다', () async {
    final processing = _draftFailure('DRAFT_SAVE_IN_PROGRESS');
    final repository = _FakeDrawingRepository(
      saveErrors: [processing, processing],
    );
    var captures = 0;
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      policy: const DrawingSyncPolicy(draftProcessingBackoff: Duration.zero),
      idempotencyKeyProvider: () => 'draft-processing-key-0001',
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(
      snapshotProvider: () async {
        captures += 1;
        return _png;
      },
    );

    await coordinator.saveDraftNow();

    expect(repository.draftCalls, 3);
    expect(captures, 1);
    expect(
      repository.draftIdempotencyKeys,
      everyElement('draft-processing-key-0001'),
    );
    expect(
      repository.draftPreviews.every(
        (preview) => identical(preview, repository.draftPreviews.first),
      ),
      isTrue,
    );
    expect(
      repository.draftCanvasStates.every(
        (state) => identical(state, repository.draftCanvasStates.first),
      ),
      isTrue,
    );
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('processing retry 상한 뒤 동일 snapshot을 수동 재시도용으로 남긴다', () async {
    final processing = _draftFailure('DRAFT_SAVE_IN_PROGRESS');
    final repository = _FakeDrawingRepository(
      saveErrors: [processing, processing, processing],
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      policy: const DrawingSyncPolicy(
        maxDraftProcessingRetries: 2,
        draftProcessingBackoff: Duration.zero,
      ),
      idempotencyKeyProvider: () => 'draft-processing-key-0002',
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.saveDraftNow();
    expect(repository.draftCalls, 3);
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    expect(coordinator.canRetrySave, isTrue);

    await coordinator.retry();

    expect(repository.draftCalls, 4);
    expect(
      repository.draftIdempotencyKeys,
      everyElement('draft-processing-key-0002'),
    );
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  for (final failure in [
    (status: 409, code: 'IDEMPOTENCY_KEY_REUSED'),
    (status: 400, code: 'DRAWING_400_003'),
    (status: 400, code: 'DRAWING_400_004'),
  ]) {
    test('${failure.code}는 자동·수동 재시도를 차단한다', () async {
      final repository = _FakeDrawingRepository(
        saveError: _draftFailure(failure.code, statusCode: failure.status),
      );
      final coordinator = DrawingSyncCoordinator(
        sessionId: 42,
        repository: repository,
        policy: const DrawingSyncPolicy(draftProcessingBackoff: Duration.zero),
        idempotencyKeyProvider: () => 'draft-invalid-key-0001',
      );
      addTearDown(coordinator.dispose);
      coordinator.recordStroke(_stroke(), const Size(100, 100));
      coordinator.start(snapshotProvider: () async => _png);

      await coordinator.saveDraftNow();
      await coordinator.retry();

      expect(repository.draftCalls, 1);
      expect(coordinator.saveStatus, DrawingSaveStatus.failed);
      expect(coordinator.canRetrySave, isFalse);
    });
  }

  for (final statusCode in [401, 403, 404, 422]) {
    test('HTTP $statusCode Draft 실패는 재시도를 차단한다', () async {
      final repository = _FakeDrawingRepository(
        saveError: ApiResponseFailure(statusCode: statusCode, error: null),
      );
      final coordinator = DrawingSyncCoordinator(
        sessionId: 42,
        repository: repository,
        idempotencyKeyProvider: () => 'draft-client-error-key',
      );
      addTearDown(coordinator.dispose);
      coordinator.recordStroke(_stroke(), const Size(100, 100));
      coordinator.start(snapshotProvider: () async => _png);

      await coordinator.saveDraftNow();
      await coordinator.retry();

      expect(repository.draftCalls, 1);
      expect(coordinator.canRetrySave, isFalse);
    });
  }

  test('정확히 10MiB preview는 저장 요청을 허용한다', () async {
    final repository = _FakeDrawingRepository();
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      idempotencyKeyProvider: () => 'draft-size-key-0001',
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(
      snapshotProvider: () async => BinaryUploadDto(
        bytes: List<int>.filled(kMaxDraftPreviewBytes, 0),
        fileName: 'draft.png',
        mimeType: 'image/png',
      ),
    );

    await coordinator.saveDraftNow();

    expect(repository.draftCalls, 1);
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('10MiB+1 preview는 API 없이 비재시도 실패로 보존한다', () async {
    final repository = _FakeDrawingRepository();
    var captures = 0;
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      idempotencyKeyProvider: () => 'draft-size-key-0002',
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(
      snapshotProvider: () async {
        captures += 1;
        return BinaryUploadDto(
          bytes: List<int>.filled(kMaxDraftPreviewBytes + 1, 0),
          fileName: 'draft.png',
          mimeType: 'image/png',
        );
      },
    );

    await coordinator.saveDraftNow();
    await coordinator.retry();

    expect(captures, 1);
    expect(repository.draftCalls, 0);
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    expect(coordinator.canRetrySave, isFalse);
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

  test('autosave와 lifecycle 저장이 겹쳐도 Draft 요청은 하나만 보낸다', () async {
    final pending = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(saveCompleter: pending);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    final autosave = coordinator.saveDraftNow();
    final lifecycle = coordinator.flushAndSaveDraft();
    await Future<void>.delayed(Duration.zero);

    expect(repository.draftCalls, 1);
    pending.complete(_draftSaveResponse);
    await Future.wait([autosave, lifecycle]);
    expect(repository.draftCalls, 1);
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('저장 중 새 stroke는 현재 성공 뒤 최신 generation으로 다시 저장한다', () async {
    final firstSave = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(saveCompleter: firstSave);
    var nextKey = 0;
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      idempotencyKeyProvider: () => 'draft-success-key-${++nextKey}',
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    final saving = coordinator.saveDraftNow();
    await Future<void>.delayed(Duration.zero);
    coordinator.recordStroke(_stroke(t: 40), const Size(100, 100));
    expect(coordinator.saveStatus, DrawingSaveStatus.saving);

    firstSave.complete(_draftSaveResponse);
    await saving;

    expect(repository.draftCalls, 2);
    expect(
      repository.draftCanvasStates.map((state) => state.lastEventSequence),
      [2, 4],
    );
    expect(repository.draftIdempotencyKeys, [
      'draft-success-key-1',
      'draft-success-key-2',
    ]);
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('이전 generation network 실패는 최신 dirty를 실패로 표시하지 않고 후속 저장한다', () async {
    final firstSave = Completer<DraftSaveResponseDto>();
    final secondSave = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(
      saveCompleters: [firstSave, secondSave],
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    final saving = coordinator.saveDraftNow();
    await Future<void>.delayed(Duration.zero);
    coordinator.recordStroke(_stroke(t: 40), const Size(100, 100));
    firstSave.completeError(
      const ApiTransportFailure(type: ApiTransportFailureType.connection),
    );
    await _waitFor(() => repository.draftCalls == 2);

    expect(coordinator.saveStatus, DrawingSaveStatus.saving);
    secondSave.complete(_draftSaveResponse);
    await saving;

    expect(
      repository.draftCanvasStates.map((state) => state.lastEventSequence),
      [2, 4],
    );
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('이전 generation 영구 실패도 새 dirty의 다음 저장을 막지 않는다', () async {
    final firstSave = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(saveCompleters: [firstSave]);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    final first = coordinator.saveDraftNow();
    await Future<void>.delayed(Duration.zero);
    coordinator.recordStroke(_stroke(t: 40), const Size(100, 100));
    firstSave.completeError(ApiResponseFailure(statusCode: 403, error: null));
    await first;

    expect(coordinator.saveStatus, DrawingSaveStatus.localOnly);
    await coordinator.saveDraftNow();

    expect(repository.draftCalls, 2);
    expect(repository.draftCanvasStates.last.lastEventSequence, 4);
    expect(coordinator.saveStatus, DrawingSaveStatus.saved);
  });

  test('409_009는 최신 metadata를 조회하지만 sequence만으로 성공 처리하지 않는다', () async {
    final repository = _FakeDrawingRepository(
      saveError: _draftConflict('DRAWING_409_009'),
      latestDraft: _draftRecovery,
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.saveDraftNow();

    expect(repository.getDraftCalls, 1);
    expect(repository.downloadDraftPreviewCalls, 0);
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    expect(coordinator.canRetrySave, isFalse);
  });

  test(
    '응답 유실 뒤 동일 snapshot 재시도 409_009도 identity 계약 없이는 성공 처리하지 않는다',
    () async {
      final repository = _FakeDrawingRepository(
        saveErrors: [
          const ApiTransportFailure(type: ApiTransportFailureType.connection),
          _draftConflict('DRAWING_409_009'),
        ],
        latestDraft: _draftRecovery,
      );
      final coordinator = DrawingSyncCoordinator(
        sessionId: 42,
        repository: repository,
      );
      addTearDown(coordinator.dispose);
      coordinator.recordStroke(_stroke(), const Size(100, 100));
      coordinator.start(snapshotProvider: () async => _png);

      await coordinator.saveDraftNow();
      expect(coordinator.canRetrySave, isTrue);
      await coordinator.retry();

      expect(repository.draftCalls, 2);
      expect(repository.getDraftCalls, 1);
      expect(repository.downloadDraftPreviewCalls, 0);
      expect(
        identical(repository.draftPreviews[0], repository.draftPreviews[1]),
        isTrue,
      );
      expect(
        identical(
          repository.draftCanvasStates[0],
          repository.draftCanvasStates[1],
        ),
        isTrue,
      );
      expect(coordinator.saveStatus, DrawingSaveStatus.failed);
      expect(coordinator.canRetrySave, isFalse);
    },
  );

  test('409 reconciliation metadata 조회 실패도 원래 PUT을 성공 처리하지 않는다', () async {
    final repository = _FakeDrawingRepository(
      saveError: _draftConflict('DRAWING_409_009'),
      draftError: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.saveDraftNow();

    expect(repository.getDraftCalls, 1);
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    expect(coordinator.canRetrySave, isFalse);
  });

  test(
    '409 reconciliation 중 새 stroke는 dirty로 남아 새 sequence로 저장할 수 있다',
    () async {
      final pendingDraft = Completer<DraftRecoveryDto?>();
      final repository = _FakeDrawingRepository(
        saveError: _draftConflict('DRAWING_409_009'),
        draftCompleter: pendingDraft,
      );
      final coordinator = DrawingSyncCoordinator(
        sessionId: 42,
        repository: repository,
      );
      addTearDown(coordinator.dispose);
      coordinator.recordStroke(_stroke(), const Size(100, 100));
      coordinator.start(snapshotProvider: () async => _png);

      final first = coordinator.saveDraftNow();
      await _waitFor(() => repository.getDraftCalls == 1);
      coordinator.recordStroke(_stroke(t: 40), const Size(100, 100));
      pendingDraft.complete(_draftRecovery);
      await first;

      expect(coordinator.saveStatus, DrawingSaveStatus.localOnly);
      repository.saveError = null;
      await coordinator.saveDraftNow();

      expect(repository.draftCalls, 2);
      expect(repository.draftCanvasStates.last.lastEventSequence, 4);
      expect(coordinator.saveStatus, DrawingSaveStatus.saved);
    },
  );

  test('409_010은 최신 metadata를 조회하고 stale snapshot을 자동 재시도하지 않는다', () async {
    final repository = _FakeDrawingRepository(
      saveError: _draftConflict('DRAWING_409_010'),
      latestDraft: _draftRecovery,
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.saveDraftNow();
    await coordinator.retry();

    expect(repository.draftCalls, 1);
    expect(repository.getDraftCalls, 1);
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
  });

  test('일반 409는 Draft sequence reconciliation 조회를 하지 않는다', () async {
    final repository = _FakeDrawingRepository(
      saveError: ApiResponseFailure(
        statusCode: 409,
        error: ApiError(
          timestamp: '2026-07-22T00:00:00Z',
          path: '/api/v1/drawing-sessions/42/draft',
          code: 'DRAWING_409_011',
          message: 'conflict',
        ),
      ),
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.saveDraftNow();

    expect(repository.getDraftCalls, 0);
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
  });

  test('409 reconciliation 조회 중 dispose하면 늦은 metadata를 상태에 반영하지 않는다', () async {
    final pendingDraft = Completer<DraftRecoveryDto?>();
    final repository = _FakeDrawingRepository(
      saveError: _draftConflict('DRAWING_409_009'),
      draftCompleter: pendingDraft,
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    var notifications = 0;
    coordinator.addListener(() => notifications += 1);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);
    final saving = coordinator.saveDraftNow();
    await _waitFor(() => repository.getDraftCalls == 1);
    final notificationsAtDispose = notifications;

    coordinator.dispose();
    pendingDraft.complete(_draftRecovery);
    await saving;

    expect(notifications, notificationsAtDispose);
  });

  test('동시 flush는 같은 batch 전송을 기다리고 Draft보다 먼저 끝난다', () async {
    final pendingBatch = Completer<StrokeBatchResponseDto>();
    final repository = _FakeDrawingRepository(strokeCompleter: pendingBatch);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    final first = coordinator.flushAndSaveDraft();
    final second = coordinator.flushAndSaveDraft();
    await Future<void>.delayed(Duration.zero);

    expect(repository.strokeCalls, 1);
    expect(repository.draftCalls, 0);
    pendingBatch.complete(_strokeBatchResponse);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(repository.calls, ['stroke', 'draft']);
  });

  test('dispose 뒤 첫 batch가 끝나도 queued batch를 추가 전송하지 않는다', () async {
    final firstBatch = Completer<StrokeBatchResponseDto>();
    final repository = _FakeDrawingRepository(strokeCompleter: firstBatch);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    final firstFlush = coordinator.flushEvents();
    await Future<void>.delayed(Duration.zero);
    coordinator.recordStroke(_stroke(t: 40), const Size(100, 100));
    final secondFlush = coordinator.flushEvents();
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.batchQueue.pendingBatches, hasLength(2));

    coordinator.dispose();
    firstBatch.complete(_strokeBatchResponse);
    await Future.wait([firstFlush, secondFlush]);

    expect(repository.strokeCalls, 1);
    await coordinator.batchQueue.retryHead();
    expect(repository.strokeCalls, 1);
  });

  test('dispose하지 않은 queue는 첫 batch 뒤 queued batch를 정상 drain한다', () async {
    final firstBatch = Completer<StrokeBatchResponseDto>();
    final repository = _FakeDrawingRepository(strokeCompleter: firstBatch);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    final firstFlush = coordinator.flushEvents();
    await Future<void>.delayed(Duration.zero);
    coordinator.recordStroke(_stroke(t: 40), const Size(100, 100));
    final secondFlush = coordinator.flushEvents();

    firstBatch.complete(_strokeBatchResponse);
    await Future.wait([firstFlush, secondFlush]);

    expect(repository.strokeCalls, 2);
    expect(repository.strokeBatchSequences, [1, 2]);
  });

  test('영구 batch 오류이면 Draft를 보내지 않고 retry를 제공하지 않는다', () async {
    final repository = _FakeDrawingRepository(
      strokeError: ApiResponseFailure(statusCode: 409, error: null),
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    expect(await coordinator.flushAndSaveDraft(), isFalse);

    expect(repository.strokeCalls, 1);
    expect(repository.draftCalls, 0);
    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    expect(coordinator.canRetrySave, isFalse);
  });

  test('영구 Draft 오류이면 retry를 숨기고 Canvas 입력은 유지한다', () async {
    final repository = _FakeDrawingRepository(
      saveError: ApiResponseFailure(statusCode: 403, error: null),
    );
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);

    await coordinator.saveDraftNow();

    expect(coordinator.saveStatus, DrawingSaveStatus.failed);
    expect(coordinator.canRetrySave, isFalse);
    final before = coordinator.journal.events.length;
    coordinator.recordStroke(_stroke(t: 50), const Size(100, 100));
    expect(coordinator.journal.events.length, greaterThan(before));
  });

  test('dispose 뒤 늦은 Draft 성공은 상태 알림을 발생시키지 않는다', () async {
    final pending = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(saveCompleter: pending);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
    );
    var notifications = 0;
    coordinator.addListener(() => notifications += 1);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);
    final saving = coordinator.saveDraftNow();
    await Future<void>.delayed(Duration.zero);
    final notificationsAtDispose = notifications;

    coordinator.dispose();
    pending.complete(_draftSaveResponse);
    await saving;

    expect(coordinator.isDisposed, isTrue);
    expect(notifications, notificationsAtDispose);
  });

  test('dispose 뒤 DRAFT_SAVE_IN_PROGRESS 응답은 retry·notify를 만들지 않는다', () async {
    final pending = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(saveCompleter: pending);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      policy: const DrawingSyncPolicy(draftProcessingBackoff: Duration.zero),
      idempotencyKeyProvider: () => 'draft-dispose-key-0001',
    );
    var notifications = 0;
    coordinator.addListener(() => notifications += 1);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);
    final saving = coordinator.saveDraftNow();
    await _waitFor(() => repository.draftCalls == 1);
    final notificationsAtDispose = notifications;

    coordinator.dispose();
    pending.completeError(_draftFailure('DRAFT_SAVE_IN_PROGRESS'));
    await saving;

    expect(repository.draftCalls, 1);
    expect(notifications, notificationsAtDispose);
  });

  test('completion barrier 중 processing 응답은 Draft retry를 시작하지 않는다', () async {
    final pending = Completer<DraftSaveResponseDto>();
    final repository = _FakeDrawingRepository(saveCompleter: pending);
    final coordinator = DrawingSyncCoordinator(
      sessionId: 42,
      repository: repository,
      policy: const DrawingSyncPolicy(draftProcessingBackoff: Duration.zero),
      idempotencyKeyProvider: () => 'draft-completion-key-0001',
    );
    addTearDown(coordinator.dispose);
    coordinator.recordStroke(_stroke(), const Size(100, 100));
    coordinator.start(snapshotProvider: () async => _png);
    final saving = coordinator.saveDraftNow();
    await _waitFor(() => repository.draftCalls == 1);

    final completion = coordinator.beginCompletion();
    pending.completeError(_draftFailure('DRAFT_SAVE_IN_PROGRESS'));
    await Future.wait([saving, completion]);
    await coordinator.retry();

    expect(repository.draftCalls, 1);
    expect(coordinator.isCompleting, isTrue);
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

const _strokeBatchResponse = StrokeBatchResponseDto(
  batchId: 1,
  batchSequence: 1,
  acceptedEventCount: 1,
  lastEventSequence: 2,
  receivedAt: '2026-07-22T00:00:00Z',
);

const _draftRecovery = DraftRecoveryDto(
  previewUrl: '/api/v1/drawing-assets/1/file',
  canvasState: DraftCanvasStateDto(
    lastEventSequence: 2,
    toolState: null,
    viewport: null,
    clientSavedAt: '2026-07-22T00:00:00Z',
  ),
  assetVersion: 1,
);

ApiResponseFailure _draftConflict(String code) => ApiResponseFailure(
  statusCode: 409,
  error: ApiError(
    timestamp: '2026-07-22T00:00:00Z',
    path: '/api/v1/drawing-sessions/42/draft',
    code: code,
    message: 'conflict',
  ),
);

ApiResponseFailure _draftFailure(String code, {int statusCode = 409}) =>
    ApiResponseFailure(
      statusCode: statusCode,
      error: ApiError(
        timestamp: '2026-07-22T00:00:00Z',
        path: '/api/v1/drawing-sessions/42/draft',
        code: code,
        message: 'draft failure',
      ),
    );

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not met');
}

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
  _FakeDrawingRepository({
    this.saveCompleter,
    this.saveError,
    this.strokeCompleter,
    this.strokeError,
    List<Completer<DraftSaveResponseDto>> saveCompleters = const [],
    List<Object> saveErrors = const [],
    this.latestDraft,
    this.draftCompleter,
    this.draftError,
  }) : _saveCompleters = List.of(saveCompleters),
       _saveErrors = List.of(saveErrors);

  Completer<DraftSaveResponseDto>? saveCompleter;
  Object? saveError;
  Completer<StrokeBatchResponseDto>? strokeCompleter;
  Object? strokeError;
  final List<Completer<DraftSaveResponseDto>> _saveCompleters;
  final List<Object> _saveErrors;
  final DraftRecoveryDto? latestDraft;
  final Completer<DraftRecoveryDto?>? draftCompleter;
  final Object? draftError;
  int strokeCalls = 0;
  int draftCalls = 0;
  int getDraftCalls = 0;
  int downloadDraftPreviewCalls = 0;
  int? lastEventSequence;
  final List<String> calls = [];
  final List<int> strokeBatchSequences = [];
  final List<BinaryUploadDto> draftPreviews = [];
  final List<DraftCanvasStateDto> draftCanvasStates = [];
  final List<String> draftIdempotencyKeys = [];

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async {
    strokeCalls += 1;
    calls.add('stroke');
    strokeBatchSequences.add(request.batchSequence);
    if (strokeError case final error?) throw error;
    return strokeCompleter?.future ??
        StrokeBatchResponseDto(
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
    DraftCanvasStateDto canvasState, {
    required String idempotencyKey,
  }) async {
    draftCalls += 1;
    calls.add('draft');
    lastEventSequence = canvasState.lastEventSequence;
    draftPreviews.add(preview);
    draftCanvasStates.add(canvasState);
    draftIdempotencyKeys.add(idempotencyKey);
    if (_saveErrors.isNotEmpty) throw _saveErrors.removeAt(0);
    if (saveError case final error?) throw error;
    if (_saveCompleters.isNotEmpty) {
      return _saveCompleters.removeAt(0).future;
    }
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
  Future<void> deleteDraft(int sessionId) => throw UnimplementedError();
  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) {
    getDraftCalls += 1;
    if (draftError case final error?) return Future.error(error);
    return draftCompleter?.future ?? Future.value(latestDraft);
  }

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;
  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) async {
    downloadDraftPreviewCalls += 1;
    return Uint8List.fromList(_png.bytes);
  }

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
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
  }) => throw UnimplementedError();
}
