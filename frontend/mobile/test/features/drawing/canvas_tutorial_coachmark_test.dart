import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/canvas_tutorial_controller.dart';
import 'package:dodam/features/drawing/application/drawing_document_controller.dart';
import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/presentation/models/canvas_tutorial_step_content.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tool_tutorial_overlay.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tutorial_target_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('안내는 실제 도구를 밝게 남기고 카드를 그 반대쪽에 놓는다', (tester) async {
    await _pumpDrawing(tester, tutorial: _tutorial(status: 'NOT_STARTED'));

    final crayon = tester.getRect(
      find.byKey(const ValueKey('drawing-tool-crayon')),
    );
    final bubble = tester.getRect(
      find.byKey(const ValueKey('canvas-tutorial-bubble')),
    );

    // 툴바가 화면 위에 있으므로 카드는 아래로 내려가 도구를 가리지 않는다.
    expect(bubble.top, greaterThan(crayon.bottom));
    expect(
      find.byKey(const ValueKey('canvas-tutorial-teacher')),
      findsOneWidget,
    );
  });

  testWidgets('가리킬 자리를 못 찾으면 가운데 카드로 물러난다', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _tutorial(status: 'COMPLETED')..replay();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // 툴바가 없는 화면이라 registry 가 있어도 읽을 rect 가 없다.
          body: Stack(
            children: [
              CanvasToolTutorialOverlay(
                controller,
                targets: CanvasTutorialTargetRegistry(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bubble = tester.getRect(
      find.byKey(const ValueKey('canvas-tutorial-bubble')),
    );
    expect((bubble.center.dy - 300).abs(), lessThan(140));
  });

  testWidgets('가리키는 도구는 눌러 볼 수 있다', (tester) async {
    final tutorial = _tutorial(status: 'IN_PROGRESS', lastStep: 'ERASER');
    await _pumpDrawing(tester, tutorial: tutorial);
    expect(find.text('지우개로 고쳐요'), findsOneWidget);
    expect(find.text('지우개를 누르고 굵기를 조절해 원하는 부분을 지워 보세요.'), findsOneWidget);

    // 안내를 보면서 실제 지우개 버튼을 누르면 바로 영역 지우개가 선택된다.
    await tester.tap(find.byKey(const ValueKey('drawing-tool-eraser')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('drawing-eraser-stroke')), findsNothing);
    expect(find.byKey(const ValueKey('drawing-eraser-area')), findsNothing);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('안내 중에는 캔버스에 그려지지 않고, 끝나면 다시 그려진다', (tester) async {
    final document = DrawingDocumentController();
    addTearDown(document.dispose);
    final tutorial = _tutorial(status: 'NOT_STARTED');
    await _pumpDrawing(tester, tutorial: tutorial, document: document);

    final canvas = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
    await _drag(tester, canvas.center);
    expect(document.visibleStrokes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);

    await _drag(tester, canvas.center);
    expect(document.visibleStrokes, hasLength(1));
  });

  testWidgets('완료 단계는 완료 버튼을 가리키지만 눌러지지 않는다', (tester) async {
    final document = DrawingDocumentController()
      ..addStroke(
        const DrawingStroke(
          points: [
            DrawingPoint(position: Offset(10, 10), elapsedMilliseconds: 0),
            DrawingPoint(position: Offset(40, 40), elapsedMilliseconds: 8),
          ],
          color: Color(0xFF000000),
          thickness: 8,
        ),
      );
    addTearDown(document.dispose);
    await _pumpDrawing(
      tester,
      tutorial: _tutorial(status: 'IN_PROGRESS', lastStep: 'COMPLETE'),
      document: document,
    );
    expect(find.text('그림을 마쳐요'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('drawing-complete-button'))),
    );
    await tester.pumpAndSettle();

    // 안내를 보다가 활동이 끝나 버리면 안 된다.
    expect(find.text('그림을 다 그렸나요?'), findsNothing);
  });

  testWidgets('AI 질문이 뜨면 안내를 숨긴다', (tester) async {
    final detection = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 1),
      saveDraft: () async => const DraftSaveResponseDto(
        drawingAssetId: 120,
        assetVersion: 1,
        lastEventSequence: 1,
        savedAt: '2026-08-05T00:00:00Z',
        expiresAt: null,
      ),
      requestDetection: (_) async => _detection,
    );
    addTearDown(detection.dispose);

    await _pumpDrawing(
      tester,
      tutorial: _tutorial(status: 'NOT_STARTED'),
      detection: detection,
      conversation: _ConversationRepository(),
    );
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsOneWidget);

    detection.onDrawingInputStarted();
    detection.onDrawingInputEnded();
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('이 집에는 누가 살고 있어?'), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);
  });

  testWidgets('HTP는 안내 동안 색상·도구를 열어 체험시키고 끝나면 다시 잠근다', (tester) async {
    final tutorial = _tutorial(status: 'NOT_STARTED');
    await _pumpDrawing(tester, tutorial: tutorial, htp: true);

    // 안내 중에는 그림일기와 같은 툴바로 열어 준다.
    expect(find.byKey(const ValueKey('drawing-quick-colors')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drawing-palette-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('drawing-tool-crayon')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canvas-tutorial-trial-notice')),
      findsOneWidget,
    );

    // 도구 단계에서 크레용을 눌러 본다.
    await tester.tap(find.byKey(const ValueKey('drawing-tool-crayon')));
    await tester.pumpAndSettle();

    // 색상 단계까지 가서 빨강을 골라 본다.
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pumpAndSettle();
    expect(find.text('좋아하는 색을 골라요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drawing-quick-color-0')));
    await tester.pumpAndSettle();
    expect(_previewColor(tester), AppColors.canvasSwatchRed);

    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pumpAndSettle();

    // 검사로 돌아오면 다시 연필·검정만 남는다.
    expect(find.byKey(const ValueKey('drawing-quick-colors')), findsNothing);
    expect(find.byKey(const ValueKey('drawing-palette-button')), findsNothing);
    expect(find.byKey(const ValueKey('drawing-tool-crayon')), findsNothing);
    expect(find.byKey(const ValueKey('drawing-tool-pencil')), findsOneWidget);

    // 체험 중 고른 빨강이 남아 있으면 검사 그림이 빨갛게 그려진다.
    expect(_previewColor(tester), AppColors.canvasSwatchCharcoal);
  });

  testWidgets('물음표를 누르면 언제든 안내를 다시 볼 수 있다', (tester) async {
    await _pumpDrawing(tester, tutorial: _tutorial(status: 'COMPLETED'));
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('canvas-tutorial-help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);

    // 다시 보기는 몇 번이든 된다.
    await tester.tap(find.byKey(const ValueKey('canvas-tutorial-help')));
    await tester.pumpAndSettle();
    expect(find.text('도구를 골라 그려요'), findsOneWidget);
  });

  testWidgets('안내받은 도구를 직접 눌러 보면 해보기 체크가 켜진다', (tester) async {
    await _pumpDrawing(tester, tutorial: _tutorial(status: 'NOT_STARTED'));

    expect(find.text('도구를 하나 눌러 보기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canvas-tutorial-practice-todo')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('drawing-tool-brush')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('canvas-tutorial-practice-done')),
      findsOneWidget,
    );
    expect(find.text('해 봤어요!'), findsOneWidget);
    expect(find.text('좋아요! 이제 종이에 그으면 그 도구 자국이 남아요.'), findsOneWidget);
  });

  testWidgets('안내는 그림 캡처 경계 밖에 있다', (tester) async {
    await _pumpDrawing(tester, tutorial: _tutorial(status: 'NOT_STARTED'));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('drawing-document-marker')),
        matching: find.byKey(const ValueKey('canvas-tool-tutorial')),
      ),
      findsNothing,
    );
  });

  testWidgets('화면 크기가 바뀌면 가리키는 자리를 다시 잡는다', (tester) async {
    await _pumpDrawing(tester, tutorial: _tutorial(status: 'NOT_STARTED'));
    final before = tester.getRect(
      find.byKey(const ValueKey('canvas-tutorial-bubble')),
    );

    tester.view.physicalSize = const Size(820, 1180);
    await tester.pumpAndSettle();

    final crayon = tester.getRect(
      find.byKey(const ValueKey('drawing-tool-crayon')),
    );
    final after = tester.getRect(
      find.byKey(const ValueKey('canvas-tutorial-bubble')),
    );
    expect(after, isNot(before));
    expect(after.top, greaterThan(crayon.bottom));
    expect(tester.takeException(), isNull);
  });

  test('HTP 체험에서만 검은 연필로 돌아간다는 안내를 덧붙인다', () {
    expect(
      CanvasTutorialStepContent.of(
        CanvasTutorialStep.color,
        htpTrial: true,
      ).trialNotice,
      isNotNull,
    );
    expect(
      CanvasTutorialStepContent.of(
        CanvasTutorialStep.color,
        htpTrial: false,
      ).trialNotice,
      isNull,
    );
    // 체험이든 아니든 가리킬 자리와 문구는 같다.
    expect(
      CanvasTutorialStepContent.of(
        CanvasTutorialStep.color,
        htpTrial: true,
      ).target,
      CanvasTutorialTargetId.colors,
    );
  });

  test('완료 단계만 target 탭을 막는다', () {
    for (final step in CanvasTutorialStep.values) {
      final content = CanvasTutorialStepContent.of(step, htpTrial: false);
      expect(
        content.allowsTargetTap,
        step != CanvasTutorialStep.complete,
        reason: step.name,
      );
    }
  });
}

/// 굵기 미리보기 점은 지금 그리기 색을 그대로 쓴다. 그 색을 읽는다.
Color? _previewColor(WidgetTester tester) {
  final preview = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byKey(const ValueKey('drawing-thickness-preview')),
          matching: find.byType(DecoratedBox),
        )
        .last,
  );
  return (preview.decoration as BoxDecoration).color;
}

Future<void> _drag(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(const Offset(30, 20));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _pumpDrawing(
  WidgetTester tester, {
  required CanvasTutorialController tutorial,
  DrawingDocumentController? document,
  DrawingObjectDetectionController? detection,
  ConversationRepository? conversation,
  bool htp = false,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(
        childId: '3',
        canvasTutorialController: tutorial,
        documentController: document,
        objectDetectionController: detection,
        conversationRepository: conversation,
        conversationId: conversation == null ? null : 8001,
        activityContext: htp
            ? const DrawingActivityContextDto(
                activityKind: 'HTP',
                htpAssessmentId: 91,
                htpStatus: 'IN_PROGRESS',
                stepOrder: 1,
                drawingSubject: 'HOUSE',
              )
            : const DrawingActivityContextDto.general(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CanvasTutorialController _tutorial({required String status, String? lastStep}) {
  var currentStatus = status;
  var currentStep = lastStep;
  return CanvasTutorialController(
    childId: 3,
    loadProgress: (childId) async =>
        _progress(childId, currentStatus, currentStep),
    saveProgress: (childId, request) async {
      currentStatus = request.tutorialStatus;
      currentStep = request.lastStep;
      return _progress(childId, currentStatus, currentStep);
    },
  );
}

TutorialProgressDto _progress(int childId, String status, String? lastStep) =>
    TutorialProgressDto(
      childId: childId,
      tutorialStatus: status,
      lastStep: lastStep,
      completedAt: null,
      updatedAt: '2026-08-05T00:00:00Z',
    );

final class _ConversationRepository implements ConversationRepository {
  @override
  Future<ConversationStartResult> startConversation({
    required int drawingSessionId,
    int? analysisId,
    required String idempotencyKey,
  }) async =>
      const ConversationStartResult(conversationId: 8001, maxQuestionCount: 5);

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async => AiQuestion(
    messageId: 9001,
    conversationId: conversationId,
    sequence: 1,
    text: '이 집에는 누가 살고 있어?',
    options: const [],
    ttsAvailable: false,
    createdAt: DateTime(2026, 8, 5),
  );
}

const _detection = ObjectDetectionResponseDto(
  drawingAnalysisId: 7001,
  drawingSessionId: 481,
  drawingAssetId: 120,
  requestId: 'coachmark-detection',
  analysisType: 'OBJECT_DETECTION',
  status: 'SUCCEEDED',
  model: DrawingAnalysisModelDto(name: 'preview', version: '1.0'),
  detections: [],
  requestedAt: '2026-08-05T00:00:00Z',
  processedAt: '2026-08-05T00:00:01Z',
);
