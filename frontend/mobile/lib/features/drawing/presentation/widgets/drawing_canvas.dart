import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../models/drawing_stroke.dart';

class DrawingCanvas extends StatelessWidget {
  const DrawingCanvas({
    required this.strokes,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    this.backgroundImage,
    this.inputEnabled = true,
    this.onBackgroundLoaded,
    this.onBackgroundError,
    super.key,
  });

  final List<DrawingStroke> strokes;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerMoveEvent> onPointerMove;
  final ValueChanged<PointerEvent> onPointerUp;
  final ImageProvider<Object>? backgroundImage;
  final bool inputEnabled;
  final VoidCallback? onBackgroundLoaded;
  final VoidCallback? onBackgroundError;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '그림을 그리는 캔버스',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ColoredBox(
        color: AppColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backgroundImage case final image?)
              Image(
                key: const ValueKey('draft-background-image'),
                image: image,
                fit: BoxFit.contain,
                frameBuilder: (context, child, frame, synchronous) {
                  if (synchronous || frame != null) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => onBackgroundLoaded?.call(),
                    );
                  }
                  return child;
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => onBackgroundError?.call(),
                  );
                  return const SizedBox.expand();
                },
              ),
            Listener(
              key: const ValueKey('drawing-canvas'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: inputEnabled ? onPointerDown : null,
              onPointerMove: inputEnabled ? onPointerMove : null,
              onPointerUp: inputEnabled ? onPointerUp : null,
              onPointerCancel: inputEnabled ? onPointerUp : null,
              child: CustomPaint(
                painter: DrawingCanvasPainter(strokes),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DrawingCanvasPainter extends CustomPainter {
  const DrawingCanvasPainter(this.strokes);

  final List<DrawingStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
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
        continue;
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
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
