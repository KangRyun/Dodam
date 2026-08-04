@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 색 견본 원화의 크기·중심을 맞추는 일회성 도구다.
///
///   flutter test tool/brushes/normalize_swatches_test.dart
///
/// 원화는 같은 48x48 canvas 를 쓰지만 안에 그려진 자국 크기가 36~44 로 제각각이라
/// 툴바에 늘어놓으면 어떤 색은 작고 어떤 색은 치우쳐 보인다. 자국만 잘라 같은
/// 크기로 가운데 다시 그린다. CI 가 test/ 만 돌도록 tool/ 아래 둔다.
const _dir = 'assets/canvas/swatches';
const _canvas = 48.0;

/// 자국이 차지할 크기다. 남는 여백이 선택 링과 겹치지 않을 만큼 남긴다.
const _ink = 44.0;

const _names = <String>[
  'red',
  'orange',
  'yellow',
  'green',
  'teal',
  'blue',
  'purple',
  'charcoal',
];

void main() {
  test('swatches share one ink size and centre', () async {
    for (final name in _names) {
      final file = File('$_dir/$name.png');
      expect(file.existsSync(), isTrue, reason: name);

      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      final source = frame.image;
      codec.dispose();
      final raw = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(raw, isNotNull, reason: name);

      final pixels = raw!.buffer.asUint8List();
      final width = source.width;
      var left = width, top = source.height, right = -1, bottom = -1;
      for (var i = 3; i < pixels.length; i += 4) {
        if (pixels[i] <= 20) continue;
        final index = i ~/ 4;
        final x = index % width;
        final y = index ~/ width;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
      expect(right, greaterThan(left), reason: name);

      // 가로세로 비율은 원화 그대로 두고 긴 변만 _ink 에 맞춘다. 억지로 정사각형
      // 으로 늘이면 동글동글하던 자국이 찌그러진다.
      final inkWidth = (right - left + 1).toDouble();
      final inkHeight = (bottom - top + 1).toDouble();
      final scale = _ink / (inkWidth > inkHeight ? inkWidth : inkHeight);
      final target = Rect.fromCenter(
        center: const Offset(_canvas / 2, _canvas / 2),
        width: inkWidth * scale,
        height: inkHeight * scale,
      );

      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        source,
        Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          right + 1,
          bottom + 1,
        ),
        target,
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final baked = await picture.toImage(_canvas.toInt(), _canvas.toInt());
      picture.dispose();
      source.dispose();

      final png = await baked.toByteData(format: ui.ImageByteFormat.png);
      baked.dispose();
      expect(png, isNotNull, reason: name);
      file.writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}
