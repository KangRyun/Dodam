import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dodam/features/drawing/application/drawing_fill_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _wall = 0xFF24313D;
const _inside = 0xFFF4F1DE;
const _replacement = Color(0xFFEF476F);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = ScanlineDrawingFillEngine();

  test('fills only the closed four-connected region', () async {
    final source = await _imageFromArgbRows(const [
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _wall, _wall, _wall, _wall],
    ]);
    addTearDown(source.dispose);

    final patch = await engine.createPatch(
      source: source,
      seed: const Offset(2, 2),
      replacement: _replacement,
    );
    addTearDown(patch!.image.dispose);

    expect(patch.documentSize, const Size(5, 5));
    expect(await _opaqueCoordinates(patch.image), {
      const Point(1, 1),
      const Point(2, 1),
      const Point(3, 1),
      const Point(1, 2),
      const Point(2, 2),
      const Point(3, 2),
      const Point(1, 3),
      const Point(2, 3),
      const Point(3, 3),
    });
    expect(await _rgbaAt(patch.image, 2, 2), [0xEF, 0x47, 0x6F, 0xFF]);
    expect(await _rgbaAt(patch.image, 0, 0), [0, 0, 0, 0]);
  });

  test('includes channel differences of 24 but excludes 25', () async {
    final source = await _imageFromArgbRows(const [
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, 0xFF646464, 0xFF7C7C7C, 0xFF7D6464, _wall],
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _wall, _wall, _wall, _wall],
    ]);
    addTearDown(source.dispose);

    final patch = await engine.createPatch(
      source: source,
      seed: const Offset(1, 1),
      replacement: _replacement,
    );
    addTearDown(patch!.image.dispose);

    expect(await _opaqueCoordinates(patch.image), {
      const Point(1, 1),
      const Point(2, 1),
    });
  });

  test('fills a transparent source region with an opaque color', () async {
    final source = await _imageFromArgbRows(const [
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, 0, 0, _wall, _wall],
      [_wall, 0, _wall, _wall, _wall],
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _wall, _wall, _wall, _wall],
    ]);
    addTearDown(source.dispose);

    final patch = await engine.createPatch(
      source: source,
      seed: const Offset(1, 1),
      replacement: _replacement,
    );
    addTearDown(patch!.image.dispose);

    expect(await _opaqueCoordinates(patch.image), {
      const Point(1, 1),
      const Point(2, 1),
      const Point(1, 2),
    });
  });

  test('returns a transparent patch for a transparent replacement', () async {
    final source = await _imageFromArgbRows(const [
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _wall, _wall, _wall, _wall],
    ]);
    addTearDown(source.dispose);

    final patch = await engine.createPatch(
      source: source,
      seed: const Offset(2, 2),
      replacement: const Color(0x00000000),
    );
    addTearDown(patch!.image.dispose);

    expect(await _rgba(patch.image), everyElement(0));
  });

  test('does not cross diagonal contact or wrap between rows', () async {
    final source = await _imageFromArgbRows(const [
      [_wall, _inside, _wall, _wall, _inside],
      [_inside, _wall, _wall, _wall, _wall],
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _wall, _wall, _wall, _wall],
    ]);
    addTearDown(source.dispose);

    final patch = await engine.createPatch(
      source: source,
      seed: const Offset(0, 1),
      replacement: _replacement,
      tolerance: 0,
    );
    addTearDown(patch!.image.dispose);

    expect(await _opaqueCoordinates(patch.image), {const Point(0, 1)});
  });

  test('returns null for an out-of-bounds or non-finite seed', () async {
    final source = await _imageFromArgbRows(
      List.generate(5, (_) => List.filled(5, _inside)),
    );
    addTearDown(source.dispose);

    for (final seed in [
      const Offset(-0.01, 0),
      const Offset(0, -0.01),
      const Offset(5, 0),
      const Offset(0, 5),
      const Offset(double.infinity, 0),
      const Offset(double.nan, 0),
    ]) {
      expect(
        await engine.createPatch(
          source: source,
          seed: seed,
          replacement: _replacement,
        ),
        isNull,
        reason: 'seed $seed must not address an image pixel',
      );
    }
  });

  test('returns null when replacement equals the seed color', () async {
    final source = await _imageFromArgbRows(const [
      [_wall, _wall, _wall, _wall, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _inside, _inside, _inside, _wall],
      [_wall, _wall, _wall, _wall, _wall],
    ]);
    addTearDown(source.dispose);

    expect(
      await engine.createPatch(
        source: source,
        seed: const Offset(2, 2),
        replacement: const Color(_inside),
      ),
      isNull,
    );
  });

  test(
    'is deterministic and leaves the source image owned by the caller',
    () async {
      final source = await _imageFromArgbRows(const [
        [_wall, _wall, _wall, _wall, _wall],
        [_wall, _inside, _inside, _inside, _wall],
        [_wall, _inside, _inside, _inside, _wall],
        [_wall, _inside, _inside, _inside, _wall],
        [_wall, _wall, _wall, _wall, _wall],
      ]);
      addTearDown(source.dispose);
      final before = await _rgba(source);

      final first = await engine.createPatch(
        source: source,
        seed: const Offset(2, 2),
        replacement: _replacement,
      );
      final second = await engine.createPatch(
        source: source,
        seed: const Offset(2, 2),
        replacement: _replacement,
      );
      addTearDown(first!.image.dispose);
      addTearDown(second!.image.dispose);

      expect(
        await _rgba(first.image),
        orderedEquals(await _rgba(second.image)),
      );
      expect(await _rgba(source), orderedEquals(before));
      expect(identical(first.image, source), isFalse);
      expect(identical(second.image, source), isFalse);
    },
  );
}

Future<ui.Image> _imageFromArgbRows(List<List<int>> rows) async {
  final height = rows.length;
  final width = rows.first.length;
  final pixels = Uint8List(width * height * 4);

  for (var y = 0; y < height; y++) {
    assert(rows[y].length == width);
    for (var x = 0; x < width; x++) {
      final argb = rows[y][x];
      final alpha = (argb >> 24) & 0xFF;
      final offset = (y * width + x) * 4;
      pixels[offset] = _premultiply((argb >> 16) & 0xFF, alpha);
      pixels[offset + 1] = _premultiply((argb >> 8) & 0xFF, alpha);
      pixels[offset + 2] = _premultiply(argb & 0xFF, alpha);
      pixels[offset + 3] = alpha;
    }
  }

  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  try {
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

int _premultiply(int channel, int alpha) => (channel * alpha + 127) ~/ 255;

Future<Uint8List> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('Image did not expose raw RGBA bytes');
  return Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

Future<List<int>> _rgbaAt(ui.Image image, int x, int y) async {
  final bytes = await _rgba(image);
  final offset = (y * image.width + x) * 4;
  return bytes.sublist(offset, offset + 4);
}

Future<Set<Point<int>>> _opaqueCoordinates(ui.Image image) async {
  final bytes = await _rgba(image);
  final result = <Point<int>>{};
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (bytes[(y * image.width + x) * 4 + 3] != 0) {
        result.add(Point(x, y));
      }
    }
  }
  return result;
}
