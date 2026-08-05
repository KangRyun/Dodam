import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class DrawingCanvasGeometry {
  static const documentSize = Size(1024, 768);
}

final class DrawingViewportMetrics {
  const DrawingViewportMetrics({
    required this.availableSize,
    required this.documentSize,
    required this.scale,
    required this.origin,
  });

  final Size availableSize;
  final Size documentSize;
  final double scale;
  final Offset origin;

  Offset viewportToDocument(Offset point) => (point - origin) / scale;

  Offset documentToViewport(Offset point) => origin + point * scale;

  double documentLengthToViewport(double value) => value * scale;
}

typedef DrawingViewportOverlayBuilder =
    Widget Function(BuildContext context, DrawingViewportMetrics metrics);

final class DrawingCanvasViewport extends StatelessWidget {
  const DrawingCanvasViewport({
    required this.repaintBoundaryKey,
    required this.canvas,
    required this.overlayBuilder,
    super.key,
  });

  final GlobalKey repaintBoundaryKey;
  final Widget canvas;
  final DrawingViewportOverlayBuilder overlayBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableSize = constraints.biggest;
      final documentSize = DrawingCanvasGeometry.documentSize;
      final scale = math.min(
        availableSize.width / documentSize.width,
        availableSize.height / documentSize.height,
      );
      final paintedSize = documentSize * scale;
      final metrics = DrawingViewportMetrics(
        availableSize: availableSize,
        documentSize: documentSize,
        scale: scale,
        origin: Offset(
          (availableSize.width - paintedSize.width) / 2,
          (availableSize.height - paintedSize.height) / 2,
        ),
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: SizedBox.fromSize(
              size: availableSize,
              child: FittedBox(
                fit: BoxFit.contain,
                child: KeyedSubtree(
                  key: const ValueKey('drawing-document-marker'),
                  child: RepaintBoundary(
                    key: repaintBoundaryKey,
                    child: SizedBox.fromSize(
                      size: DrawingCanvasGeometry.documentSize,
                      child: canvas,
                    ),
                  ),
                ),
              ),
            ),
          ),
          overlayBuilder(context, metrics),
        ],
      );
    },
  );
}
