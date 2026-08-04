import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../../../design_system/tokens/app_colors.dart';
import '../models/drawing_tool_state.dart';
import '../rendering/drawing_stroke_renderer.dart';
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
    this.color = AppColors.canvasInk,
  });

  final bool visible;
  final Offset documentPosition;
  final DrawingInstrument instrument;
  final DrawingEraserMode eraserMode;
  final double documentWidth;
  final PointerDeviceKind deviceKind;

  /// 지금 고른 그리기 색이다. 커서 안을 이 색으로 채워 미리 보여 준다.
  final Color color;

  /// 이 도구·굵기로 실제로 찍히는 자국의 지름이다.
  double get footprint =>
      DrawingStrokeRenderer.footprintFor(instrument.brushProfile, documentWidth);
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
      color: toolState.color,
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
      color: current.color,
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
    // 선 굵기가 아니라 실제 자국 크기를 보여 준다. 크레파스·붓은 선보다 넓게
    // 번지므로 굵기 그대로 그리면 커서보다 큰 자국이 찍힌다.
    final diameter = metrics.documentLengthToViewport(state.footprint);
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
    // 지우개는 지우는 자리라 색을 채우지 않는다. 그리기 도구는 고른 색을 옅게
    // 채워 어떤 색이 어느 크기로 찍힐지 손대기 전에 보이게 한다.
    final fills = state.instrument != DrawingInstrument.eraser;
    return DecoratedBox(
      key: cursorKey,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fills ? state.color.withValues(alpha: .35) : null,
        border: Border.all(color: Colors.black87, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.white, spreadRadius: 0.5)],
      ),
    );
  }
}
