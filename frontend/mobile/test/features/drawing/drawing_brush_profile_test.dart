import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_canvas_action.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_tool_state.dart';
import 'package:dodam/features/drawing/presentation/rendering/drawing_stroke_renderer.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('instruments map only wire-supported tools to the journal', () {
    expect(
      const DrawingToolState(instrument: DrawingInstrument.crayon).wireTool,
      DrawingTool.pen,
    );
    expect(
      const DrawingToolState(instrument: DrawingInstrument.pencil).wireTool,
      DrawingTool.pen,
    );
    expect(
      const DrawingToolState(instrument: DrawingInstrument.brush).wireTool,
      DrawingTool.pen,
    );
    expect(
      const DrawingToolState(instrument: DrawingInstrument.eraser).wireTool,
      DrawingTool.eraser,
    );
    expect(
      const DrawingToolState(instrument: DrawingInstrument.fill).wireTool,
      isNull,
    );
  });

  test('adding points keeps the selected profile and texture seed', () {
    const first = DrawingStroke(
      points: [DrawingPoint(position: Offset.zero, elapsedMilliseconds: 0)],
      color: AppColors.drawingRed,
      thickness: 8,
      brushProfile: DrawingBrushProfileId.crayon,
      textureSeed: 73,
    );
    final second = first.addPoint(
      const DrawingPoint(position: Offset(5, 4), elapsedMilliseconds: 10),
    );
    final third = second.addPoint(
      const DrawingPoint(position: Offset(9, 7), elapsedMilliseconds: 20),
    );

    expect(second.brushProfile, DrawingBrushProfileId.crayon);
    expect(third.brushProfile, DrawingBrushProfileId.crayon);
    expect(second.textureSeed, 73);
    expect(third.textureSeed, 73);
    expect(third.points, hasLength(3));
  });

  test('pencil, crayon, and brush expose clearly separated footprints', () {
    const thickness = 12.0;
    final pencil = DrawingStrokeRenderer.footprintFor(
      DrawingBrushProfileId.pencil,
      thickness,
    );
    final crayon = DrawingStrokeRenderer.footprintFor(
      DrawingBrushProfileId.crayon,
      thickness,
    );
    final brush = DrawingStrokeRenderer.footprintFor(
      DrawingBrushProfileId.brush,
      thickness,
    );

    expect(pencil, lessThan(crayon * .7));
    expect(brush, greaterThan(crayon * 1.08));
  });

  testWidgets('a seeded crayon stroke renders identical RGBA bytes', (
    tester,
  ) async {
    const stroke = DrawingStroke(
      points: [
        DrawingPoint(position: Offset(8, 16), elapsedMilliseconds: 0),
        DrawingPoint(position: Offset(56, 48), elapsedMilliseconds: 20),
      ],
      color: AppColors.drawingRed,
      thickness: 12,
      brushProfile: DrawingBrushProfileId.crayon,
      textureSeed: 41,
    );

    final first = await _render(tester, stroke);
    final second = await _render(tester, stroke);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    expect(await _rgba(tester, first), await _rgba(tester, second));
  });

  testWidgets('a crayon tap stays within its pressure-adjusted width', (
    tester,
  ) async {
    const stroke = DrawingStroke(
      points: [DrawingPoint(position: Offset(32, 32), elapsedMilliseconds: 0)],
      color: AppColors.drawingRed,
      thickness: 12,
      brushProfile: DrawingBrushProfileId.crayon,
      textureSeed: 41,
    );

    final image = await _renderStroke(tester, stroke);
    addTearDown(image.dispose);

    final bounds = await _paintedBounds(tester, image);
    // 크레파스 자국은 선 굵기보다 번지지만 프로필이 정한 범위 안에 있어야 한다.
    final limit =
        DrawingStrokeRenderer.footprintFor(DrawingBrushProfileId.crayon, 12) *
            (1 + DrawingStrokeRenderer.crayon.stampScaleJitter) +
        2;
    expect(bounds.width, lessThanOrEqualTo(limit));
    expect(bounds.height, lessThanOrEqualTo(limit));
  });

  testWidgets('crayon taps are deterministic for a seed and textured by seed', (
    tester,
  ) async {
    const base = DrawingStroke(
      points: [DrawingPoint(position: Offset(32, 32), elapsedMilliseconds: 0)],
      color: AppColors.drawingRed,
      thickness: 12,
      brushProfile: DrawingBrushProfileId.crayon,
      textureSeed: 41,
    );
    final first = await _renderStroke(tester, base);
    final second = await _renderStroke(tester, base);
    final other = await _renderStroke(tester, base.copyWith(textureSeed: 42));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(other.dispose);

    expect(await _rgba(tester, first), await _rgba(tester, second));
    expect(await _rgba(tester, first), isNot(await _rgba(tester, other)));
  });
}

Future<ui.Image> _render(WidgetTester tester, DrawingStroke stroke) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: SizedBox.square(
          dimension: 64,
          child: DrawingCanvas(
            strokes: const [],
            actions: const [],
            onPointerDown: (_) {},
            onPointerMove: (_) {},
            onPointerUp: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: SizedBox.square(
          dimension: 64,
          child: DrawingCanvas(
            strokes: const [],
            actions: [DrawingStrokeAction(id: 1, stroke: stroke)],
            onPointerDown: (_) {},
            onPointerMove: (_) {},
            onPointerUp: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
}

Future<Uint8List> _rgba(WidgetTester tester, ui.Image image) async =>
    (await tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    }))!;

Future<ui.Image> _renderStroke(
  WidgetTester tester,
  DrawingStroke stroke,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  DrawingStrokeRenderer.paint(canvas, stroke);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(64, 64));
  picture.dispose();
  return image!;
}

Future<Rect> _paintedBounds(WidgetTester tester, ui.Image image) async =>
    (await tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      var left = image.width;
      var top = image.height;
      var right = -1;
      var bottom = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (bytes[(y * image.width + x) * 4 + 3] > 16) {
            left = x < left ? x : left;
            top = y < top ? y : top;
            right = x > right ? x : right;
            bottom = y > bottom ? y : bottom;
          }
        }
      }
      return Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right + 1.0,
        bottom + 1.0,
      );
    }))!;
