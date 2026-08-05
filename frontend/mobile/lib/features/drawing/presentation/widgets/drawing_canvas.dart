import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../models/drawing_canvas_action.dart';
import '../models/drawing_stroke.dart';
import '../rendering/drawing_brush_stamps.dart';
import '../rendering/drawing_stroke_renderer.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    required List<DrawingStroke> strokes,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    this.actions,
    this.onPointerHover,
    this.onPointerExit,
    this.backgroundImage,
    this.inputEnabled = true,
    this.onBackgroundLoaded,
    this.onBackgroundError,
    super.key,
  }) : _transientStrokes = strokes;

  final List<DrawingStroke> _transientStrokes;
  final List<DrawingCanvasAction>? actions;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerMoveEvent> onPointerMove;
  final ValueChanged<PointerEvent> onPointerUp;
  final ValueChanged<PointerHoverEvent>? onPointerHover;
  final ValueChanged<PointerExitEvent>? onPointerExit;
  final ImageProvider<Object>? backgroundImage;
  final bool inputEnabled;
  final VoidCallback? onBackgroundLoaded;
  final VoidCallback? onBackgroundError;

  /// Visible vector strokes for compatibility with existing consumers.
  ///
  /// When [actions] is present, only [_transientStrokes] is painted through
  /// the transient layer; committed strokes are rendered once from [actions].
  List<DrawingStroke> get strokes {
    final committed = actions;
    if (committed == null) return _transientStrokes;
    return List.unmodifiable([
      for (final action in committed)
        if (action case DrawingStrokeAction(:final stroke)) stroke,
      ..._transientStrokes,
    ]);
  }

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
    // 도구별 질감 스탬프는 한 번만 읽는다. 다 읽히기 전에는 단색 선으로 그리고
    // 준비되면 다시 그려 결이 나타나게 한다.
    DrawingBrushStamps.revision.addListener(_handleBrushStampsReady);
    unawaited(DrawingBrushStamps.ensureLoaded());
  }

  void _handleBrushStampsReady() {
    if (mounted) setState(() {});
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
    DrawingBrushStamps.revision.removeListener(_handleBrushStampsReady);
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
            MouseRegion(
              cursor: widget.inputEnabled
                  ? SystemMouseCursors.none
                  : MouseCursor.defer,
              onExit: widget.inputEnabled ? widget.onPointerExit : null,
              child: Listener(
                key: const ValueKey('drawing-canvas'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: widget.inputEnabled
                    ? widget.onPointerDown
                    : null,
                onPointerMove: widget.inputEnabled
                    ? widget.onPointerMove
                    : null,
                onPointerUp: widget.inputEnabled ? widget.onPointerUp : null,
                onPointerCancel: widget.inputEnabled
                    ? widget.onPointerUp
                    : null,
                onPointerHover: widget.inputEnabled
                    ? widget.onPointerHover
                    : null,
                child: CustomPaint(
                  key: widget.backgroundImage == null
                      ? null
                      : const ValueKey('draft-background-image'),
                  painter: DrawingCanvasPainter(
                    widget._transientStrokes,
                    actions: widget.actions,
                    backgroundImage: _backgroundImageInfo?.image,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DrawingCanvasPainter extends CustomPainter {
  const DrawingCanvasPainter(
    this.strokes, {
    this.actions,
    this.backgroundImage,
  });

  final List<DrawingStroke> strokes;
  final List<DrawingCanvasAction>? actions;
  final ui.Image? backgroundImage;

  @override
  void paint(Canvas canvas, Size size) {
    // Draft bitmap and new vector actions share this layer so ERASER can clear
    // both. The white widget surface beneath the layer becomes the erased pixel.
    final hasEraser =
        strokes.any((stroke) => stroke.tool == DrawingTool.eraser) ||
        (actions?.any(
              (action) =>
                  action is DrawingStrokeAction &&
                  action.stroke.tool == DrawingTool.eraser,
            ) ??
            false);
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
    if (actions case final committed?) {
      for (final action in committed) {
        switch (action) {
          case DrawingStrokeAction(:final stroke):
            DrawingStrokeRenderer.paint(canvas, stroke);
          case DrawingFillAction(:final patch):
            paintImage(
              canvas: canvas,
              rect: Offset.zero & size,
              image: patch,
              fit: BoxFit.fill,
              alignment: Alignment.center,
            );
        }
      }
    }
    for (final stroke in strokes) {
      DrawingStrokeRenderer.paint(canvas, stroke);
    }
    if (hasEraser) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.actions != actions ||
      oldDelegate.backgroundImage != backgroundImage;
}
