import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/drawing_stroke.dart';
import 'drawing_brush_stamps.dart';

@immutable
final class DrawingBrushProfile {
  const DrawingBrushProfile({
    required this.id,
    required this.opacity,
    required this.pressureWidthFactor,
    required this.texturePasses,
    this.stampSpacing = 0,
    this.widthScale = 1,
    this.stampScale = 1,
    this.stampScaleJitter = 0,
    this.stampAngleJitter = 0,
    this.stampFollowsDirection = false,
  });

  final DrawingBrushProfileId id;
  final double opacity;
  final double pressureWidthFactor;
  final int texturePasses;

  /// 스탬프를 찍는 간격이다. 굵기에 대한 비율이라 굵어져도 결이 유지된다.
  final double stampSpacing;

  /// Gives each physical tool a recognisable footprint at the same slider value.
  final double widthScale;

  /// 굵기 대비 스탬프 크기다. 자국이 선보다 조금 넓게 번지는 도구가 있다.
  final double stampScale;
  final double stampScaleJitter;

  /// 스탬프를 무작위로 얼마나 돌릴지다(라디안).
  final double stampAngleJitter;

  /// 참이면 스탬프가 획이 나아가는 방향을 따라 눕는다(붓끝).
  final bool stampFollowsDirection;

  bool get isStamped => stampSpacing > 0;
}

abstract final class DrawingStrokeRenderer {
  static const legacyPen = DrawingBrushProfile(
    id: DrawingBrushProfileId.legacyPen,
    opacity: 1,
    pressureWidthFactor: 0,
    texturePasses: 1,
  );

  /// 크레파스는 왁스가 뭉쳐 찍히고 중간중간 종이 결이 비친다.
  static const crayon = DrawingBrushProfile(
    id: DrawingBrushProfileId.crayon,
    opacity: .62,
    pressureWidthFactor: .15,
    texturePasses: 3,
    stampSpacing: .28,
    stampScale: 1.45,
    stampScaleJitter: .22,
    stampAngleJitter: math.pi,
  );

  /// 연필은 자국이 가늘고 촘촘하며 흑연 알갱이가 성글게 남는다.
  static const pencil = DrawingBrushProfile(
    id: DrawingBrushProfileId.pencil,
    opacity: .48,
    pressureWidthFactor: .35,
    texturePasses: 1,
    stampSpacing: .20,
    widthScale: .56,
    stampScale: .92,
    stampScaleJitter: .18,
    stampAngleJitter: math.pi,
  );

  /// 붓은 자국이 넓고 매끄럽게 이어지며 붓끝이 진행 방향으로 눕는다.
  static const brush = DrawingBrushProfile(
    id: DrawingBrushProfileId.brush,
    opacity: .72,
    pressureWidthFactor: .65,
    texturePasses: 1,
    stampSpacing: .065,
    widthScale: 1.16,
    stampScale: 1.45,
    stampScaleJitter: .035,
    stampAngleJitter: .08,
    stampFollowsDirection: true,
  );

  static DrawingBrushProfile profileFor(DrawingBrushProfileId id) =>
      switch (id) {
        DrawingBrushProfileId.legacyPen => legacyPen,
        DrawingBrushProfileId.crayon => crayon,
        DrawingBrushProfileId.pencil => pencil,
        DrawingBrushProfileId.brush => brush,
      };

  /// 굵기 [thickness] 로 그었을 때 실제로 종이에 닿는 자국의 지름이다.
  ///
  /// 스탬프로 찍는 도구는 자국이 선 굵기보다 넓게 번진다. 커서 미리보기는 이
  /// 값을 써야 아이가 보는 원과 실제로 찍히는 자국이 맞는다.
  static double footprintFor(DrawingBrushProfileId id, double thickness) {
    final profile = profileFor(id);
    return profile.isStamped
        ? thickness * profile.widthScale * profile.stampScale
        : thickness * profile.widthScale;
  }

  static void paint(Canvas canvas, DrawingStroke stroke) {
    if (stroke.brushProfile == DrawingBrushProfileId.legacyPen ||
        stroke.tool == DrawingTool.eraser) {
      _paintLegacy(canvas, stroke);
      return;
    }
    if (stroke.points.isEmpty) return;
    final profile = profileFor(stroke.brushProfile);
    // 스탬프가 아직 안 읽혔으면 단색 선으로 먼저 그린다. 다 읽히면 다시 그린다.
    final stamp = profile.isStamped
        ? DrawingBrushStamps.stampFor(profile.id)
        : null;
    if (stamp != null) {
      _paintStamped(canvas, stroke, profile, stamp);
      return;
    }
    if (stroke.points.length == 1) {
      final width = _widthFor(
        stroke.thickness * profile.widthScale,
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
        stroke.thickness * profile.widthScale,
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

  /// 획을 따라 일정한 간격으로 도구 자국을 찍는다.
  ///
  /// 간격·크기를 굵기에 대한 비율로 두어 굵게 그려도 결이 뭉개지지 않는다.
  static void _paintStamped(
    Canvas canvas,
    DrawingStroke stroke,
    DrawingBrushProfile profile,
    Image stamp,
  ) {
    final points = stroke.points;
    final source = Rect.fromLTWH(
      0,
      0,
      stamp.width.toDouble(),
      stamp.height.toDouble(),
    );
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(
        stroke.color.withValues(alpha: stroke.color.a * profile.opacity),
        BlendMode.srcIn,
      )
      ..filterQuality = FilterQuality.low
      ..isAntiAlias = true;
    var seed = stroke.textureSeed;

    if (points.length == 1) {
      final point = points.single;
      _stamp(
        canvas,
        stamp,
        source,
        paint,
        profile,
        point.position,
        _widthFor(
          stroke.thickness * profile.widthScale,
          point.pressure ?? 1,
          profile.pressureWidthFactor,
        ),
        0,
        seed,
      );
      return;
    }

    // 이전 구간에서 남은 거리를 이어받아야 이음매에서 자국이 뭉치지 않는다.
    var carried = 0.0;
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      final delta = end.position - start.position;
      final length = delta.distance;
      final pressure = ((start.pressure ?? 1) + (end.pressure ?? 1)) / 2;
      final width = _widthFor(
        stroke.thickness * profile.widthScale,
        pressure,
        profile.pressureWidthFactor,
      );
      final step = math.max(width * profile.stampSpacing, .5);
      if (length == 0) {
        if (index == 0) {
          _stamp(
            canvas,
            stamp,
            source,
            paint,
            profile,
            start.position,
            width,
            0,
            seed++,
          );
        }
        continue;
      }
      final direction = delta / length;
      final angle = math.atan2(direction.dy, direction.dx);
      for (var travelled = carried; travelled <= length; travelled += step) {
        _stamp(
          canvas,
          stamp,
          source,
          paint,
          profile,
          start.position + direction * travelled,
          width,
          angle,
          seed++,
        );
      }
      final consumed = ((length - carried) / step).floor() + 1;
      carried = math.max(carried + consumed * step - length, 0);
    }
  }

  static void _stamp(
    Canvas canvas,
    Image stamp,
    Rect source,
    Paint paint,
    DrawingBrushProfile profile,
    Offset position,
    double width,
    double angle,
    int seed,
  ) {
    final sizeSample = _sample32(seed);
    final angleSample = _sample32(seed ^ 0x9e3779b9);
    final size =
        width *
        profile.stampScale *
        (1 -
            profile.stampScaleJitter +
            profile.stampScaleJitter * 2 * sizeSample);
    canvas
      ..save()
      ..translate(position.dx, position.dy)
      ..rotate(
        (profile.stampFollowsDirection ? angle : 0) +
            (angleSample * 2 - 1) * profile.stampAngleJitter,
      )
      ..drawImageRect(
        stamp,
        source,
        Rect.fromCenter(center: Offset.zero, width: size, height: size),
        paint,
      )
      ..restore();
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
