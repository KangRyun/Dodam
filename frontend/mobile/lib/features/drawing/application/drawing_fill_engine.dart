import 'dart:typed_data';
import 'dart:ui' as ui;

final class DrawingFillPatch {
  const DrawingFillPatch({required this.image, required this.documentSize});

  final ui.Image image;
  final ui.Size documentSize;
}

abstract interface class DrawingFillEngine {
  Future<DrawingFillPatch?> createPatch({
    required ui.Image source,
    required ui.Offset seed,
    required ui.Color replacement,
    int tolerance = 24,
  });
}

final class ScanlineDrawingFillEngine implements DrawingFillEngine {
  const ScanlineDrawingFillEngine();

  @override
  Future<DrawingFillPatch?> createPatch({
    required ui.Image source,
    required ui.Offset seed,
    required ui.Color replacement,
    int tolerance = 24,
  }) async {
    final width = source.width;
    final height = source.height;
    if (!seed.dx.isFinite || !seed.dy.isFinite) return null;

    final seedX = seed.dx.floor();
    final seedY = seed.dy.floor();
    if (seedX < 0 || seedX >= width || seedY < 0 || seedY >= height) {
      return null;
    }

    final byteData = await source.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw StateError('Unable to read source image as raw RGBA');
    }
    final sourceBytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    final replacementBytes = _premultipliedRgba(replacement);
    final seedByteOffset = (seedY * width + seedX) * 4;
    if (_pixelEquals(sourceBytes, seedByteOffset, replacementBytes)) {
      return null;
    }

    final targetRed = sourceBytes[seedByteOffset];
    final targetGreen = sourceBytes[seedByteOffset + 1];
    final targetBlue = sourceBytes[seedByteOffset + 2];
    final targetAlpha = sourceBytes[seedByteOffset + 3];
    final patchBytes = Uint8List(width * height * 4);
    final visited = Uint8List(width * height);
    final pending = <int>[seedY * width + seedX];

    bool matchesTarget(int pixelIndex) {
      final byteOffset = pixelIndex * 4;
      return (sourceBytes[byteOffset] - targetRed).abs() <= tolerance &&
          (sourceBytes[byteOffset + 1] - targetGreen).abs() <= tolerance &&
          (sourceBytes[byteOffset + 2] - targetBlue).abs() <= tolerance &&
          (sourceBytes[byteOffset + 3] - targetAlpha).abs() <= tolerance;
    }

    while (pending.isNotEmpty) {
      final pendingIndex = pending.removeLast();
      if (visited[pendingIndex] != 0 || !matchesTarget(pendingIndex)) {
        continue;
      }

      final y = pendingIndex ~/ width;
      var x = pendingIndex % width;
      while (x > 0) {
        final leftIndex = y * width + x - 1;
        if (visited[leftIndex] != 0 || !matchesTarget(leftIndex)) break;
        x -= 1;
      }

      var spansAbove = false;
      var spansBelow = false;
      for (; x < width; x++) {
        final pixelIndex = y * width + x;
        if (visited[pixelIndex] != 0 || !matchesTarget(pixelIndex)) break;

        visited[pixelIndex] = 1;
        final byteOffset = pixelIndex * 4;
        patchBytes.setRange(byteOffset, byteOffset + 4, replacementBytes);

        if (y > 0) {
          final aboveIndex = pixelIndex - width;
          final matchesAbove =
              visited[aboveIndex] == 0 && matchesTarget(aboveIndex);
          if (matchesAbove && !spansAbove) pending.add(aboveIndex);
          spansAbove = matchesAbove;
        }

        if (y + 1 < height) {
          final belowIndex = pixelIndex + width;
          final matchesBelow =
              visited[belowIndex] == 0 && matchesTarget(belowIndex);
          if (matchesBelow && !spansBelow) pending.add(belowIndex);
          spansBelow = matchesBelow;
        }
      }
    }

    return DrawingFillPatch(
      image: await _decodeRgba(patchBytes, width: width, height: height),
      documentSize: ui.Size(width.toDouble(), height.toDouble()),
    );
  }
}

Future<ui.Image> _decodeRgba(
  Uint8List pixels, {
  required int width,
  required int height,
}) async {
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

Uint8List _premultipliedRgba(ui.Color color) {
  final argb = color.toARGB32();
  final alpha = (argb >> 24) & 0xFF;
  return Uint8List.fromList([
    _premultiply((argb >> 16) & 0xFF, alpha),
    _premultiply((argb >> 8) & 0xFF, alpha),
    _premultiply(argb & 0xFF, alpha),
    alpha,
  ]);
}

int _premultiply(int channel, int alpha) => (channel * alpha + 127) ~/ 255;

bool _pixelEquals(Uint8List pixels, int offset, Uint8List replacement) =>
    pixels[offset] == replacement[0] &&
    pixels[offset + 1] == replacement[1] &&
    pixels[offset + 2] == replacement[2] &&
    pixels[offset + 3] == replacement[3];
