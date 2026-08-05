@Tags(['tool'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

/// 원화(흰 배경 + 회색 자국)를 알파 마스크로 바꿔 assets 에 굽는 일회성 도구다.
///
///   flutter test test/tools/build_brush_masks_test.dart
///
/// 결과는 검정 픽셀 + `alpha = 255 - 밝기` 다. 획을 그릴 때 색을 입혀 찍는다.
const _source = r'C:\Users\SSAFY\Desktop\프로젝트 자료\캔버스 디자인 자료\브러시';
const _target = 'assets/canvas/brushes';
// CI 가 test/ 만 돌도록 tool/ 아래 둔다. 원화가 있는 로컬에서만 수동 실행한다.
const _size = 256.0;

const _files = <String, String>{
  'pencil1.png': 'pencil_grain.png',
  'pencil2.png': 'brush_tip.png',
  'pencil3.png': 'soft_grain.png',
  '크레파스_브러쉬.png': 'crayon_crumb.png',
};

void main() {
  test('brush stamps are baked into alpha masks', () async {
    final outDir = Directory(_target);
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    for (final entry in _files.entries) {
      final sourceFile = File('$_source${Platform.pathSeparator}${entry.key}');
      expect(sourceFile.existsSync(), isTrue, reason: entry.key);

      final codec = await ui.instantiateImageCodec(
        await sourceFile.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final source = frame.image;
      final width = source.width;
      final height = source.height;
      final raw = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
      source.dispose();
      codec.dispose();
      expect(raw, isNotNull, reason: entry.key);

      final pixels = raw!.buffer.asUint8List();
      final mask = Uint8List(pixels.length);
      var left = width, top = height, right = -1, bottom = -1;
      for (var i = 0; i < pixels.length; i += 4) {
        final luminance =
            (pixels[i] * 0.299 + pixels[i + 1] * 0.587 + pixels[i + 2] * 0.114);
        // 원본 알파가 0 인 여백은 자국이 아니다.
        final coverage = pixels[i + 3] == 0
            ? 0
            : (255 - luminance).round().clamp(0, 255);
        mask[i + 3] = coverage;
        // 원화는 여백이 넓다. 자국만 남겨야 굵기 값이 실제 선 굵기와 맞는다.
        if (coverage < 10) continue;
        final x = (i ~/ 4) % width;
        final y = (i ~/ 4) ~/ width;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
      expect(right, greaterThan(left), reason: entry.key);

      final full = await _decodeRgba(mask, width, height);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        full,
        Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          right + 1,
          bottom + 1,
        ),
        const Rect.fromLTWH(0, 0, _size, _size),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final baked = await picture.toImage(_size.toInt(), _size.toInt());
      picture.dispose();
      full.dispose();
      final png = await baked.toByteData(format: ui.ImageByteFormat.png);
      baked.dispose();
      expect(png, isNotNull, reason: entry.value);
      File('$_target/${entry.value}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}

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
