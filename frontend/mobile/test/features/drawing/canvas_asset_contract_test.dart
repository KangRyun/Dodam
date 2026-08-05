import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _assetPaths = <String>[
  'assets/canvas/tools/brush_base.png',
  'assets/canvas/tools/crayon_base.png',
  'assets/canvas/tools/eraser_base.png',
  'assets/canvas/tools/fill_base.png',
  'assets/canvas/tools/palette_base.png',
  'assets/canvas/tools/pencil_base.png',
  'assets/canvas/tools/masks/brush_point.png',
  'assets/canvas/tools/masks/crayon_point.png',
  'assets/canvas/tools/masks/fill_point.png',
  'assets/canvas/tools/masks/pencil_point.png',
  'assets/canvas/swatches/red.png',
  'assets/canvas/swatches/orange.png',
  'assets/canvas/swatches/yellow.png',
  'assets/canvas/swatches/green.png',
  'assets/canvas/swatches/teal.png',
  'assets/canvas/swatches/blue.png',
  'assets/canvas/swatches/purple.png',
  'assets/canvas/swatches/charcoal.png',
  'assets/canvas/frame/back.png',
  'assets/canvas/frame/undo.png',
  'assets/canvas/frame/redo.png',
  'assets/canvas/frame/save.png',
  'assets/canvas/frame/button_green.png',
  'assets/canvas/frame/button_yellow.png',
  'assets/canvas/frame/canvas_frame_mobile.png',
  'assets/canvas/frame/canvas_frame_tablet.png',
  'assets/canvas/frame/toolbar_frame_mobile.png',
  'assets/canvas/frame/toolbar_frame_tablet.png',
  'assets/canvas/frame/frame_patch_graphite.png',
  'assets/canvas/frame/paper_texture.png',
  'assets/canvas/frame/selected_tool.png',
  'assets/canvas/frame/slider_track.png',
  'assets/canvas/frame/speech_bubble.png',
  'assets/canvas/frame/spiral_mobile.png',
  'assets/canvas/frame/spiral_tablet.png',
];

Future<ui.Image> _decodeAsset(WidgetTester tester, String path) async {
  return (await tester.runAsync(() async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }))!;
}

Future<({Set<int> colors, int transparentPixels})> _pixelProfile(
  WidgetTester tester,
  ui.Image image,
) async => (await tester.runAsync(() async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final colors = <int>{};
  var transparentPixels = 0;
  for (var offset = 0; offset < bytes.length; offset += 4) {
    final alpha = bytes[offset + 3];
    if (alpha < 16) {
      transparentPixels++;
      continue;
    }
    colors.add(
      (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2],
    );
  }
  return (colors: colors, transparentPixels: transparentPixels);
}))!;

void main() {
  testWidgets(
    'registers every approved canvas asset with expected dimensions',
    (tester) async {
      for (final path in _assetPaths) {
        await rootBundle.load(path);
      }

      for (final path in _assetPaths.where(
        (path) => path.contains('/tools/') && path.endsWith('.png'),
      )) {
        final image = await _decodeAsset(tester, path);
        expect(image.width, 256, reason: path);
        expect(image.height, 256, reason: path);
        image.dispose();
      }

      for (final path in _assetPaths.where(
        (path) => path.contains('/swatches/'),
      )) {
        final image = await _decodeAsset(tester, path);
        expect(image.width, 48, reason: path);
        expect(image.height, 48, reason: path);
        image.dispose();
      }
    },
  );

  testWidgets('every quick swatch keeps a transparent textured crayon mark', (
    tester,
  ) async {
    for (final path in _assetPaths.where(
      (path) => path.contains('/swatches/'),
    )) {
      final image = await _decodeAsset(tester, path);
      final profile = await _pixelProfile(tester, image);

      expect(
        profile.transparentPixels,
        greaterThan(0),
        reason: '$path must keep transparent padding around the crayon mark',
      );
      expect(
        profile.colors.length,
        greaterThan(24),
        reason: '$path must retain visible crayon texture',
      );
      image.dispose();
    }
  });
}
