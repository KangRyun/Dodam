import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Drawing 화면에 빈 Canvas와 비활성 완료 버튼을 표시한다', (tester) async {
    await _pumpDrawing(tester);

    expect(find.text('그림 활동'), findsOneWidget);
    expect(find.text('그림을 안전하게 담고 있어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(_canvas(tester).strokes, isEmpty);
    expect(_undoButton(tester).onPressed, isNull);
    expect(_completeButton(tester).onPressed, isNull);
  });

  testWidgets('pointer down부터 up까지 하나의 stroke로 만들고 여러 획을 누적한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );

    final first = await tester.startGesture(center - const Offset(50, 20));
    await first.moveBy(const Offset(40, 30));
    await first.moveBy(const Offset(40, -10));
    await first.up();
    await tester.pump();

    expect(_canvas(tester).strokes, hasLength(1));
    expect(_canvas(tester).strokes.single.points.length, greaterThan(1));

    final second = await tester.startGesture(center + const Offset(20, 20));
    await second.moveBy(const Offset(30, 20));
    await second.up();
    await tester.pump();

    expect(_canvas(tester).strokes, hasLength(2));
  });

  testWidgets('색상과 굵기 변경은 다음 stroke에만 적용한다', (tester) async {
    await _pumpDrawing(tester);
    final canvasFinder = find.byKey(const ValueKey('drawing-canvas'));
    final center = tester.getCenter(canvasFinder);

    await _drawStroke(tester, center - const Offset(70, 30));
    await tester.tap(find.byKey(const ValueKey('color-빨강')));
    await tester.pump();
    await _drawStroke(tester, center);
    await tester.tap(find.text('얇게'));
    await tester.pump();
    await _drawStroke(tester, center + const Offset(70, 30));

    final strokes = _canvas(tester).strokes;
    expect(strokes, hasLength(3));
    expect(strokes[0].color, AppColors.drawingInk);
    expect(strokes[0].thickness, 8);
    expect(strokes[1].color, AppColors.drawingRed);
    expect(strokes[1].thickness, 8);
    expect(strokes[2].color, AppColors.drawingRed);
    expect(strokes[2].thickness, 4);
  });

  testWidgets('stroke 생성 후 완료 버튼이 활성화된다', (tester) async {
    await _pumpDrawing(tester);
    await _drawStroke(
      tester,
      tester.getCenter(find.byKey(const ValueKey('drawing-canvas'))),
    );

    expect(_undoButton(tester).onPressed, isNotNull);
    expect(_completeButton(tester).onPressed, isNotNull);
  });

  testWidgets('Undo는 마지막 완료 stroke만 제거하고 기존 속성을 유지한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center - const Offset(50, 20));
    await tester.tap(find.byKey(const ValueKey('color-빨강')));
    await tester.tap(find.text('얇게'));
    await tester.pump();
    await _drawStroke(tester, center + const Offset(50, 20));

    expect(_canvas(tester).strokes, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();

    final remaining = _canvas(tester).strokes.single;
    expect(remaining.color, AppColors.drawingInk);
    expect(remaining.thickness, 8);
    expect(_completeButton(tester).onPressed, isNotNull);
  });

  testWidgets('연속 Undo로 빈 Canvas가 되면 버튼들을 비활성화한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center - const Offset(60, 20));
    await _drawStroke(tester, center);
    await _drawStroke(tester, center + const Offset(60, 20));

    for (final expectedCount in [2, 1, 0]) {
      await tester.tap(find.byKey(const ValueKey('undo-action')));
      await tester.pump();
      expect(_canvas(tester).strokes, hasLength(expectedCount));
    }
    expect(_undoButton(tester).onPressed, isNull);
    expect(_completeButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(_canvas(tester).strokes, isEmpty);
  });

  testWidgets('그리는 중에는 Undo와 완료를 비활성화한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center - const Offset(50, 20));
    final gesture = await tester.startGesture(center + const Offset(50, 20));
    await gesture.moveBy(const Offset(20, 12));
    await tester.pump();

    expect(_canvas(tester).strokes, hasLength(2));
    expect(_undoButton(tester).onPressed, isNull);
    expect(_completeButton(tester).onPressed, isNull);

    await gesture.up();
    await tester.pump();
    expect(_canvas(tester).strokes, hasLength(2));
    expect(_undoButton(tester).onPressed, isNotNull);
    expect(_completeButton(tester).onPressed, isNotNull);
  });

  testWidgets('pointer cancel은 active stroke를 폐기하고 Undo 상태를 안전하게 복구한다', (
    tester,
  ) async {
    await _pumpDrawing(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('drawing-canvas'))),
    );
    await gesture.moveBy(const Offset(20, 12));
    await gesture.cancel();
    await tester.pump();

    expect(_canvas(tester).strokes, isEmpty);
    expect(_undoButton(tester).onPressed, isNull);
    expect(_completeButton(tester).onPressed, isNull);
  });

  testWidgets('Canvas Undo는 stroke event를 유지하고 UNDO를 journal에 append한다', (
    tester,
  ) async {
    final coordinator = DrawingSyncCoordinator(
      sessionId: null,
      repository: null,
    );
    await _pumpDrawing(tester, coordinator: coordinator);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center - const Offset(50, 20));
    await _drawStroke(tester, center + const Offset(50, 20));
    expect(coordinator.journal.events, hasLength(4));

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(_canvas(tester).strokes, hasLength(1));
    expect(coordinator.journal.events, hasLength(5));
    expect(coordinator.journal.events.last.type, 'UNDO');

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(_canvas(tester).strokes, isEmpty);
    expect(coordinator.journal.events.last.type, 'UNDO');
    expect(coordinator.journal.events, hasLength(6));

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(coordinator.journal.events, hasLength(6));

    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
  });

  testWidgets('작은 화면에서는 세로 배치하며 overflow가 발생하지 않는다', (tester) async {
    await _pumpDrawing(tester, size: const Size(600, 800));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -300),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.text('다 그렸어요!'), findsOneWidget);
  });

  testWidgets('넓지만 높이가 작은 화면에서는 도구 패널이 스크롤되어 overflow가 없다', (tester) async {
    await _pumpDrawing(tester, size: const Size(1200, 600));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('drawing-tool-panel-scroll')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('drawing-tool-panel-scroll')),
      const Offset(0, -1000),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('그림을 안전하게 담고 있어요'), findsOneWidget);
    expect(find.text('다 그렸어요!'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drawing-complete-bottom-space')),
      findsOneWidget,
    );
    final panelBottom = tester
        .getRect(find.byKey(const ValueKey('drawing-tool-panel-scroll')))
        .bottom;
    final buttonBottom = tester
        .getRect(find.byKey(const ValueKey('drawing-complete')))
        .bottom;
    expect(panelBottom - buttonBottom, greaterThanOrEqualTo(AppSpacing.md));
  });

  testWidgets('Drawing 화면에는 보호자 전용 정보가 노출되지 않는다', (tester) async {
    await _pumpDrawing(tester);

    expect(find.text('월간 활동 요약'), findsNothing);
    expect(find.text('관찰 리포트'), findsNothing);
    expect(find.textContaining('위험'), findsNothing);
    expect(find.textContaining('분석 상세'), findsNothing);
  });
}

Future<void> _pumpDrawing(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  DrawingSyncCoordinator? coordinator,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(childId: '3', syncCoordinator: coordinator),
    ),
  );
  await tester.pumpAndSettle();
}

DrawingCanvas _canvas(WidgetTester tester) =>
    tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));

IconButton _undoButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const ValueKey('undo-action')));

FilledButton _completeButton(WidgetTester tester) =>
    tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('drawing-complete')),
        matching: find.byType(FilledButton),
      ),
    );

Future<void> _drawStroke(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(const Offset(24, 18));
  await gesture.up();
  await tester.pump();
}
