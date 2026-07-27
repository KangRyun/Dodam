import 'dart:ui';

enum DrawingTool { pen, eraser }

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
  });

  final List<DrawingPoint> points;
  final Color color;
  final double thickness;
  final DrawingTool tool;

  DrawingStroke addPoint(DrawingPoint point) => DrawingStroke(
    points: List.unmodifiable([...points, point]),
    color: color,
    thickness: thickness,
    tool: tool,
  );
}
