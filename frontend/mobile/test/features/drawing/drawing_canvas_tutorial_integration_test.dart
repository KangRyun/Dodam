import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/drawing/application/canvas_tutorial_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('최초 Canvas 진입은 도구 안내를 자동으로 연다', (tester) async {
    final controller = _controller(status: 'NOT_STARTED');

    await _pumpDrawing(tester, controller);

    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsOneWidget);
    expect(find.text('도구를 골라 그려요'), findsOneWidget);
  });

  testWidgets('완료한 아동은 자동 노출하지 않고 도움말로 다시 본다', (tester) async {
    final controller = _controller(status: 'COMPLETED');

    await _pumpDrawing(tester, controller);

    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('canvas-tutorial-help')));
    await tester.pump();
    expect(find.text('도구를 골라 그려요'), findsOneWidget);
  });

  testWidgets('튜토리얼 저장소가 없으면 기존 Canvas 동작과 상단 버튼을 유지한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DrawingScreen(childId: '3')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);
    expect(find.byKey(const ValueKey('canvas-tutorial-help')), findsNothing);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('undo-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('redo-action')), findsOneWidget);
  });

  testWidgets('UPLOAD 입력 화면에는 Canvas 도구 안내를 열지 않는다', (tester) async {
    final controller = _controller(status: 'NOT_STARTED');
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          childId: '3',
          inputMethod: 'UPLOAD',
          canvasTutorialController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('canvas-tool-tutorial')), findsNothing);
    expect(find.byKey(const ValueKey('canvas-tutorial-help')), findsNothing);
  });
}

CanvasTutorialController _controller({required String status}) =>
    CanvasTutorialController(
      childId: 3,
      loadProgress: (_) async => _progress(status),
      saveProgress: (_, request) async =>
          _progress(request.tutorialStatus, lastStep: request.lastStep),
    );

Future<void> _pumpDrawing(
  WidgetTester tester,
  CanvasTutorialController controller,
) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(childId: '3', canvasTutorialController: controller),
    ),
  );
  await tester.pumpAndSettle();
}

TutorialProgressDto _progress(String status, {String? lastStep}) =>
    TutorialProgressDto(
      childId: 3,
      tutorialStatus: status,
      lastStep: lastStep,
      completedAt: null,
      updatedAt: '2026-07-31T00:00:00Z',
    );
