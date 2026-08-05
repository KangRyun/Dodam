import 'dart:math' as math;

import 'package:dodam/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

enum DrawingCanvasDeviceClass { mobilePortrait, mobileLandscape, tablet }

/// 스케치북 모양 테두리다.
///
/// 테두리를 그림 파일로 덮지 않고 직접 그린다. 파일을 늘여 붙이면 종이 모서리가
/// 선 밖으로 삐져나오는 자리가 생기는데, 같은 둥근 사각형을 종이로 채우고 그
/// 위를 선으로 덧그리면 그런 자리가 생길 수 없다.
final class DrawingCrayonFrame extends StatelessWidget {
  const DrawingCrayonFrame({
    required this.deviceClass,
    required this.child,
    super.key,
  });

  final DrawingCanvasDeviceClass deviceClass;
  final Widget child;

  bool get _isTablet => deviceClass == DrawingCanvasDeviceClass.tablet;

  @override
  Widget build(BuildContext context) {
    final metrics = _FrameMetrics.of(deviceClass);
    // 종이 질감 타일 크기는 시안 값(태블릿 320·모바일 240)에 맞춘다.
    final paperTextureScale = _isTablet ? 512 / 320 : 512 / 240;

    return ColoredBox(
      key: const ValueKey('drawing-crayon-frame-exterior'),
      // 테두리 선 바깥은 화면 배경이 그대로 보여야 한다.
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        // 제본이 스케치북 위쪽으로 걸쳐 나가야 시안과 같은 모양이 된다.
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.all(metrics.paperInset),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(metrics.paperRadius),
              child: ColoredBox(
                key: const ValueKey('drawing-crayon-document'),
                color: Colors.white,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: ExactAssetImage(
                        'assets/canvas/frame/paper_texture.png',
                        scale: paperTextureScale,
                      ),
                      repeat: ImageRepeat.repeat,
                      // 시안은 질감 위에 흰색 88% 를 덮는다. 남는 12% 가 결이다.
                      opacity: 0.12,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('drawing-crayon-frame-border'),
                painter: _CrayonBorderPainter(metrics),
              ),
            ),
          ),
          // 고리는 스케치북 위로 걸쳐 나가야 해서 잘라 내지 않는다. 띠는 테두리
          // 안쪽에서 그려 모서리 곡선을 그대로 따라간다.
          Positioned(
            left: 0,
            right: 0,
            top: -metrics.bindingOverhang,
            height: metrics.bindingHeight + metrics.bindingOverhang,
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('drawing-crayon-frame-spirals'),
                painter: _BindingLoopPainter(metrics),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 기기별 스케치북 치수다. 테두리와 제본이 같은 값을 봐야 어긋나지 않는다.
@immutable
final class _FrameMetrics {
  const _FrameMetrics({
    required this.borderWidth,
    required this.radius,
    required this.bindingHeight,
    required this.bindingOverhang,
    required this.loopWidth,
    required this.loopGap,
  });

  static _FrameMetrics of(DrawingCanvasDeviceClass deviceClass) =>
      switch (deviceClass) {
        DrawingCanvasDeviceClass.tablet => const _FrameMetrics(
          borderWidth: 5,
          radius: 22,
          bindingHeight: 30,
          bindingOverhang: 9,
          loopWidth: 13,
          loopGap: 30,
        ),
        _ => const _FrameMetrics(
          borderWidth: 4,
          radius: 16,
          bindingHeight: 22,
          bindingOverhang: 7,
          loopWidth: 10,
          loopGap: 22,
        ),
      };

  final double borderWidth;
  final double radius;

  /// 제본 띠 높이다.
  final double bindingHeight;

  /// 제본이 스케치북 위쪽으로 걸쳐 나가는 길이다.
  final double bindingOverhang;

  /// 철사 고리 하나의 폭과 고리 사이 간격이다.
  final double loopWidth;
  final double loopGap;

  /// 종이는 선 한가운데까지만 채운다. 이보다 넓으면 선 밖으로 흰 자리가 남고,
  /// 좁으면 선과 종이 사이가 뜬다.
  double get paperInset => borderWidth / 2;
  double get paperRadius => math.max(radius - paperInset, 0);
}

/// 크레용으로 그은 듯한 테두리와 제본 띠를 그린다.
///
/// 자로 잰 선은 크레용으로 보이지 않는다. 선을 짧게 끊어 조금씩 흔들고, 굵기와
/// 진하기가 다른 겹을 여러 번 덧그어 손으로 그은 자국처럼 만든다.
final class _CrayonBorderPainter extends CustomPainter {
  const _CrayonBorderPainter(this.metrics);

  final _FrameMetrics metrics;

  /// 겹마다 굵기·진하기·흔들림이 달라야 한 번에 그은 선으로 안 보인다.
  static const _passes = <({double width, double opacity, double wobble})>[
    (width: 1, opacity: .9, wobble: .5),
    (width: .66, opacity: .55, wobble: 1.5),
    (width: .4, opacity: .38, wobble: 2.4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final outline = _outlineOf(size, metrics);

    // 띠는 스케치북 안쪽에서만 보여야 모서리 곡선을 그대로 따라간다.
    canvas
      ..save()
      ..clipRRect(outline);
    final band = Rect.fromLTWH(0, 0, size.width, metrics.bindingHeight);
    canvas
      ..drawRect(band, Paint()..color = AppColors.canvasBindingBand)
      ..drawLine(
        Offset(0, band.bottom),
        Offset(size.width, band.bottom),
        Paint()
          ..color = AppColors.canvasFrameInk.withValues(alpha: .55)
          ..strokeWidth = metrics.borderWidth * .5,
      )
      ..restore();

    for (final pass in _passes) {
      canvas.drawPath(
        _wobbledOutline(outline, pass.wobble),
        Paint()
          ..color = AppColors.canvasFrameInk.withValues(alpha: pass.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = metrics.borderWidth * pass.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CrayonBorderPainter oldDelegate) =>
      oldDelegate.metrics != metrics;
}

/// 제본 띠를 감는 철사 고리다. 스케치북 위로 걸쳐 나가야 해서 따로 그린다.
final class _BindingLoopPainter extends CustomPainter {
  const _BindingLoopPainter(this.metrics);

  final _FrameMetrics metrics;

  @override
  void paint(Canvas canvas, Size size) {
    final step = metrics.loopWidth + metrics.loopGap;
    // 스케치북 모서리 곡선을 침범하지 않도록 양쪽을 비운다.
    final usable = size.width - metrics.radius * 2;
    final count = (usable / step).floor();
    if (count <= 0) return;
    final spare = usable - count * step;
    final start = metrics.radius + (spare + metrics.loopGap) / 2;

    final fill = Paint()..color = AppColors.canvasBindingWire;
    final edge = Paint()
      ..color = AppColors.canvasFrameInk.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = metrics.borderWidth * .4
      ..isAntiAlias = true;

    for (var index = 0; index < count; index++) {
      final loop = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          start + index * step,
          0,
          metrics.loopWidth,
          metrics.bindingOverhang + metrics.bindingHeight * .72,
        ),
        Radius.circular(metrics.loopWidth * .5),
      );
      canvas
        ..drawRRect(loop, fill)
        ..drawRRect(loop, edge);
    }
  }

  @override
  bool shouldRepaint(covariant _BindingLoopPainter oldDelegate) =>
      oldDelegate.metrics != metrics;
}

RRect _outlineOf(Size size, _FrameMetrics metrics) {
  final inset = metrics.borderWidth / 2;
  return RRect.fromRectAndRadius(
    Rect.fromLTWH(
      inset,
      inset,
      size.width - metrics.borderWidth,
      size.height - metrics.borderWidth,
    ),
    Radius.circular(metrics.radius - inset),
  );
}

/// 둥근 사각형을 짧게 끊어 각 점을 바깥·안쪽으로 조금씩 밀어 손떨림을 만든다.
Path _wobbledOutline(RRect outline, double wobble) {
  final source = Path()..addRRect(outline);
  if (wobble <= 0) return source;
  final centre = outline.outerRect.center;
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var first = true;
    while (distance < metric.length) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        final point = tangent.position;
        final away = point - centre;
        final length = away.distance;
        final push = (_noise(distance.round()) - .5) * 2 * wobble;
        final shifted = length == 0 ? point : point + away / length * push;
        if (first) {
          result.moveTo(shifted.dx, shifted.dy);
          first = false;
        } else {
          result.lineTo(shifted.dx, shifted.dy);
        }
      }
      distance += 6;
    }
    if (!first) result.close();
  }
  return result;
}

/// 같은 자리는 늘 같은 값이 나와야 다시 그릴 때 테두리가 떨리지 않는다.
double _noise(int value) {
  var mixed = value & 0xffffffff;
  mixed = ((mixed ^ (mixed >> 16)) * 0x45d9f3b) & 0xffffffff;
  mixed = ((mixed ^ (mixed >> 16)) * 0x45d9f3b) & 0xffffffff;
  mixed = (mixed ^ (mixed >> 16)) & 0xffffffff;
  return mixed / 0x100000000;
}
