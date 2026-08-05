import 'dart:ui' as ui;

import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_document_controller.dart';
import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_tool_state.dart';
import 'package:dodam/features/drawing/presentation/rendering/drawing_stroke_renderer.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas_viewport.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_cursor_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const metrics = DrawingViewportMetrics(
    availableSize: Size(400, 300),
    documentSize: Size(1024, 768),
    scale: 0.5,
    origin: Offset(20, 30),
  );

  test('controller publishes the current tool and can hide the cursor', () {
    final controller = DrawingCursorController(_hiddenCursorState);
    addTearDown(controller.dispose);
    const toolState = DrawingToolState(
      instrument: DrawingInstrument.eraser,
      eraserMode: DrawingEraserMode.stroke,
      color: Colors.red,
      width: 24,
    );

    controller.update(
      documentPosition: const Offset(123, 456),
      toolState: toolState,
      deviceKind: ui.PointerDeviceKind.stylus,
    );

    expect(controller.value.visible, isTrue);
    expect(controller.value.documentPosition, const Offset(123, 456));
    expect(controller.value.instrument, DrawingInstrument.eraser);
    expect(controller.value.eraserMode, DrawingEraserMode.stroke);
    expect(controller.value.documentWidth, 24);
    expect(controller.value.deviceKind, ui.PointerDeviceKind.stylus);

    controller.hide();
    expect(controller.value.visible, isFalse);
    expect(controller.value.documentPosition, const Offset(123, 456));
  });

  testWidgets('overlay ignores input and scales diameter from document width', (
    tester,
  ) async {
    const state = DrawingCursorState(
      visible: true,
      documentPosition: Offset(100, 80),
      instrument: DrawingInstrument.brush,
      eraserMode: DrawingEraserMode.area,
      documentWidth: 24,
      deviceKind: ui.PointerDeviceKind.mouse,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: DrawingCursorOverlay(state: state, metrics: metrics),
        ),
      ),
    );

    final ignorePointer = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('drawing-cursor-overlay')),
    );
    expect(ignorePointer.ignoring, isTrue);
    final visual = find.byKey(const ValueKey('drawing-cursor-visual'));
    // 붓은 선 굵기보다 자국이 넓다. 커서는 그 자국 크기를 그린다.
    final footprint = DrawingStrokeRenderer.footprintFor(
      DrawingInstrument.brush.brushProfile,
      24,
    );
    expect(tester.getSize(visual), Size.square(footprint * 0.5));
    expect(
      tester.getCenter(visual),
      const Offset(20 + 100 * 0.5, 30 + 80 * 0.5),
    );
  });

  testWidgets('fill cursor renders dark and light contrast rings', (
    tester,
  ) async {
    const state = DrawingCursorState(
      visible: true,
      documentPosition: Offset(200, 100),
      instrument: DrawingInstrument.fill,
      eraserMode: DrawingEraserMode.area,
      documentWidth: 32,
      deviceKind: ui.PointerDeviceKind.mouse,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: DrawingCursorOverlay(state: state, metrics: metrics),
      ),
    );

    final dark = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('drawing-fill-cursor-dark-outline')),
    );
    final light = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('drawing-fill-cursor-light-outline')),
    );
    final darkBorder = (dark.decoration as BoxDecoration).border! as Border;
    final lightBorder = (light.decoration as BoxDecoration).border! as Border;
    expect(darkBorder.top.color, Colors.black);
    expect(lightBorder.top.color, Colors.white);
  });

  testWidgets('current width immediately changes the cursor diameter', (
    tester,
  ) async {
    final controller = DrawingCursorController(_hiddenCursorState);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<DrawingCursorState>(
          valueListenable: controller,
          builder: (context, state, child) =>
              DrawingCursorOverlay(state: state, metrics: metrics),
        ),
      ),
    );

    controller.update(
      documentPosition: const Offset(50, 50),
      toolState: const DrawingToolState(width: 10),
      deviceKind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('drawing-cursor-visual'))),
      Size.square(_footprint(10) * 0.5),
    );

    controller.update(
      documentPosition: const Offset(50, 50),
      toolState: const DrawingToolState(width: 36),
      deviceKind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('drawing-cursor-visual'))),
      Size.square(_footprint(36) * 0.5),
    );
  });

  testWidgets(
    'hover and drag track the pointer while idle touch and exit hide',
    (tester) async {
      final syncCoordinator = DrawingSyncCoordinator(
        sessionId: null,
        repository: null,
      );
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingScreen(childId: '3', syncCoordinator: syncCoordinator),
        ),
      );
      await tester.pumpAndSettle();

      final document = find.byKey(const ValueKey('drawing-document-marker'));
      final canvas = find.byKey(const ValueKey('drawing-canvas'));
      final documentMouseRegion = find.descendant(
        of: document,
        matching: find.byType(MouseRegion),
      );
      expect(documentMouseRegion, findsOneWidget);
      expect(
        tester.widget<MouseRegion>(documentMouseRegion).cursor,
        SystemMouseCursors.none,
      );

      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      final canvasCenter = tester.getCenter(canvas);
      await mouse.moveTo(canvasCenter);
      await tester.pump();
      final visual = find.byKey(const ValueKey('drawing-cursor-visual'));
      expect(visual, findsOneWidget);
      expect(
        (tester.getCenter(visual) - canvasCenter).distance,
        lessThan(0.01),
      );

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(visual, findsNothing);

      final touch = await tester.startGesture(canvasCenter);
      await tester.pump();
      expect(visual, findsOneWidget);
      final movedTo = canvasCenter + const Offset(18, 12);
      await touch.moveTo(movedTo);
      await tester.pump();
      expect((tester.getCenter(visual) - movedTo).distance, lessThan(0.01));
      await touch.up();
      await tester.pump();
      expect(visual, findsNothing);

      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      syncCoordinator.dispose();
    },
  );

  testWidgets(
    'mouse drag stays hidden after leaving the document and releasing outside',
    (tester) async {
      final syncCoordinator = DrawingSyncCoordinator(
        sessionId: null,
        repository: null,
      );
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingScreen(childId: '3', syncCoordinator: syncCoordinator),
        ),
      );
      await tester.pumpAndSettle();

      final canvas = find.byKey(const ValueKey('drawing-canvas'));
      final canvasCenter = tester.getCenter(canvas);
      final visual = find.byKey(const ValueKey('drawing-cursor-visual'));
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: canvasCenter);
      await mouse.down(canvasCenter);
      await tester.pump();
      expect(visual, findsOneWidget);

      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(visual, findsNothing);

      await mouse.up();
      await tester.pump();
      expect(visual, findsNothing);

      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      syncCoordinator.dispose();
    },
  );

  testWidgets(
    'touch rejected during voice recording never shows a cursor or stroke',
    (tester) async {
      final documentController = DrawingDocumentController();
      final syncCoordinator = DrawingSyncCoordinator(
        sessionId: null,
        repository: null,
      );
      final detectionController = DrawingObjectDetectionController(
        debounceDuration: Duration.zero,
        saveDraft: () async => const DraftSaveResponseDto(
          drawingAssetId: 120,
          assetVersion: 1,
          lastEventSequence: 1,
          savedAt: '2026-08-03T00:00:00Z',
          expiresAt: null,
        ),
        requestDetection: (_) async => _cursorDetection,
      );
      final recorder = _CursorVoiceRecorder();
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DrawingScreen(
            childId: '3',
            conversationId: 8001,
            conversationRepository: const _CursorConversationRepository(),
            voiceAnswerRepository: const _CursorVoiceAnswerRepository(),
            voiceRecorder: recorder,
            microphonePermissionService: const _GrantedMicrophonePermission(),
            voiceNoSpeechTimeout: const Duration(minutes: 1),
            documentController: documentController,
            objectDetectionController: detectionController,
            syncCoordinator: syncCoordinator,
            startFresh: true,
          ),
        ),
      );
      await tester.pump();

      detectionController
        ..onDrawingInputStarted()
        ..onDrawingInputEnded();
      for (var index = 0; index < 40 && !recorder.started; index += 1) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump();
      expect(recorder.started, isTrue);

      final canvas = find.byKey(const ValueKey('drawing-canvas'));
      final canvasRect = tester.getRect(canvas);
      final touch = await tester.startGesture(
        canvasRect.bottomLeft + const Offset(24, -24),
      );
      await tester.pump();
      final visual = find.byKey(const ValueKey('drawing-cursor-visual'));
      expect(visual, findsNothing);
      expect(documentController.visibleStrokes, isEmpty);

      await touch.up();
      await tester.pump();
      expect(visual, findsNothing);
      expect(documentController.visibleStrokes, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      detectionController.dispose();
      syncCoordinator.dispose();
      documentController.dispose();
    },
  );

  testWidgets('cursor is outside capture and does not change document bytes', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    final controller = DrawingCursorController(_hiddenCursorState);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingCanvasViewport(
          repaintBoundaryKey: boundaryKey,
          canvas: const ColoredBox(color: Colors.white),
          overlayBuilder: (context, metrics) =>
              ValueListenableBuilder<DrawingCursorState>(
                valueListenable: controller,
                builder: (context, state, child) =>
                    DrawingCursorOverlay(state: state, metrics: metrics),
              ),
        ),
      ),
    );
    await tester.pump();
    final before = await _captureRawBytes(tester, boundaryKey);

    controller.update(
      documentPosition: const Offset(512, 384),
      toolState: const DrawingToolState(
        instrument: DrawingInstrument.fill,
        width: 48,
      ),
      deviceKind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump();

    final marker = find.byKey(const ValueKey('drawing-document-marker'));
    final overlay = find.byKey(const ValueKey('drawing-cursor-overlay'));
    expect(overlay, findsOneWidget);
    expect(find.ancestor(of: marker, matching: overlay), findsNothing);
    expect(find.descendant(of: marker, matching: overlay), findsNothing);
    expect(find.ancestor(of: overlay, matching: marker), findsNothing);
    expect(find.descendant(of: overlay, matching: marker), findsNothing);

    final after = await _captureRawBytes(tester, boundaryKey);
    expect(listEquals(after, before), isTrue);
  });
}

const _hiddenCursorState = DrawingCursorState(
  visible: false,
  documentPosition: Offset.zero,
  instrument: DrawingInstrument.crayon,
  eraserMode: DrawingEraserMode.area,
  documentWidth: 8,
  deviceKind: ui.PointerDeviceKind.touch,
);

Future<Uint8List> _captureRawBytes(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  image!.dispose();
  return data!.buffer.asUint8List();
}

final class _CursorConversationRepository implements ConversationRepository {
  const _CursorConversationRepository();

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async => 8001;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async => AiQuestion(
    messageId: 9001,
    conversationId: conversationId,
    sequence: 1,
    text: 'What did you draw?',
    options: const [],
    ttsAvailable: false,
    createdAt: DateTime.utc(2026, 8, 3),
  );
}

final class _CursorVoiceAnswerRepository implements VoiceAnswerRepository {
  const _CursorVoiceAnswerRepository();

  @override
  Future<VoiceAnswerUploadResult> upload({
    required int conversationId,
    required VoiceAnswerUploadRequest request,
    required String idempotencyKey,
  }) async => const VoiceAnswerUploadResult(
    messageId: 9002,
    parentMessageId: 9001,
    sequence: 2,
    speechStatus: 'PENDING',
  );
}

final class _CursorVoiceRecorder implements VoiceRecorder {
  bool started = false;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<double> readAmplitude() async => -80;

  @override
  Future<String?> stop() async => '/tmp/cursor-voice.m4a';

  @override
  Future<void> cancel() async {
    started = false;
  }

  @override
  Future<void> dispose() async {}
}

final class _GrantedMicrophonePermission
    implements MicrophonePermissionService {
  const _GrantedMicrophonePermission();

  @override
  Future<MicrophonePermissionStatus> request() async =>
      MicrophonePermissionStatus.granted;

  @override
  Future<bool> openSettings() async => true;
}

const _cursorDetection = ObjectDetectionResponseDto(
  drawingAnalysisId: 7001,
  drawingSessionId: 42,
  drawingAssetId: 120,
  requestId: 'cursor-preview-detection',
  analysisType: 'OBJECT_DETECTION',
  status: 'SUCCEEDED',
  model: DrawingAnalysisModelDto(name: 'cursor-test', version: '1.0'),
  detections: [],
  requestedAt: '2026-08-03T00:00:00Z',
  processedAt: '2026-08-03T00:00:01Z',
);

/// 기본 도구(크레파스)로 [thickness] 만큼 그었을 때 찍히는 자국 지름이다.
double _footprint(double thickness) => DrawingStrokeRenderer.footprintFor(
  const DrawingToolState().brushProfile,
  thickness,
);
