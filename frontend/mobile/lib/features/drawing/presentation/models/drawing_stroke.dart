import 'dart:ui';

enum DrawingTool { pen, eraser }

enum DrawingBrushProfileId { legacyPen, crayon, pencil, brush }

final class DrawingPoint {
  const DrawingPoint({
    required this.position,
    required this.elapsedMilliseconds,
    this.pressure,
  });

  final Offset position;
  final int elapsedMilliseconds;
  final double? pressure;
}

final class DrawingStroke {
  const DrawingStroke({
    required this.points,
    required this.color,
    required this.thickness,
    this.tool = DrawingTool.pen,
    this.brushProfile = DrawingBrushProfileId.legacyPen,
    this.textureSeed = 0,
  });

  final List<DrawingPoint> points;
  final Color color;
  final double thickness;
  final DrawingTool tool;
  final DrawingBrushProfileId brushProfile;
  final int textureSeed;

  DrawingStroke copyWith({
    List<DrawingPoint>? points,
    Color? color,
    double? thickness,
    DrawingTool? tool,
    DrawingBrushProfileId? brushProfile,
    int? textureSeed,
  }) => DrawingStroke(
    points: points ?? this.points,
    color: color ?? this.color,
    thickness: thickness ?? this.thickness,
    tool: tool ?? this.tool,
    brushProfile: brushProfile ?? this.brushProfile,
    textureSeed: textureSeed ?? this.textureSeed,
  );

  DrawingStroke addPoint(DrawingPoint point) =>
      copyWith(points: List.unmodifiable([...points, point]));
}
