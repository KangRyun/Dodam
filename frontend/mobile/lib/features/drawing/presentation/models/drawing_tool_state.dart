import 'package:flutter/material.dart';

import '../../../../design_system/tokens/app_colors.dart';
import 'drawing_stroke.dart';

enum DrawingInstrument { crayon, pencil, brush, eraser, fill }

enum DrawingEraserMode { stroke, area }

enum DrawingEraserMenuAction { selectStroke, selectArea, clearAll }

extension DrawingInstrumentBrush on DrawingInstrument {
  /// 도구가 남기는 자국의 질감이다. 지우개·채우기는 획을 남기지 않는다.
  DrawingBrushProfileId get brushProfile => switch (this) {
    DrawingInstrument.crayon => DrawingBrushProfileId.crayon,
    DrawingInstrument.pencil => DrawingBrushProfileId.pencil,
    DrawingInstrument.brush => DrawingBrushProfileId.brush,
    DrawingInstrument.eraser ||
    DrawingInstrument.fill => DrawingBrushProfileId.legacyPen,
  };
}

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

  DrawingBrushProfileId get brushProfile => instrument.brushProfile;

  DrawingTool? get wireTool => switch (instrument) {
    DrawingInstrument.crayon ||
    DrawingInstrument.pencil ||
    DrawingInstrument.brush => DrawingTool.pen,
    DrawingInstrument.eraser when eraserMode == DrawingEraserMode.area =>
      DrawingTool.eraser,
    DrawingInstrument.eraser || DrawingInstrument.fill => null,
  };
}
