import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:dodam/features/drawing/presentation/widgets/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PEN 렌더링은 기존 색상 픽셀을 유지한다', (tester) async {
    final image = await _renderCanvas(tester, strokes: [_pen()]);
    addTearDown(image.dispose);

    expect(await _pixel(tester, image, 32, 32), _isRed);
  });

  testWidgets('빈 흰 Canvas를 지우면 불투명한 흰 픽셀을 유지한다', (tester) async {
    final image = await _renderCanvas(tester, strokes: [_eraser(width: 14)]);
    addTearDown(image.dispose);

    expect(await _pixel(tester, image, 32, 32), _isOpaqueWhite);
  });

  testWidgets('PEN 위를 지난 ERASER가 실제 픽셀을 흰색으로 삭제한다', (tester) async {
    final image = await _renderCanvas(
      tester,
      strokes: [_pen(width: 14), _eraser(width: 8)],
    );
    addTearDown(image.dispose);

    expect(await _pixel(tester, image, 32, 32), _isOpaqueWhite);
    expect(await _pixel(tester, image, 32, 26), _isRed);
  });

  testWidgets('Resume MemoryImage 위를 지난 ERASER가 복원 픽셀을 삭제한다', (tester) async {
    final background = await _solidPng(tester, AppColors.drawingBlue);
    final image = await _renderCanvas(
      tester,
      strokes: [_eraser(width: 14)],
      backgroundBytes: background,
    );
    addTearDown(image.dispose);

    expect(
      find.byKey(const ValueKey('draft-background-image')),
      findsOneWidget,
    );
    expect(await _pixel(tester, image, 32, 32), _isOpaqueWhite);
    expect(await _pixel(tester, image, 32, 20), _isBlue);
  });

  testWidgets('마지막 ERASER를 Undo한 재합성은 원본 픽셀을 복원한다', (tester) async {
    final background = await _solidPng(tester, AppColors.drawingBlue);
    final erased = await _renderCanvas(
      tester,
      strokes: [_eraser(width: 14)],
      backgroundBytes: background,
    );
    expect(await _pixel(tester, erased, 32, 32), _isOpaqueWhite);
    erased.dispose();

    final restored = await _renderCanvas(
      tester,
      strokes: const [],
      backgroundBytes: background,
    );
    addTearDown(restored.dispose);
    expect(await _pixel(tester, restored, 32, 32), _isBlue);
  });

  testWidgets('ERASER 얇게·보통·굵게는 삭제 폭이 순서대로 증가한다', (tester) async {
    final background = await _solidPng(tester, AppColors.drawingBlue);
    final erasedWidths = <int>[];

    for (final width in [4.0, 8.0, 14.0]) {
      final image = await _renderCanvas(
        tester,
        strokes: [_eraser(width: width)],
        backgroundBytes: background,
      );
      erasedWidths.add(await _whitePixelCountAtX(tester, image, 32));
      image.dispose();
    }

    expect(erasedWidths[0], lessThan(erasedWidths[1]));
    expect(erasedWidths[1], lessThan(erasedWidths[2]));
  });

  testWidgets('Draft와 Final이 공유하는 PNG 캡처에 지운 결과가 포함된다', (tester) async {
    final background = await _solidPng(tester, AppColors.drawingBlue);
    final captured = await _renderCanvas(
      tester,
      strokes: [_eraser(width: 14)],
      backgroundBytes: background,
    );
    final decoded = await tester.runAsync(() async {
      final pngData = await captured.toByteData(format: ui.ImageByteFormat.png);
      captured.dispose();
      final codec = await ui.instantiateImageCodec(
        pngData!.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    expect(decoded, isNotNull);
    addTearDown(decoded!.dispose);

    expect(await _pixel(tester, decoded, 32, 32), _isOpaqueWhite);
    expect(await _pixel(tester, decoded, 32, 20), _isBlue);
  });
}

Future<ui.Image> _renderCanvas(
  WidgetTester tester, {
  required List<DrawingStroke> strokes,
  Uint8List? backgroundBytes,
}) async {
  final boundaryKey = GlobalKey();
  final backgroundProvider = backgroundBytes == null
      ? null
      : MemoryImage(backgroundBytes);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox.square(
              dimension: 64,
              child: DrawingCanvas(
                strokes: strokes,
                backgroundImage: backgroundProvider,
                onPointerDown: (_) {},
                onPointerMove: (_) {},
                onPointerUp: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (backgroundProvider != null) {
    await tester.runAsync(
      () => precacheImage(backgroundProvider, boundaryKey.currentContext!),
    );
    await tester.pump();
  }
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
}

DrawingStroke _pen({double width = 8}) => DrawingStroke(
  color: AppColors.drawingRed,
  thickness: width,
  points: _horizontalPoints,
);

DrawingStroke _eraser({required double width}) => DrawingStroke(
  tool: DrawingTool.eraser,
  color: AppColors.drawingRed,
  thickness: width,
  points: _horizontalPoints,
);

const _horizontalPoints = [
  DrawingPoint(position: Offset(8, 32), elapsedMilliseconds: 0),
  DrawingPoint(position: Offset(56, 32), elapsedMilliseconds: 20),
];

Future<Uint8List> _solidPng(WidgetTester tester, Color color) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 64),
        Paint()..color = color,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;

Future<Color> _pixel(WidgetTester tester, ui.Image image, int x, int y) async =>
    (await tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        bytes[offset + 3],
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
      );
    }))!;

Future<int> _whitePixelCountAtX(
  WidgetTester tester,
  ui.Image image,
  int x,
) async => (await tester.runAsync(() async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var count = 0;
  for (var y = 0; y < image.height; y++) {
    final offset = (y * image.width + x) * 4;
    if (bytes[offset] > 242 &&
        bytes[offset + 1] > 242 &&
        bytes[offset + 2] > 242) {
      count += 1;
    }
  }
  return count;
}))!;

Matcher get _isOpaqueWhite => isA<Color>()
    .having((color) => color.a, 'alpha', 1)
    .having((color) => color.r, 'red', greaterThan(0.98))
    .having((color) => color.g, 'green', greaterThan(0.98))
    .having((color) => color.b, 'blue', greaterThan(0.98));

Matcher get _isRed => isA<Color>()
    .having((color) => color.r, 'red', greaterThan(0.7))
    .having((color) => color.g, 'green', lessThan(0.6))
    .having((color) => color.b, 'blue', lessThan(0.6));

Matcher get _isBlue => isA<Color>()
    .having((color) => color.b, 'blue', greaterThan(0.6))
    .having((color) => color.r, 'red', lessThan(0.5));
