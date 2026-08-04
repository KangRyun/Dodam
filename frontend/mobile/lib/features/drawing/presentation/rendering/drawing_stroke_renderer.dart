import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/drawing_stroke.dart';

@immutable
final class DrawingBrushProfile {
  const DrawingBrushProfile({
    required this.id,
    required this.opacity,
    required this.pressureWidthFactor,
    required this.texturePasses,
  });

  final DrawingBrushProfileId id;
  final double opacity;
  final double pressureWidthFactor;
  final int texturePasses;
}

abstract final class DrawingStrokeRenderer {
  static const legacyPen = DrawingBrushProfile(
    id: DrawingBrushProfileId.legacyPen,
    opacity: 1,
    pressureWidthFactor: 0,
    texturePasses: 1,
  );
  static const crayon = DrawingBrushProfile(
    id: DrawingBrushProfileId.crayon,
    opacity: .42,
    pressureWidthFactor: .15,
    texturePasses: 3,
  );
  static const pencil = DrawingBrushProfile(
    id: DrawingBrushProfileId.pencil,
    opacity: .72,
    pressureWidthFactor: .35,
    texturePasses: 1,
  );
  static const brush = DrawingBrushProfile(
    id: DrawingBrushProfileId.brush,
    opacity: .90,
    pressureWidthFactor: .65,
    texturePasses: 1,
  );

  static DrawingBrushProfile profileFor(DrawingBrushProfileId id) =>
      switch (id) {
        DrawingBrushProfileId.legacyPen => legacyPen,
        DrawingBrushProfileId.crayon => crayon,
        DrawingBrushProfileId.pencil => pencil,
        DrawingBrushProfileId.brush => brush,
      };

  static void paint(Canvas canvas, DrawingStroke stroke) {
    if (stroke.brushProfile == DrawingBrushProfileId.legacyPen ||
        stroke.tool == DrawingTool.eraser) {
      _paintLegacy(canvas, stroke);
      return;
    }
    if (stroke.points.isEmpty) return;
    final profile = profileFor(stroke.brushProfile);
    if (stroke.points.length == 1) {
      final width = _widthFor(
        stroke.thickness,
        stroke.points.single.pressure ?? 1,
        profile.pressureWidthFactor,
      );
      _paintDot(canvas, stroke, profile, width);
      return;
    }

    for (
      var segmentIndex = 0;
      segmentIndex < stroke.points.length - 1;
      segmentIndex++
    ) {
      final start = stroke.points[segmentIndex];
      final end = stroke.points[segmentIndex + 1];
      final pressure = ((start.pressure ?? 1) + (end.pressure ?? 1)) / 2;
      final width = _widthFor(
        stroke.thickness,
        pressure,
        profile.pressureWidthFactor,
      );
      for (var passIndex = 0; passIndex < profile.texturePasses; passIndex++) {
        final sample = _sample32(
          stroke.textureSeed + segmentIndex * profile.texturePasses + passIndex,
        );
        if (profile.id == DrawingBrushProfileId.crayon && sample < .18) {
          continue;
        }
        final passWidth = profile.id == DrawingBrushProfileId.crayon
            ? width * (.86 + .18 * sample)
            : width;
        final offset = profile.id == DrawingBrushProfileId.crayon
            ? _perpendicularOffset(
                start.position,
                end.position,
                (sample * 2 - 1) * .10 * width,
              )
            : Offset.zero;
        final path = Path()
          ..moveTo(start.position.dx + offset.dx, start.position.dy + offset.dy)
          ..lineTo(end.position.dx + offset.dx, end.position.dy + offset.dy);
        canvas.drawPath(path, _paintFor(stroke, profile.opacity, passWidth));
      }
    }
  }

  static void _paintDot(
    Canvas canvas,
    DrawingStroke stroke,
    DrawingBrushProfile profile,
    double width,
  ) {
    final point = stroke.points.single.position;
    if (profile.id != DrawingBrushProfileId.crayon) {
      canvas.drawCircle(
        point,
        width / 2,
        _dotPaintFor(stroke, profile.opacity),
      );
      return;
    }
    for (var passIndex = 0; passIndex < profile.texturePasses; passIndex++) {
      final sample = _sample32(stroke.textureSeed + passIndex);
      final passWidth = width * (.86 + .18 * sample);
      canvas.drawCircle(
        point,
        passWidth / 2,
        _dotPaintFor(stroke, profile.opacity),
      );
    }
  }

  static void _paintLegacy(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..blendMode = stroke.tool == DrawingTool.eraser
          ? BlendMode.clear
          : BlendMode.srcOver
      ..strokeWidth = stroke.thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.single.position,
        stroke.thickness / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()
      ..moveTo(
        stroke.points.first.position.dx,
        stroke.points.first.position.dy,
      );
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.position.dx, point.position.dy);
    }
    canvas.drawPath(path, paint);
  }

  static Paint _paintFor(DrawingStroke stroke, double opacity, double width) =>
      Paint()
        ..color = stroke.color.withValues(alpha: stroke.color.a * opacity)
        ..blendMode = BlendMode.srcOver
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

  static Paint _dotPaintFor(DrawingStroke stroke, double opacity) => Paint()
    ..color = stroke.color.withValues(alpha: stroke.color.a * opacity)
    ..blendMode = BlendMode.srcOver
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static double _widthFor(double thickness, double pressure, double factor) =>
      (thickness * (1 - factor + factor * pressure)).clamp(.5, double.infinity);

  static Offset _perpendicularOffset(Offset start, Offset end, double amount) {
    final delta = end - start;
    final length = delta.distance;
    if (length == 0) return Offset.zero;
    return Offset(-delta.dy / length * amount, delta.dx / length * amount);
  }

  static double _sample32(int value) {
    var mixed = value & 0xffffffff;
    mixed = ((mixed ^ (mixed >> 16)) * 0x45d9f3b) & 0xffffffff;
    mixed = ((mixed ^ (mixed >> 16)) * 0x45d9f3b) & 0xffffffff;
    mixed = (mixed ^ (mixed >> 16)) & 0xffffffff;
    return mixed / 0x100000000;
  }
}
