import 'dart:ui';

import '../data/dto/drawing_dtos.dart';
import '../presentation/models/drawing_stroke.dart';

abstract final class DrawingEventTypes {
  static const strokeStart = 'STROKE_START';
  static const strokeMove = 'STROKE_MOVE';
  static const strokeEnd = 'STROKE_END';
  static const toolChange = 'TOOL_CHANGE';
  static const colorChange = 'COLOR_CHANGE';
  static const thicknessChange = 'THICKNESS_CHANGE';
  static const undo = 'UNDO';
  static const redo = 'REDO';
  static const canvasClear = 'CANVAS_CLEAR';
  static const pause = 'PAUSE';
  static const resume = 'RESUME';
}

final class SessionSequenceAllocator {
  /// Team default starts at 1 and increases session-wide. The start remains
  /// configurable because the unimplemented server currently only checks >= 0.
  SessionSequenceAllocator({int startValue = 1}) : _nextValue = startValue;

  int _nextValue;
  int get nextValue => _nextValue;

  int allocate() => _nextValue++;

  void resumeAt(int nextValue) {
    if (nextValue < 0) throw ArgumentError.value(nextValue, 'nextValue');
    _nextValue = nextValue;
  }
}

final class DrawingEventJournal {
  DrawingEventJournal({
    SessionSequenceAllocator? sequenceAllocator,
    Stopwatch? sessionClock,
  }) : _sequenceAllocator = sequenceAllocator ?? SessionSequenceAllocator(),
       _sessionClock = sessionClock ?? (Stopwatch()..start());

  final SessionSequenceAllocator _sequenceAllocator;
  final Stopwatch _sessionClock;
  final List<StrokeEventDto> _events = [];
  int _undoableStrokeCount = 0;
  int _redoableStrokeCount = 0;

  int get elapsedMilliseconds => _sessionClock.elapsedMilliseconds;
  List<StrokeEventDto> get events => List.unmodifiable(_events);
  int? get lastEventSequence => _events.lastOrNull?.seq;
  int get snapshotCutoffSequence {
    final cutoff = _sequenceAllocator.nextValue - 1;
    return cutoff < 0 ? 0 : cutoff;
  }

  int get undoableStrokeCount => _undoableStrokeCount;
  int get redoableStrokeCount => _redoableStrokeCount;

  bool resumeEventSequence(int nextValue) {
    if (_events.isNotEmpty) return false;
    _sequenceAllocator.resumeAt(nextValue);
    return true;
  }

  List<StrokeEventDto> recordStroke(DrawingStroke stroke, Size canvasSize) {
    final converted = DrawingStrokeEventConverter.convert(
      stroke: stroke,
      canvasSize: canvasSize,
      sequenceAllocator: _sequenceAllocator,
    );
    _events.addAll(converted);
    if (converted.isNotEmpty) {
      _undoableStrokeCount += 1;
      _redoableStrokeCount = 0;
    }
    return converted;
  }

  StrokeEventDto? recordUndo({int? elapsedMilliseconds}) {
    if (_undoableStrokeCount == 0) return null;
    final event = StrokeEventDto(
      seq: _sequenceAllocator.allocate(),
      t: elapsedMilliseconds ?? _sessionClock.elapsedMilliseconds,
      type: DrawingEventTypes.undo,
    );
    _events.add(event);
    _undoableStrokeCount -= 1;
    _redoableStrokeCount += 1;
    return event;
  }

  StrokeEventDto? recordRedo({int? elapsedMilliseconds}) {
    if (_redoableStrokeCount == 0) return null;
    final event = StrokeEventDto(
      seq: _sequenceAllocator.allocate(),
      t: elapsedMilliseconds ?? _sessionClock.elapsedMilliseconds,
      type: DrawingEventTypes.redo,
    );
    _events.add(event);
    _redoableStrokeCount -= 1;
    _undoableStrokeCount += 1;
    return event;
  }

  // CLEAR/PAUSE and tool setting events remain intentionally dormant.
}

abstract final class DrawingStrokeEventConverter {
  static List<StrokeEventDto> convert({
    required DrawingStroke stroke,
    required Size canvasSize,
    required SessionSequenceAllocator sequenceAllocator,
  }) {
    if (stroke.points.isEmpty ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return const [];
    }

    if (stroke.points.length == 1) {
      final point = stroke.points.single;
      return List.unmodifiable([
        _eventForPoint(
          point: point,
          stroke: stroke,
          canvasSize: canvasSize,
          sequenceAllocator: sequenceAllocator,
          type: DrawingEventTypes.strokeStart,
          includeStyle: true,
        ),
        _eventForPoint(
          point: point,
          stroke: stroke,
          canvasSize: canvasSize,
          sequenceAllocator: sequenceAllocator,
          type: DrawingEventTypes.strokeEnd,
        ),
      ]);
    }

    final result = <StrokeEventDto>[];
    for (var index = 0; index < stroke.points.length; index++) {
      final point = stroke.points[index];
      final isFirst = index == 0;
      final isLast = index == stroke.points.length - 1;
      result.add(
        _eventForPoint(
          point: point,
          stroke: stroke,
          canvasSize: canvasSize,
          sequenceAllocator: sequenceAllocator,
          type: isFirst
              ? DrawingEventTypes.strokeStart
              : isLast
              ? DrawingEventTypes.strokeEnd
              : DrawingEventTypes.strokeMove,
          includeStyle: isFirst,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static StrokeEventDto _eventForPoint({
    required DrawingPoint point,
    required DrawingStroke stroke,
    required Size canvasSize,
    required SessionSequenceAllocator sequenceAllocator,
    required String type,
    bool includeStyle = false,
  }) => StrokeEventDto(
    seq: sequenceAllocator.allocate(),
    t: point.elapsedMilliseconds,
    type: type,
    x: (point.position.dx / canvasSize.width).clamp(0.0, 1.0),
    y: (point.position.dy / canvasSize.height).clamp(0.0, 1.0),
    tool: includeStyle ? _toolCode(stroke.tool) : null,
    color: includeStyle && stroke.tool == DrawingTool.pen
        ? _colorHex(stroke.color)
        : null,
    // Team policy uses the same Flutter logical pixel value as Paint.strokeWidth.
    // TODO(API): Document logical pixels as the final backend unit.
    thickness: includeStyle ? stroke.thickness : null,
    pressure: point.pressure?.clamp(0.0, 1.0),
  );

  static String _toolCode(DrawingTool tool) => switch (tool) {
    DrawingTool.pen => 'PEN',
    DrawingTool.eraser => 'ERASER',
  };

  static String _colorHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
