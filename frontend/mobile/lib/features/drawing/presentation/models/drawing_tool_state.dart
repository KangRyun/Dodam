import 'package:flutter/material.dart';

import '../../../../design_system/tokens/app_colors.dart';
import 'drawing_stroke.dart';

enum DrawingInstrument { crayon, pencil, brush, eraser, fill }

enum DrawingEraserMode { stroke, area }

enum DrawingEraserMenuAction { selectStroke, selectArea, clearAll }

@immutable
final class DrawingToolState {
  const DrawingToolState({
    this.instrument = DrawingInstrument.crayon,
    this.eraserMode = DrawingEraserMode.area,
    this.color = AppColors.canvasInk,
    this.width = 8,
  });

  final DrawingInstrument instrument;
  final DrawingEraserMode eraserMode;
  final Color color;
  final double width;

  DrawingTool? get wireTool => switch (instrument) {
    DrawingInstrument.crayon ||
    DrawingInstrument.pencil ||
    DrawingInstrument.brush => DrawingTool.pen,
    DrawingInstrument.eraser when eraserMode == DrawingEraserMode.area =>
      DrawingTool.eraser,
    DrawingInstrument.eraser || DrawingInstrument.fill => null,
  };
}
