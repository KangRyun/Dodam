@Tags(['tool'])
library;

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 손그림 도구 원화의 종이 배경을 빼고 아이콘 에셋으로 굽는 일회성 도구다.
///
///   flutter test tool/brushes/import_hand_drawn_tools_test.dart
///
/// 원화는 크림색 종이 위에 그려져 있다. 도구 몸통에도 흰색이 있어 색만 보고
/// 지우면 몸통까지 뚫린다. 테두리가 도형을 완전히 감싸므로 네 귀퉁이에서
/// 물채우기로 번져 나가 바깥 배경만 지운다.
const _source =
    r'C:\Users\SSAFY\Desktop\프로젝트 자료\캔버스 디자인 자료\도구\지우개.png';
const _target = 'assets/canvas/tools/eraser_base.png';
const _size = 256;

/// 배경으로 볼 색 차이다. 종이 얼룩까지 같이 지울 만큼은 넉넉하게 둔다.
const _tolerance = 30;

void main() {
  test('eraser icon keeps only the drawing', () async {
    final file = File(_source);
    expect(file.existsSync(), isTrue, reason: _source);

    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    expect(raw, isNotNull);

    final pixels = raw!.buffer.asUint8List();
    final seed = _rgb(pixels, 0);
    final removed = List<bool>.filled(width * height, false);
    final queue = Queue<int>()
      ..addAll([0, width - 1, (height - 1) * width, height * width - 1]);

    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      if (removed[index]) continue;
      if (!_matches(_rgb(pixels, index * 4), seed)) continue;
      removed[index] = true;
      final x = index % width;
      final y = index ~/ width;
      if (x > 0) queue.add(index - 1);
      if (x < width - 1) queue.add(index + 1);
      if (y > 0) queue.add(index - width);
      if (y < height - 1) queue.add(index + width);
    }

    var left = width, top = height, right = -1, bottom = -1;
    for (var index = 0; index < removed.length; index++) {
      if (removed[index]) {
        pixels[index * 4 + 3] = 0;
        continue;
      }
      final x = index % width;
      final y = index ~/ width;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
    expect(right, greaterThan(left));

    final keyed = await _decodeRgba(pixels, width, height);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      keyed,
      ui.Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1, bottom + 1),
      const ui.Rect.fromLTWH(0, 0, _size * 0.92, _size * 0.92).shift(
        const ui.Offset(_size * 0.04, _size * 0.04),
      ),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final baked = await picture.toImage(_size, _size);
    picture.dispose();
    keyed.dispose();

    final png = await baked.toByteData(format: ui.ImageByteFormat.png);
    baked.dispose();
    expect(png, isNotNull);
    File(_target).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

List<int> _rgb(Uint8List pixels, int offset) => [
  pixels[offset],
  pixels[offset + 1],
  pixels[offset + 2],
];

bool _matches(List<int> a, List<int> b) =>
    (a[0] - b[0]).abs() <= _tolerance &&
    (a[1] - b[1]).abs() <= _tolerance &&
    (a[2] - b[2]).abs() <= _tolerance;

Future<ui.Image> _decodeRgba(Uint8List pixels, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  descriptor.dispose();
  buffer.dispose();
  codec.dispose();
  return frame.image;
}
