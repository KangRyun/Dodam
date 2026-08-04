import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_document_controller.dart';
import 'package:dodam/features/drawing/application/drawing_draft_restore_controller.dart';
import 'package:dodam/features/drawing/application/drawing_event_journal.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_canvas_action.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_tool_state.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas_viewport.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_cursor_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'stroke eraser removes every intersected pen stroke as one snapshot-only undo group',
    (tester) async {
      final harness = await _pumpScreen(tester);
      _addSyncedStroke(harness, const Offset(460, 350));
      _addSyncedStroke(harness, const Offset(460, 390));
      await tester.pump();
      final eventCountBeforeErase = harness.sync.journal.events.length;

      await _selectEraserMode(tester, DrawingEraserMode.stroke);
      final canvasRect = tester.getRect(
        find.byKey(const ValueKey('drawing-canvas')),
      );
      final gesture = await tester.startGesture(
        canvasRect.center - const Offset(0, 30),
        kind: ui.PointerDeviceKind.mouse,
      );
      await gesture.moveTo(canvasRect.center + const Offset(0, 5));
      await gesture.moveTo(canvasRect.center + const Offset(0, 30));
      await gesture.up();
      await _pumpUntil(tester, () => harness.repository.draftCalls == 1);

      expect(harness.document.visibleStrokes, isEmpty);
      expect(harness.sync.journal.events, hasLength(eventCountBeforeErase));
      expect(harness.repository.draftCalls, 1);
      expect(harness.document.canUndo, isTrue);

      harness.document.undo();
      expect(harness.document.visibleStrokes, hasLength(2));
    },
  );

  testWidgets(
    'pen input remains usable during a stroke-erase snapshot upload',
    (tester) async {
      final harness = await _pumpScreen(tester, holdDraft: true);
      _addSyncedStroke(harness, const Offset(460, 350));
      _addSyncedStroke(harness, const Offset(460, 390));
      await tester.pump();
      await _selectEraserMode(tester, DrawingEraserMode.stroke);
      final canvasRect = tester.getRect(
        find.byKey(const ValueKey('drawing-canvas')),
      );
      final eraser = await tester.startGesture(
        canvasRect.center - const Offset(0, 30),
        kind: ui.PointerDeviceKind.mouse,
      );
      await eraser.moveTo(canvasRect.center + const Offset(0, 5));
      await eraser.moveTo(canvasRect.center + const Offset(0, 30));
      await eraser.up();
      await _pumpUntil(tester, () => harness.repository.draftCalls == 1);

      await tester.tap(find.byKey(const ValueKey('drawing-tool-pen')));
      await tester.pump();
      final pen = await tester.startGesture(
        canvasRect.center + const Offset(-100, 80),
        kind: ui.PointerDeviceKind.mouse,
      );
      await pen.moveBy(const Offset(80, 0));
      await pen.up();
      await tester.pump();

      expect(harness.document.visibleStrokes, hasLength(1));
      expect(harness.document.visibleStrokes.single.tool, DrawingTool.pen);
      expect(harness.sync.journal.events, hasLength(6));

      harness.repository.completeHeldDraft(0);
      await _pumpUntil(tester, () => harness.repository.draftCalls == 2);
      harness.repository.completeHeldDraft(1);
      await _pumpUntil(tester, () => !harness.sync.hasUnsavedSnapshot);
    },
  );

  testWidgets('area eraser records every drag point as one ERASER stroke', (
    tester,
  ) async {
    final harness = await _pumpScreen(tester);
    await _selectEraserMode(tester, DrawingEraserMode.area);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-canvas')),
    );

    final gesture = await tester.startGesture(
      canvasRect.center - const Offset(40, 0),
      kind: ui.PointerDeviceKind.mouse,
    );
    await gesture.moveTo(canvasRect.center);
    await gesture.moveTo(canvasRect.center + const Offset(40, 0));
    await gesture.up();
    await tester.pump();

    final events = harness.sync.journal.events;
    expect(events.map((event) => event.type), [
      DrawingEventTypes.strokeStart,
      DrawingEventTypes.strokeMove,
      DrawingEventTypes.strokeEnd,
    ]);
    expect(events.first.tool, 'ERASER');
    expect(harness.document.visibleStrokes.single.tool, DrawingTool.eraser);
    expect(harness.document.hasVisibleContent, isFalse);
  });

  testWidgets('fill adds a snapshot-only action and immediately saves it', (
    tester,
  ) async {
    final harness = await _pumpScreen(tester);
    final fill = find.byKey(const ValueKey('drawing-tool-fill'));
    await tester.ensureVisible(fill);
    await tester.tap(fill);
    await tester.pump();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('drawing-canvas'))),
    );
    await _pumpUntil(
      tester,
      () =>
          harness.repository.draftCalls == 1 &&
          !harness.sync.hasUnsavedSnapshot,
    );

    expect(harness.document.actions, hasLength(1));
    expect(harness.document.actions.single, isA<DrawingFillAction>());
    expect(harness.sync.journal.events, isEmpty);
    expect(harness.sync.documentRevision, 1);
    expect(harness.sync.hasUnsavedSnapshot, isFalse);
  });

  testWidgets(
    'stroke eraser falls back to a continuous area eraser over restored pixels',
    (tester) async {
      final harness = await _pumpScreen(tester, restoreDraft: true);
      expect(harness.restore.backgroundImage, isNotNull);

      await _selectEraserMode(tester, DrawingEraserMode.stroke);
      final canvasRect = tester.getRect(
        find.byKey(const ValueKey('drawing-canvas')),
      );
      final gesture = await tester.startGesture(
        canvasRect.center - const Offset(30, 0),
        kind: ui.PointerDeviceKind.mouse,
      );
      await gesture.moveTo(canvasRect.center);
      await gesture.moveTo(canvasRect.center + const Offset(30, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('area-eraser-cursor')), findsOneWidget);
      await gesture.up();
      await _pumpUntil(tester, () => harness.repository.draftCalls == 1);

      final events = harness.sync.journal.events;
      expect(events.map((event) => event.type), [
        DrawingEventTypes.strokeStart,
        DrawingEventTypes.strokeMove,
        DrawingEventTypes.strokeEnd,
      ]);
      expect(events.first.tool, 'ERASER');
      expect(harness.document.visibleStrokes.single.tool, DrawingTool.eraser);
      expect(harness.restore.backgroundImage, isNotNull);
    },
  );

  testWidgets('pointer cancel rolls back a stroke-erasure gesture', (
    tester,
  ) async {
    final harness = await _pumpScreen(tester);
    _addSyncedStroke(harness, const Offset(460, 370));
    await tester.pump();
    final eventCountBeforeCancel = harness.sync.journal.events.length;

    await _selectEraserMode(tester, DrawingEraserMode.stroke);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(
      center,
      kind: ui.PointerDeviceKind.mouse,
    );
    await gesture.cancel();
    await tester.pump();

    expect(harness.document.visibleStrokes, hasLength(1));
    expect(harness.sync.journal.events, hasLength(eventCountBeforeCancel));
    expect(harness.repository.draftCalls, 0);
  });

  testWidgets(
    'metrics change cancels stroke erasure and releases its mutation guard',
    (tester) async {
      final harness = await _pumpScreen(tester);
      _addSyncedStroke(harness, const Offset(460, 350));
      await tester.pump();
      await _selectEraserMode(tester, DrawingEraserMode.stroke);
      final center = tester.getCenter(
        find.byKey(const ValueKey('drawing-canvas')),
      );
      final interruptedGesture = await tester.startGesture(
        center - const Offset(0, 30),
        pointer: 71,
        kind: ui.PointerDeviceKind.mouse,
      );
      addTearDown(interruptedGesture.cancel);
      await interruptedGesture.moveTo(center + const Offset(0, 5));
      await tester.pump();
      expect(harness.document.visibleStrokes, isEmpty);

      tester.view.physicalSize = const Size(1000, 700);
      await tester.pump();

      expect(harness.document.visibleStrokes, hasLength(1));
      await _selectEraserMode(tester, DrawingEraserMode.area);
      final resizedCenter = tester.getCenter(
        find.byKey(const ValueKey('drawing-canvas')),
      );
      final nextGesture = await tester.startGesture(
        resizedCenter - const Offset(20, 0),
        pointer: 73,
        kind: ui.PointerDeviceKind.mouse,
      );
      await nextGesture.moveTo(resizedCenter + const Offset(20, 0));
      await nextGesture.up();
      await tester.pump();

      expect(
        harness.document.visibleStrokes
            .where((stroke) => stroke.tool == DrawingTool.eraser),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'clear-all waits for confirmation then clears actions redo and restored pixels and saves blank',
    (tester) async {
      final harness = await _pumpScreen(tester, restoreDraft: true);
      _addSyncedStroke(harness, const Offset(460, 350));
      _addSyncedStroke(harness, const Offset(460, 390));
      final undone = harness.document.undo();
      expect(undone.changed, isTrue);
      harness.sync.recordUndo();
      await tester.pump();
      final cutoffBeforeClear = harness.sync.journal.lastEventSequence;

      await _openClearConfirmation(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(harness.document.actions, isNotEmpty);
      expect(harness.document.canRedo, isTrue);
      expect(harness.restore.backgroundImage, isNotNull);

      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(AppButton),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(harness.document.actions, isNotEmpty);
      expect(harness.restore.backgroundImage, isNotNull);
      expect(harness.repository.draftCalls, 0);

      await _openClearConfirmation(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(AppButton),
            )
            .last,
      );
      await _pumpUntil(tester, () => harness.repository.draftCalls == 1);

      expect(harness.document.actions, isEmpty);
      expect(harness.document.canUndo, isFalse);
      expect(harness.document.canRedo, isFalse);
      expect(harness.restore.backgroundImage, isNull);
      expect(
        find.byKey(const ValueKey('draft-background-image')),
        findsNothing,
      );
      expect(harness.repository.lastEventSequence, cutoffBeforeClear);
      expect(harness.repository.savedPreview?.bytes, isNotEmpty);
    },
  );

  testWidgets('clear-all is a no-op when neither content source is visible', (
    tester,
  ) async {
    final harness = await _pumpScreen(tester);

    await _openClearConfirmation(tester);
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(AppButton),
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(harness.repository.draftCalls, 0);
    expect(harness.sync.journal.events, isEmpty);
  });

  testWidgets('both eraser cursors use the selected document width', (
    tester,
  ) async {
    await _pumpScreen(tester);
    // 가장 굵은 프리셋을 키로 직접 고른다. 순서에 기대면 툴바 배치가 바뀔 때
    // 슬라이더나 미리보기를 누르게 된다.
    final widthChoices = find.byKey(const ValueKey('drawing-thickness-굵게'));
    await tester.ensureVisible(widthChoices);
    await tester.tap(widthChoices);
    await tester.pump();

    await _selectEraserMode(tester, DrawingEraserMode.area);
    final areaPointer = TestPointer(91, PointerDeviceKind.mouse);
    await _hoverCanvas(tester, areaPointer);
    var overlay = tester.widget<DrawingCursorOverlay>(
      find.byType(DrawingCursorOverlay),
    );
    expect(find.byKey(const ValueKey('area-eraser-cursor')), findsOneWidget);
    expect(overlay.state.documentWidth, 14);
    await tester.sendEventToBinding(areaPointer.removePointer());

    await _selectEraserMode(tester, DrawingEraserMode.stroke);
    final strokePointer = TestPointer(93, PointerDeviceKind.mouse);
    await _hoverCanvas(tester, strokePointer);
    overlay = tester.widget<DrawingCursorOverlay>(
      find.byType(DrawingCursorOverlay),
    );
    expect(find.byKey(const ValueKey('stroke-eraser-cursor')), findsOneWidget);
    expect(overlay.state.documentWidth, 14);
    await tester.sendEventToBinding(strokePointer.removePointer());
  });
}

Future<_DrawingHarness> _pumpScreen(
  WidgetTester tester, {
  bool restoreDraft = false,
  bool holdDraft = false,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = _EraserRepository(
    holdDraft: holdDraft,
    recovery: restoreDraft
        ? const DraftRecoveryDto(
            previewUrl: 'https://example.test/restored.png',
            canvasState: DraftCanvasStateDto(
              lastEventSequence: 12,
              toolState: null,
              viewport: null,
              clientSavedAt: '2026-08-03T00:00:00Z',
            ),
            assetVersion: 4,
          )
        : null,
  );
  final sync = DrawingSyncCoordinator(sessionId: 42, repository: repository);
  final document = DrawingDocumentController();
  final restore = DrawingDraftRestoreController(
    sessionId: 42,
    repository: repository,
    syncCoordinator: sync,
    imageProviderFactory: (_) => MemoryImage(_validOnePixelPng),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '3',
        sessionId: 42,
        drawingRepository: repository,
        syncCoordinator: sync,
        documentController: document,
        draftRestoreController: restore,
        autoRestoreDraft: restoreDraft,
        startFresh: !restoreDraft,
      ),
    ),
  );
  if (restoreDraft) {
    await _pumpUntil(tester, () => restore.backgroundImage != null);
    restore.markImageLoaded();
  }
  await tester.pump();
  // 주기 autosave 만 멈춘다. stop() 은 완료 이후를 뜻해 명시적 저장까지 막으므로
  // 스냅샷 변경이 곧바로 저장되는지 보려면 pause() 여야 한다.
  sync.pause();

  addTearDown(() async {
    repository.completeAllHeldDrafts();
    await tester.pumpWidget(const SizedBox.shrink());
    restore.dispose();
    sync.dispose();
    document.dispose();
  });
  return _DrawingHarness(
    repository: repository,
    sync: sync,
    document: document,
    restore: restore,
  );
}

void _addSyncedStroke(_DrawingHarness harness, Offset start) {
  final change = harness.document.addStroke(_stroke(start));
  harness.sync.recordStroke(
    change.wireStroke!,
    DrawingCanvasGeometry.documentSize,
  );
}

Future<void> _selectEraserMode(
  WidgetTester tester,
  DrawingEraserMode mode,
) async {
  final eraser = find.byKey(const ValueKey('drawing-tool-eraser'));
  await tester.ensureVisible(eraser);
  await tester.tap(eraser);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      ValueKey(
        mode == DrawingEraserMode.stroke
            ? 'drawing-eraser-stroke'
            : 'drawing-eraser-area',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openClearConfirmation(WidgetTester tester) async {
  final eraser = find.byKey(const ValueKey('drawing-tool-eraser'));
  await tester.ensureVisible(eraser);
  await tester.tap(eraser);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('drawing-eraser-clear-all')));
  await tester.pumpAndSettle();
}

Future<void> _hoverCanvas(WidgetTester tester, TestPointer cursor) async {
  final center = tester.getCenter(find.byKey(const ValueKey('drawing-canvas')));
  await tester.sendEventToBinding(cursor.addPointer(location: center));
  await tester.sendEventToBinding(cursor.hover(center));
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(condition(), isTrue);
}

DrawingStroke _stroke(Offset start) => DrawingStroke(
  color: AppColors.drawingRed,
  thickness: 8,
  points: [
    DrawingPoint(position: start, elapsedMilliseconds: 10),
    DrawingPoint(
      position: start + const Offset(100, 0),
      elapsedMilliseconds: 20,
    ),
  ],
);

final class _DrawingHarness {
  const _DrawingHarness({
    required this.repository,
    required this.sync,
    required this.document,
    required this.restore,
  });

  final _EraserRepository repository;
  final DrawingSyncCoordinator sync;
  final DrawingDocumentController document;
  final DrawingDraftRestoreController restore;
}

final class _EraserRepository implements DrawingRepository {
  _EraserRepository({this.recovery, this.holdDraft = false});

  final DraftRecoveryDto? recovery;
  final bool holdDraft;
  int draftCalls = 0;
  BinaryUploadDto? savedPreview;
  int? lastEventSequence;
  final List<Completer<DraftSaveResponseDto>> _heldDrafts = [];

  void completeHeldDraft(int index) {
    if (_heldDrafts[index].isCompleted) return;
    _heldDrafts[index].complete(_draftResponse());
  }

  void completeAllHeldDrafts() {
    for (final completer in _heldDrafts) {
      if (!completer.isCompleted) completer.complete(_draftResponse());
    }
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async => recovery;

  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) async =>
      _validOnePixelPng;

  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState, {
    required String idempotencyKey,
  }) async {
    draftCalls += 1;
    savedPreview = preview;
    lastEventSequence = canvasState.lastEventSequence;
    if (holdDraft) {
      final completer = Completer<DraftSaveResponseDto>();
      _heldDrafts.add(completer);
      return completer.future;
    }
    return _draftResponse(canvasState.clientSavedAt);
  }

  DraftSaveResponseDto _draftResponse([String? clientSavedAt]) =>
      DraftSaveResponseDto(
        drawingAssetId: 1,
        assetVersion: draftCalls,
        lastEventSequence: lastEventSequence,
        savedAt: clientSavedAt ?? '2026-08-03T00:00:00Z',
        expiresAt: null,
      );

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async => StrokeBatchResponseDto(
    batchId: 1,
    batchSequence: request.batchSequence,
    acceptedEventCount: request.events.length,
    lastEventSequence: request.lastEventSequence,
    receivedAt: '2026-08-03T00:00:00Z',
  );

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;
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

final Uint8List _validOnePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);
