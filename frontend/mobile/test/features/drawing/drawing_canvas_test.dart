import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Drawing 화면에 빈 Canvas와 비활성 완료 버튼을 표시한다', (tester) async {
    await _pumpDrawing(tester);

    expect(find.text('그림 활동'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(_canvas(tester).strokes, isEmpty);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('drawing-complete')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
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

    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('drawing-complete')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('작은 화면에서는 세로 배치하며 overflow가 발생하지 않는다', (tester) async {
    await _pumpDrawing(tester, size: const Size(600, 800));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.text('다 그렸어요!'), findsOneWidget);
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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: DrawingScreen(childId: '3')));
  await tester.pumpAndSettle();
}

DrawingCanvas _canvas(WidgetTester tester) =>
    tester.widget<DrawingCanvas>(find.byType(DrawingCanvas));

Future<void> _drawStroke(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(const Offset(24, 18));
  await gesture.up();
  await tester.pump();
}
