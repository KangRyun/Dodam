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
      // 종이 전체가 그릴 수 있는 자리여야 한다. 문서를 고정 크기로 두고 가운데
      // 맞추면 남는 가장자리가 칠해지지 않는 흰 자리로 남는다.
      final documentSize = availableSize.isEmpty
          ? DrawingCanvasGeometry.documentSize
          : availableSize;
      final metrics = DrawingViewportMetrics(
        availableSize: availableSize,
        documentSize: documentSize,
        scale: 1,
        origin: Offset.zero,
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          KeyedSubtree(
            key: const ValueKey('drawing-document-marker'),
            child: RepaintBoundary(
              key: repaintBoundaryKey,
              child: SizedBox.fromSize(size: documentSize, child: canvas),
            ),
          ),
          overlayBuilder(context, metrics),
        ],
      );
    },
  );
}
