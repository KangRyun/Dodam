@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 도구 아이콘 원화(v2)를 앱 에셋 이름으로 들여오는 일회성 도구다.
///
///   flutter test tool/brushes/import_tool_icons_test.dart
///
/// 원화는 1024x1024 라 36px 아이콘에는 너무 크다. 256 으로 줄여 담는다.
/// CI 가 test/ 만 돌도록 tool/ 아래 둔다.
const _source =
    r'C:\Users\SSAFY\Desktop\프로젝트 자료\캔버스 디자인 자료\도구_v2';
const _size = 256;

/// 원화 파일 → 앱 에셋 경로.
const _files = <String, String>{
  'crayon-base.png': 'assets/canvas/tools/crayon_base.png',
  'pencil-base.png': 'assets/canvas/tools/pencil_base.png',
  'brush-base.png': 'assets/canvas/tools/brush_base.png',
  'paint-base.png': 'assets/canvas/tools/fill_base.png',
  'eraser-fixed.png': 'assets/canvas/tools/eraser_base.png',
  'palette-fixed.png': 'assets/canvas/tools/palette_base.png',
  'crayon-tint-mask.png': 'assets/canvas/tools/masks/crayon_point.png',
  'pencil-tint-mask.png': 'assets/canvas/tools/masks/pencil_point.png',
  'brush-tint-mask.png': 'assets/canvas/tools/masks/brush_point.png',
  'paint-tint-mask.png': 'assets/canvas/tools/masks/fill_point.png',
};

void main() {
  test('tool icons are imported at icon size', () async {
    for (final entry in _files.entries) {
      final source = File('$_source${Platform.pathSeparator}${entry.key}');
      expect(source.existsSync(), isTrue, reason: entry.key);

      final codec = await ui.instantiateImageCodec(
        await source.readAsBytes(),
        targetWidth: _size,
        targetHeight: _size,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      expect(png, isNotNull, reason: entry.value);

      File(entry.value)
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}
