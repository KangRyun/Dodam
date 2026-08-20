import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_document_controller.dart';
import 'package:dodam/features/drawing/application/drawing_event_journal.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_cursor_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('지우개 버튼은 메뉴 없이 하나의 ERASER 획을 기록한다', (tester) async {
    final harness = await _pumpScreen(tester);
    await _selectEraser(tester);
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

    expect(find.byKey(const ValueKey('drawing-eraser-stroke')), findsNothing);
    expect(find.byKey(const ValueKey('drawing-eraser-area')), findsNothing);
    expect(
      find.byKey(const ValueKey('drawing-eraser-clear-all')),
      findsNothing,
    );
    expect(harness.document.visibleStrokes, hasLength(1));
    expect(harness.document.visibleStrokes.single.tool, DrawingTool.eraser);
    expect(
      harness.sync.journal.events
          .where((event) => event.type == DrawingEventTypes.toolChange)
          .single
          .tool,
      'ERASER',
    );
    expect(
      harness.sync.journal.events
          .where((event) => event.type == DrawingEventTypes.strokeStart)
          .single
          .tool,
      'ERASER',
    );
  });

  testWidgets('굵기 Slider 값이 지우개 획과 커서 크기에 함께 반영된다', (tester) async {
    final harness = await _pumpScreen(tester);
    final slider = find.descendant(
      of: find.byKey(const ValueKey('drawing-thickness-slider')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    tester.widget<Slider>(slider).onChanged!(14);
    await tester.pump();
    await _selectEraser(tester);

    final cursor = TestPointer(91, PointerDeviceKind.mouse);
    await _hoverCanvas(tester, cursor);
    final overlay = tester.widget<DrawingCursorOverlay>(
      find.byType(DrawingCursorOverlay),
    );
    expect(find.byKey(const ValueKey('area-eraser-cursor')), findsOneWidget);
    expect(overlay.state.documentWidth, 14);

    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(
      center - const Offset(20, 0),
      kind: ui.PointerDeviceKind.mouse,
    );
    await gesture.moveTo(center + const Offset(20, 0));
    await gesture.up();
    await tester.pump();

    expect(harness.document.visibleStrokes.single.thickness, 14);
    await tester.sendEventToBinding(cursor.removePointer());
  });

  testWidgets('영역 지우개 획은 일반 획처럼 실행 취소와 다시 실행이 된다', (tester) async {
    final harness = await _pumpScreen(tester);
    await _selectEraser(tester);
    final canvas = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
    final gesture = await tester.startGesture(
      canvas.center,
      kind: ui.PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    await tester.pump();

    expect(harness.document.visibleStrokes, hasLength(1));
    harness.document.undo();
    expect(harness.document.visibleStrokes, isEmpty);
    harness.document.redo();
    expect(harness.document.visibleStrokes, hasLength(1));
    expect(harness.document.visibleStrokes.single.tool, DrawingTool.eraser);
  });
}

Future<_DrawingHarness> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = _EraserRepository();
  final sync = DrawingSyncCoordinator(
    sessionId: 42,
    repository: repository,
    journal: DrawingEventJournal(sessionClock: Stopwatch()),
  );
  final document = DrawingDocumentController();

  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '3',
        sessionId: 42,
        drawingRepository: repository,
        syncCoordinator: sync,
        documentController: document,
        startFresh: true,
      ),
    ),
  );
  await tester.pump();
  sync.pause();

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
    document.dispose();
  });
  return _DrawingHarness(sync: sync, document: document);
}

Future<void> _selectEraser(WidgetTester tester) async {
  final eraser = find.byKey(const ValueKey('drawing-tool-eraser'));
  await tester.ensureVisible(eraser);
  await tester.tap(eraser);
  await tester.pumpAndSettle();
}

Future<void> _hoverCanvas(WidgetTester tester, TestPointer cursor) async {
  final center = tester.getCenter(find.byKey(const ValueKey('drawing-canvas')));
  await tester.sendEventToBinding(cursor.addPointer(location: center));
  await tester.sendEventToBinding(cursor.hover(center));
  await tester.pump();
}

final class _DrawingHarness {
  const _DrawingHarness({required this.sync, required this.document});

  final DrawingSyncCoordinator sync;
  final DrawingDocumentController document;
}

final class _EraserRepository implements DrawingRepository {
  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState, {
    required String idempotencyKey,
  }) async => DraftSaveResponseDto(
    drawingAssetId: 1,
    assetVersion: 1,
    lastEventSequence: canvasState.lastEventSequence,
    savedAt: canvasState.clientSavedAt ?? '2026-08-10T00:00:00Z',
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
    receivedAt: '2026-08-10T00:00:00Z',
  );

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;
  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async => null;
  @override
  Future<Uint8List> downloadDraftPreview(
    String previewUrl,
  ) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  );
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
