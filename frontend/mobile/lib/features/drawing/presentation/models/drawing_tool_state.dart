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

  /// 도구 전환 이벤트(`TOOL_CHANGE`)에 싣는 코드다.
  ///
  /// 획에 실리는 [wireTool]은 PEN/ERASER 두 갈래라 크레용→연필 같은 전환이 사라진다.
  /// 아이가 실제로 고른 도구를 남기려고 여기서는 좁히지 않는다. 지우개는 획을 골라
  /// 지우는 모드와 문질러 지우는 모드가 서로 다른 행동이라 나눠 적는다.
  /// 백엔드 계약의 도구 코드 정규식(`[A-Z][A-Z0-9_]*`, 30자)을 지킨다.
  String get wireToolCode => switch (instrument) {
    DrawingInstrument.crayon => 'CRAYON',
    DrawingInstrument.pencil => 'PENCIL',
    DrawingInstrument.brush => 'BRUSH',
    DrawingInstrument.eraser when eraserMode == DrawingEraserMode.stroke =>
      'ERASER_STROKE',
    DrawingInstrument.eraser => 'ERASER',
    DrawingInstrument.fill => 'FILL',
  };

  DrawingTool? get wireTool => switch (instrument) {
    DrawingInstrument.crayon ||
    DrawingInstrument.pencil ||
    DrawingInstrument.brush => DrawingTool.pen,
    DrawingInstrument.eraser when eraserMode == DrawingEraserMode.area =>
      DrawingTool.eraser,
    DrawingInstrument.eraser || DrawingInstrument.fill => null,
  };
}
