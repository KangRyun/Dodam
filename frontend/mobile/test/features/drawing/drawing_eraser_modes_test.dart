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
      _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, -34)));
      _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, 6)));
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
      // 획 지우개가 지운 결과는 여전히 event 로 표현되지 않는다. 새로 늘어난 하나는
      // 지우개를 고른 도구 전환뿐이다(S15P11B209-772 후속).
      final addedEvents = harness.sync.journal.events
          .skip(eventCountBeforeErase)
          .toList();
      expect(addedEvents.map((event) => event.type), [
        DrawingEventTypes.toolChange,
      ]);
      expect(addedEvents.single.tool, 'ERASER_STROKE');
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
      _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, -34)));
      _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, 6)));
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
      // 획 4개 + 지우개·크레용 도구 전환 2개.
      expect(harness.sync.journal.events, hasLength(8));
      expect(
        harness.sync.journal.events
            .where((event) => event.type == DrawingEventTypes.toolChange)
            .map((event) => event.tool),
        ['ERASER_STROKE', 'CRAYON'],
      );

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
    // 지우개를 고른 도구 전환이 획보다 먼저 굳는다. 메뉴를 여닫는 중간 값은 마지막
    // 하나로 합쳐져 TOOL_CHANGE 는 한 번만 남는다.
    expect(events.map((event) => event.type), [
      DrawingEventTypes.toolChange,
      DrawingEventTypes.strokeStart,
      DrawingEventTypes.strokeMove,
      DrawingEventTypes.strokeEnd,
    ]);
    expect(events.first.tool, 'ERASER');
    expect(events[1].tool, 'ERASER');
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
    // 채우기는 이미지를 통째로 바꾸지만 행동 자체는 FILL 이벤트로 남는다. 찍은 자리
    // 좌표와 고른 색을 함께 싣는다.
    final events = harness.sync.journal.events;
    expect(events.map((event) => event.type), [
      DrawingEventTypes.toolChange,
      DrawingEventTypes.fill,
    ]);
    expect(events.first.tool, 'FILL');
    expect(events.last.x, isNotNull);
    expect(events.last.y, isNotNull);
    expect(events.last.color, isNotNull);
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
        DrawingEventTypes.toolChange,
        DrawingEventTypes.strokeStart,
        DrawingEventTypes.strokeMove,
        DrawingEventTypes.strokeEnd,
      ]);
      expect(events.first.tool, 'ERASER_STROKE');
      expect(events[1].tool, 'ERASER');
      expect(harness.document.visibleStrokes.single.tool, DrawingTool.eraser);
      expect(harness.restore.backgroundImage, isNotNull);
    },
  );

  testWidgets('pointer cancel rolls back a stroke-erasure gesture', (
    tester,
  ) async {
    final harness = await _pumpScreen(tester);
    _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, -14)));
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
      _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, -34)));
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
        harness.document.visibleStrokes.where(
          (stroke) => stroke.tool == DrawingTool.eraser,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'clear-all waits for confirmation then clears actions redo and restored pixels and saves blank',
    (tester) async {
      final harness = await _pumpScreen(tester, restoreDraft: true);
      _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, -34)));
      _addSyncedStroke(harness, _nearCentre(tester, const Offset(-52, 6)));
      final undone = harness.document.undo();
      expect(undone.changed, isTrue);
      harness.sync.recordUndo();
      await tester.pump();

      await _openClearConfirmation(tester);
      expect(find.byType(DodamDialog), findsOneWidget);
      expect(harness.document.actions, isNotEmpty);
      expect(harness.document.canRedo, isTrue);
      expect(harness.restore.backgroundImage, isNotNull);

      await tester.tap(
        find
            .descendant(
              of: find.byType(DodamDialog),
              matching: find.byType(DodamDialogButton),
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
              of: find.byType(DodamDialog),
              matching: find.byType(DodamDialogButton),
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
      // 전체 지우기는 이제 CANVAS_CLEAR 이벤트를 남긴다. 초안의 replay cutoff 는
      // 그 이벤트까지 포함해야 이어그리기가 같은 순번을 다시 쓰지 않는다.
      final events = harness.sync.journal.events;
      expect(events.last.type, DrawingEventTypes.canvasClear);
      expect(harness.repository.lastEventSequence, events.last.seq);
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
            of: find.byType(DodamDialog),
            matching: find.byType(DodamDialogButton),
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
    // 굵기는 슬라이더로 고른다(S15P11B209-807).
    final slider = find.descendant(
      of: find.byKey(const ValueKey('drawing-thickness-slider')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    tester.widget<Slider>(slider).onChanged!(14);
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

/// 종이 한가운데를 기준으로 한 문서 좌표다.
///
/// 종이가 곧 문서라 크기가 기기마다 다르다(S15P11B209-801). 좌표를 박아 두면
/// 지우개가 지나가는 자리와 획이 어긋난다.
Offset _nearCentre(WidgetTester tester, Offset delta) =>
    tester
        .getSize(find.byKey(const ValueKey('drawing-canvas')))
        .center(Offset.zero) +
    delta;
