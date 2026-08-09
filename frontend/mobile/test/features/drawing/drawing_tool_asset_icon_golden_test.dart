import 'dart:ui' as ui;

import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:dodam/features/drawing/presentation/widgets/canvas_tool_asset_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('canvas tool artwork keeps fixed regions stable across colors', (
    tester,
  ) async {
    const tools = CanvasToolArtwork.values;
    const colors = [
      AppColors.drawingInk,
      AppColors.drawingRed,
      AppColors.drawingBlue,
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: _ToolArtworkGolden(colors: colors, tools: tools),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CanvasToolAssetIcon), findsNWidgets(18));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    final contactSheet = await _captureProductionContactSheet(tester);
    await expectLater(
      contactSheet,
      matchesGoldenFile('goldens/canvas_tool_asset_icons.png'),
    );
    contactSheet.dispose();
  });
}

Future<ui.Image> _captureProductionContactSheet(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(AppColors.canvasWarm, BlendMode.src);
  final captures = <ui.Image>[];

  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < CanvasToolArtwork.values.length; column++) {
      final artwork = CanvasToolArtwork.values[column];
      final boundaryFinder = find
          .byKey(ValueKey('canvas-tool-boundary-${artwork.name}'))
          .at(row);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        boundaryFinder,
      );
      final capture = await boundary.toImage(pixelRatio: 1);
      captures.add(capture);
      canvas.drawImage(capture, Offset(column * 64, row * 64), Paint());
    }
  }

  final contactSheet = await recorder.endRecording().toImage(64 * 6, 64 * 3);
  for (final capture in captures) {
    capture.dispose();
  }
  return contactSheet;
}

final class _ToolArtworkGolden extends StatelessWidget {
  const _ToolArtworkGolden({required this.colors, required this.tools});

  final List<Color> colors;
  final List<CanvasToolArtwork> tools;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64 * 6,
    height: 64 * 3,
    child: Column(
      children: [
        for (final color in colors)
          Row(
            children: [
              for (final tool in tools)
                CanvasToolAssetIcon(artwork: tool, pointColor: color, size: 64),
            ],
          ),
      ],
    ),
  );
}
