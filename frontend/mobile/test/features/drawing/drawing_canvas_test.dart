import 'dart:ui' as ui;

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_canvas_action.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tool_asset_icon.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_tool_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('committed actions paint before the transient stroke overlay', (
    tester,
  ) async {
    const points = [
      DrawingPoint(position: Offset(8, 32), elapsedMilliseconds: 0),
      DrawingPoint(position: Offset(56, 32), elapsedMilliseconds: 10),
    ];
    const committed = DrawingStroke(
      points: points,
      color: AppColors.drawingRed,
      thickness: 12,
    );
    const transient = DrawingStroke(
      points: points,
      color: AppColors.drawingBlue,
      thickness: 8,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    DrawingCanvasPainter(
      const [transient],
      actions: const [DrawingStrokeAction(id: 1, stroke: committed)],
    ).paint(canvas, const Size(64, 64));
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    picture.dispose();
    addTearDown(image.dispose);

    final pixel = await tester.runAsync(() async {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (32 * image.width + 32) * 4;
      return Color.fromARGB(
        bytes!.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    });

    expect(pixel!.b, greaterThan(pixel.r));
  });

  testWidgets('Drawing 화면에 빈 Canvas와 비활성 완료 버튼을 표시한다', (tester) async {
    await _pumpDrawing(tester);

    // 상단 바를 없애고 조작을 크레용 툴바로 모았다(S15P11B209-805).
    expect(find.byKey(const ValueKey('drawing-toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-save-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(_canvas(tester).strokes, isEmpty);
    expect(_undoButton(tester).onTap, isNull);
    expect(_completeButton(tester).onTap, isNull);
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
    await _setThickness(tester, 4);
    await tester.pump();
    await _drawStroke(tester, center + const Offset(70, 30));

    final strokes = _canvas(tester).strokes;
    expect(strokes, hasLength(3));
    expect(strokes[0].color, AppColors.canvasInk);
    expect(strokes[0].thickness, 8);
    expect(strokes[1].color, AppColors.canvasSwatchRed);
    expect(strokes[1].thickness, 8);
    expect(strokes[2].color, AppColors.canvasSwatchRed);
    expect(strokes[2].thickness, 4);
  });

  testWidgets('PEN과 ERASER 전환은 펜 색상을 보존하고 굵기 3단계를 공유한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );

    await tester.tap(find.byKey(const ValueKey('color-빨강')));
    await tester.tap(find.byKey(const ValueKey('drawing-tool-eraser')));
    await tester.pump();

    for (final (width, offset) in [
      (4.0, const Offset(-80, -40)),
      (8.0, Offset.zero),
      (14.0, const Offset(80, 40)),
    ]) {
      await _setThickness(tester, width);
      await _drawStroke(tester, center + offset);
    }

    await tester.tap(find.byKey(const ValueKey('drawing-tool-pen')));
    await tester.pump();
    await _drawStroke(tester, center + const Offset(120, -50));

    final strokes = _canvas(tester).strokes;
    expect(strokes.map((stroke) => stroke.tool), [
      DrawingTool.eraser,
      DrawingTool.eraser,
      DrawingTool.eraser,
      DrawingTool.pen,
    ]);
    expect(strokes.take(3).map((stroke) => stroke.thickness), [4, 8, 14]);
    expect(strokes.last.color, AppColors.canvasSwatchRed);
    expect(strokes.last.thickness, 14);
  });

  testWidgets('펜과 지우개 선택 영역은 48×48 이상이며 아이콘과 테두리로 상태를 구분한다', (tester) async {
    await _pumpDrawing(tester, size: const Size(844, 419));

    final pen = find.byKey(const ValueKey('drawing-tool-pen'));
    final eraser = find.byKey(const ValueKey('drawing-tool-eraser'));
    for (final tool in [pen, eraser]) {
      final size = tester.getSize(tool);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    final artwork = tester.widget<CanvasToolAssetIcon>(
      find.descendant(of: eraser, matching: find.byType(CanvasToolAssetIcon)),
    );
    expect(artwork.artwork, CanvasToolArtwork.eraser);
    expect(tester.widget<DrawingToolButton>(eraser).selected, isFalse);

    await tester.tap(eraser);
    await tester.pump();

    expect(tester.widget<DrawingToolButton>(eraser).selected, isTrue);
    expect(
      find.descendant(
        of: eraser,
        matching: find.image(
          const AssetImage('assets/canvas/frame/selected_tool.png'),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stroke 생성 후 완료 버튼이 활성화된다', (tester) async {
    await _pumpDrawing(tester);
    await _drawStroke(
      tester,
      tester.getCenter(find.byKey(const ValueKey('drawing-canvas'))),
    );

    expect(_undoButton(tester).onTap, isNotNull);
    expect(_completeButton(tester).onTap, isNotNull);
  });

  testWidgets('Undo는 마지막 완료 stroke만 제거하고 기존 속성을 유지한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center - const Offset(50, 20));
    await tester.tap(find.byKey(const ValueKey('color-빨강')));
    await _setThickness(tester, 4);
    await tester.pump();
    await _drawStroke(tester, center + const Offset(50, 20));

    expect(_canvas(tester).strokes, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();

    final remaining = _canvas(tester).strokes.single;
    expect(remaining.color, AppColors.canvasInk);
    expect(remaining.thickness, 8);
    expect(_completeButton(tester).onTap, isNotNull);
  });

  testWidgets('Redo는 마지막으로 취소한 stroke를 원래 속성으로 복원한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center - const Offset(50, 20));
    await tester.tap(find.byKey(const ValueKey('color-빨강')));
    await _setThickness(tester, 4);
    await tester.pump();
    await _drawStroke(tester, center + const Offset(50, 20));

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(_redoButton(tester).onTap, isNotNull);

    await tester.tap(find.byKey(const ValueKey('redo-action')));
    await tester.pump();

    final restored = _canvas(tester).strokes.last;
    expect(_canvas(tester).strokes, hasLength(2));
    expect(restored.color, AppColors.canvasSwatchRed);
    expect(restored.thickness, 4);
    expect(_redoButton(tester).onTap, isNull);
  });

  testWidgets('Undo 후 새 stroke를 그리면 Redo 이력을 폐기한다', (tester) async {
    await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center - const Offset(50, 20));
    await _drawStroke(tester, center + const Offset(50, 20));

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    expect(_redoButton(tester).onTap, isNotNull);

    await _drawStroke(tester, center + const Offset(80, 30));

    expect(_redoButton(tester).onTap, isNull);
    expect(_canvas(tester).strokes, hasLength(2));
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
    expect(_undoButton(tester).onTap, isNull);
    expect(_completeButton(tester).onTap, isNull);

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
    expect(_undoButton(tester).onTap, isNull);
    expect(_completeButton(tester).onTap, isNull);

    await gesture.up();
    await tester.pump();
    expect(_canvas(tester).strokes, hasLength(2));
    expect(_undoButton(tester).onTap, isNotNull);
    expect(_completeButton(tester).onTap, isNotNull);
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
    expect(_undoButton(tester).onTap, isNull);
    expect(_completeButton(tester).onTap, isNull);
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

  testWidgets('Canvas Redo는 REDO를 journal에 append한다', (tester) async {
    final coordinator = DrawingSyncCoordinator(
      sessionId: null,
      repository: null,
    );
    await _pumpDrawing(tester, coordinator: coordinator);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    await _drawStroke(tester, center);

    await tester.tap(find.byKey(const ValueKey('undo-action')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('redo-action')));
    await tester.pump();

    expect(coordinator.journal.events.last.type, 'REDO');
    expect(coordinator.journal.events.map((event) => event.type), [
      'STROKE_START',
      'STROKE_END',
      'UNDO',
      'REDO',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
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

InkWell _undoButton(WidgetTester tester) => tester.widget<InkWell>(
  find.descendant(
    of: find.byKey(const ValueKey('undo-action')),
    matching: find.byType(InkWell),
  ),
);

InkWell _redoButton(WidgetTester tester) => tester.widget<InkWell>(
  find.descendant(
    of: find.byKey(const ValueKey('redo-action')),
    matching: find.byType(InkWell),
  ),
);

InkWell _completeButton(WidgetTester tester) => tester.widget<InkWell>(
  find.descendant(
    of: find.byKey(const ValueKey('drawing-complete')),
    matching: find.byType(InkWell),
  ),
);

Future<void> _drawStroke(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(const Offset(24, 18));
  await gesture.up();
  await tester.pump();
}

/// 굵기는 툴바 슬라이더로 고른다(S15P11B209-807). 합성 드래그로 정확한 값을
/// 맞추기 어려워 슬라이더의 콜백을 직접 부른다.
Future<void> _setThickness(WidgetTester tester, double width) async {
  final slider = find.descendant(
    of: find.byKey(const ValueKey('drawing-thickness-slider')),
    matching: find.byType(Slider),
  );
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  tester.widget<Slider>(slider).onChanged!(width);
  await tester.pump();
}
