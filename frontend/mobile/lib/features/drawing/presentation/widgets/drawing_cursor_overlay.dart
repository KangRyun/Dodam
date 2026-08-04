import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../models/drawing_tool_state.dart';
import 'drawing_canvas_viewport.dart';

@immutable
final class DrawingCursorState {
  const DrawingCursorState({
    required this.visible,
    required this.documentPosition,
    required this.instrument,
    required this.eraserMode,
    required this.documentWidth,
    required this.deviceKind,
  });

  final bool visible;
  final Offset documentPosition;
  final DrawingInstrument instrument;
  final DrawingEraserMode eraserMode;
  final double documentWidth;
  final PointerDeviceKind deviceKind;
}

final class DrawingCursorController extends ValueNotifier<DrawingCursorState> {
  DrawingCursorController(super.initial);

  void update({
    required Offset documentPosition,
    required DrawingToolState toolState,
    required PointerDeviceKind deviceKind,
  }) {
    value = DrawingCursorState(
      visible: true,
      documentPosition: documentPosition,
      instrument: toolState.instrument,
      eraserMode: toolState.eraserMode,
      documentWidth: toolState.width,
      deviceKind: deviceKind,
    );
  }

  void hide() {
    final current = value;
    if (!current.visible) return;
    value = DrawingCursorState(
      visible: false,
      documentPosition: current.documentPosition,
      instrument: current.instrument,
      eraserMode: current.eraserMode,
      documentWidth: current.documentWidth,
      deviceKind: current.deviceKind,
    );
  }
}

final class DrawingCursorOverlay extends StatelessWidget {
  const DrawingCursorOverlay({
    required this.state,
    required this.metrics,
    super.key,
  });

  final DrawingCursorState state;
  final DrawingViewportMetrics metrics;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    key: const ValueKey('drawing-cursor-overlay'),
    child: state.visible
        ? Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [_buildCursor()],
          )
        : const SizedBox.shrink(),
  );

  Widget _buildCursor() {
    final diameter = metrics.documentLengthToViewport(state.documentWidth);
    final center = metrics.documentToViewport(state.documentPosition);
    return Positioned(
      left: center.dx - diameter / 2,
      top: center.dy - diameter / 2,
      width: diameter,
      height: diameter,
      child: SizedBox.square(
        key: const ValueKey('drawing-cursor-visual'),
        dimension: diameter,
        child: state.instrument == DrawingInstrument.fill
            ? _buildFillCursor()
            : _buildOutlinedCursor(),
      ),
    );
  }

  Widget _buildFillCursor() => KeyedSubtree(
    key: const ValueKey('fill-cursor'),
    child: DecoratedBox(
      key: const ValueKey('drawing-fill-cursor-dark-outline'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          key: const ValueKey('drawing-fill-cursor-light-outline'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
      ),
    ),
  );

  Widget _buildOutlinedCursor() {
    final cursorKey = switch (state.instrument) {
      DrawingInstrument.eraser
          when state.eraserMode == DrawingEraserMode.area =>
        const ValueKey('area-eraser-cursor'),
      DrawingInstrument.eraser => const ValueKey('stroke-eraser-cursor'),
      DrawingInstrument.crayon => const ValueKey('crayon-cursor'),
      DrawingInstrument.pencil => const ValueKey('pencil-cursor'),
      DrawingInstrument.brush => const ValueKey('brush-cursor'),
      DrawingInstrument.fill => const ValueKey('fill-cursor'),
    };
    return DecoratedBox(
      key: cursorKey,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black87, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.white, spreadRadius: 0.5)],
      ),
    );
  }
}
