import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../models/drawing_stroke.dart';

class DrawingCanvas extends StatefulWidget {
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
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  ImageStream? _backgroundImageStream;
  ImageInfo? _backgroundImageInfo;
  late final ImageStreamListener _backgroundImageListener;

  @override
  void initState() {
    super.initState();
    _backgroundImageListener = ImageStreamListener(
      _handleBackgroundImage,
      onError: _handleBackgroundError,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveBackgroundImage();
  }

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundImage != widget.backgroundImage) {
      _resolveBackgroundImage();
    }
  }

  void _resolveBackgroundImage() {
    final provider = widget.backgroundImage;
    if (provider == null) {
      _backgroundImageStream?.removeListener(_backgroundImageListener);
      _backgroundImageStream = null;
      _replaceBackgroundImage(null);
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _backgroundImageStream?.key) return;
    _backgroundImageStream?.removeListener(_backgroundImageListener);
    _backgroundImageStream = stream;
    stream.addListener(_backgroundImageListener);
  }

  void _handleBackgroundImage(ImageInfo imageInfo, bool synchronousCall) {
    _replaceBackgroundImage(imageInfo);
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBackgroundLoaded?.call();
    });
  }

  void _handleBackgroundError(Object error, StackTrace? stackTrace) {
    _replaceBackgroundImage(null);
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBackgroundError?.call();
    });
  }

  void _replaceBackgroundImage(ImageInfo? imageInfo) {
    final oldImageInfo = _backgroundImageInfo;
    _backgroundImageInfo = imageInfo;
    if (oldImageInfo != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => oldImageInfo.dispose(),
      );
    }
  }

  @override
  void dispose() {
    _backgroundImageStream?.removeListener(_backgroundImageListener);
    _backgroundImageInfo?.dispose();
    super.dispose();
  }

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
            Listener(
              key: const ValueKey('drawing-canvas'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: widget.inputEnabled ? widget.onPointerDown : null,
              onPointerMove: widget.inputEnabled ? widget.onPointerMove : null,
              onPointerUp: widget.inputEnabled ? widget.onPointerUp : null,
              onPointerCancel: widget.inputEnabled ? widget.onPointerUp : null,
              child: CustomPaint(
                key: widget.backgroundImage == null
                    ? null
                    : const ValueKey('draft-background-image'),
                painter: DrawingCanvasPainter(
                  widget.strokes,
                  backgroundImage: _backgroundImageInfo?.image,
                ),
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
  const DrawingCanvasPainter(this.strokes, {this.backgroundImage});

  final List<DrawingStroke> strokes;
  final ui.Image? backgroundImage;

  @override
  void paint(Canvas canvas, Size size) {
    // Draft bitmap and new vector actions share this layer so ERASER can clear
    // both. The white widget surface beneath the layer becomes the erased pixel.
    final hasEraser = strokes.any(
      (stroke) => stroke.tool == DrawingTool.eraser,
    );
    if (hasEraser) canvas.saveLayer(Offset.zero & size, Paint());
    if (backgroundImage case final image?) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: image,
        fit: BoxFit.contain,
        alignment: Alignment.center,
      );
    }
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
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
    if (hasEraser) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.backgroundImage != backgroundImage;
}
