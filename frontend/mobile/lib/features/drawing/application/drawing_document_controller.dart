import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../presentation/models/drawing_canvas_action.dart';
import '../presentation/models/drawing_stroke.dart';

enum DrawingWireEffect { none, appendStroke, undo, redo }

final class DrawingDocumentChange {
  const DrawingDocumentChange({
    required this.changed,
    required this.wireEffect,
    this.wireStroke,
  });

  final bool changed;
  final DrawingWireEffect wireEffect;
  final DrawingStroke? wireStroke;
}

final class DrawingDocumentController extends ChangeNotifier {
  DrawingDocumentController({int initialTextureSeed = 1})
    : _nextTextureSeed = initialTextureSeed;

  final List<DrawingCanvasAction> _actions = [];
  final List<_DocumentMutation> _undo = [];
  final List<_DocumentMutation> _redo = [];
  int _nextActionId = 1;
  int _nextTextureSeed;
  List<DrawingCanvasAction>? _eraseBefore;
  bool _disposed = false;

  List<DrawingCanvasAction> get actions => List.unmodifiable(_actions);

  List<DrawingStroke> get visibleStrokes => List.unmodifiable([
    for (final action in _actions)
      if (action case DrawingStrokeAction(:final stroke)) stroke,
  ]);

  bool get hasVisibleContent => _actions.any(
    (action) =>
        action is DrawingFillAction ||
        (action is DrawingStrokeAction &&
            action.stroke.tool == DrawingTool.pen),
  );

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  DrawingDocumentChange addStroke(DrawingStroke stroke) {
    _cancelEraseIfNeeded();
    final seeded = stroke.copyWith(textureSeed: _nextTextureSeed++);
    final action = DrawingStrokeAction(id: _nextActionId++, stroke: seeded);
    final before = List<DrawingCanvasAction>.of(_actions);
    _actions.add(action);
    _record(
      _DocumentMutation(
        before: before,
        after: List<DrawingCanvasAction>.of(_actions),
        undoEffect: DrawingWireEffect.undo,
        redoEffect: DrawingWireEffect.redo,
      ),
    );
    notifyListeners();
    return DrawingDocumentChange(
      changed: true,
      wireEffect: DrawingWireEffect.appendStroke,
      wireStroke: seeded,
    );
  }

  DrawingDocumentChange addFill({
    required ui.Image patch,
    required Size documentSize,
  }) {
    _cancelEraseIfNeeded();
    final before = List<DrawingCanvasAction>.of(_actions);
    _actions.add(
      DrawingFillAction(
        id: _nextActionId++,
        patch: patch,
        documentSize: documentSize,
      ),
    );
    _record(
      _DocumentMutation(
        before: before,
        after: List<DrawingCanvasAction>.of(_actions),
        undoEffect: DrawingWireEffect.none,
        redoEffect: DrawingWireEffect.none,
      ),
    );
    notifyListeners();
    return const DrawingDocumentChange(
      changed: true,
      wireEffect: DrawingWireEffect.none,
    );
  }

  void beginStrokeEraseGesture() {
    if (_eraseBefore != null) return;
    _eraseBefore = List<DrawingCanvasAction>.of(_actions);
  }

  bool eraseStrokeAt(Offset documentPoint, {required double radius}) {
    final before = _eraseBefore;
    if (before == null) {
      throw StateError('beginStrokeEraseGesture must be called first');
    }
    for (var index = _actions.length - 1; index >= 0; index--) {
      final action = _actions[index];
      if (action is! DrawingStrokeAction ||
          action.stroke.tool != DrawingTool.pen) {
        continue;
      }
      if (_strokeHits(action.stroke, documentPoint, radius)) {
        _actions.removeAt(index);
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  DrawingDocumentChange endStrokeEraseGesture({DrawingStroke? fallbackStroke}) {
    final before = _eraseBefore;
    _eraseBefore = null;
    DrawingStroke? seededFallback;
    if (before != null && fallbackStroke != null) {
      seededFallback = fallbackStroke.copyWith(textureSeed: _nextTextureSeed++);
      _actions.add(
        DrawingStrokeAction(id: _nextActionId++, stroke: seededFallback),
      );
    }
    if (before == null || listEquals(before, _actions)) {
      return const DrawingDocumentChange(
        changed: false,
        wireEffect: DrawingWireEffect.none,
      );
    }
    _record(
      _DocumentMutation(
        before: before,
        after: List<DrawingCanvasAction>.of(_actions),
        undoEffect: DrawingWireEffect.none,
        redoEffect: DrawingWireEffect.none,
      ),
    );
    notifyListeners();
    return DrawingDocumentChange(
      changed: true,
      wireEffect: seededFallback == null
          ? DrawingWireEffect.none
          : DrawingWireEffect.appendStroke,
      wireStroke: seededFallback,
    );
  }

  void cancelStrokeEraseGesture() {
    final before = _eraseBefore;
    _eraseBefore = null;
    if (before == null || listEquals(before, _actions)) return;
    _actions
      ..clear()
      ..addAll(before);
    notifyListeners();
  }

  DrawingDocumentChange undo() {
    _cancelEraseIfNeeded();
    if (_undo.isEmpty) {
      return const DrawingDocumentChange(
        changed: false,
        wireEffect: DrawingWireEffect.none,
      );
    }
    final mutation = _undo.removeLast();
    _replaceActions(mutation.before);
    _redo.add(mutation);
    notifyListeners();
    return DrawingDocumentChange(
      changed: true,
      wireEffect: mutation.undoEffect,
    );
  }

  DrawingDocumentChange redo() {
    _cancelEraseIfNeeded();
    if (_redo.isEmpty) {
      return const DrawingDocumentChange(
        changed: false,
        wireEffect: DrawingWireEffect.none,
      );
    }
    final mutation = _redo.removeLast();
    _replaceActions(mutation.after);
    _undo.add(mutation);
    notifyListeners();
    return DrawingDocumentChange(
      changed: true,
      wireEffect: mutation.redoEffect,
    );
  }

  DrawingDocumentChange clearAll() {
    _cancelEraseIfNeeded();
    final changed = _actions.isNotEmpty;
    final historyChanged = changed || _undo.isNotEmpty || _redo.isNotEmpty;
    final discarded = <DrawingCanvasAction>{..._actions};
    for (final mutation in _redo) {
      discarded.addAll(mutation.before);
      discarded.addAll(mutation.after);
    }
    _actions.clear();
    _undo.clear();
    _redo.clear();
    _disposeFillActions(discarded);
    if (historyChanged) notifyListeners();
    return DrawingDocumentChange(
      changed: changed,
      wireEffect: DrawingWireEffect.none,
    );
  }

  void _record(_DocumentMutation mutation) {
    _discardRedo();
    _undo.add(mutation);
  }

  void _discardRedo() {
    if (_redo.isEmpty) return;
    final live = _actions.toSet();
    final discarded = <DrawingCanvasAction>{};
    for (final mutation in _redo) {
      discarded.addAll(
        mutation.before.where((action) => !live.contains(action)),
      );
      discarded.addAll(
        mutation.after.where((action) => !live.contains(action)),
      );
    }
    _redo.clear();
    _disposeFillActions(discarded);
  }

  void _replaceActions(List<DrawingCanvasAction> actions) {
    _actions
      ..clear()
      ..addAll(actions);
  }

  void _cancelEraseIfNeeded() {
    if (_eraseBefore != null) cancelStrokeEraseGesture();
  }

  static bool _strokeHits(DrawingStroke stroke, Offset point, double radius) {
    if (stroke.points.isEmpty) return false;
    final threshold = radius + stroke.thickness / 2;
    if (stroke.points.length == 1) {
      return (stroke.points.single.position - point).distance <= threshold;
    }
    for (var index = 0; index < stroke.points.length - 1; index++) {
      if (_distanceToSegment(
            point,
            stroke.points[index].position,
            stroke.points[index + 1].position,
          ) <=
          threshold) {
        return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared == 0) return (point - start).distance;
    final projection =
        ((point.dx - start.dx) * segment.dx +
            (point.dy - start.dy) * segment.dy) /
        lengthSquared;
    final t = projection.clamp(0, 1).toDouble();
    return (point -
            Offset(start.dx + segment.dx * t, start.dy + segment.dy * t))
        .distance;
  }

  static void _disposeFillActions(Iterable<DrawingCanvasAction> actions) {
    final disposed = <ui.Image>{};
    for (final action in actions) {
      if (action is DrawingFillAction && disposed.add(action.patch)) {
        action.patch.dispose();
      }
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      final actions = <DrawingCanvasAction>{..._actions};
      for (final mutation in _redo) {
        actions
          ..addAll(mutation.before)
          ..addAll(mutation.after);
      }
      _disposeFillActions(actions);
      _actions.clear();
      _undo.clear();
      _redo.clear();
    }
    super.dispose();
  }
}

final class _DocumentMutation {
  const _DocumentMutation({
    required this.before,
    required this.after,
    required this.undoEffect,
    required this.redoEffect,
  });

  final List<DrawingCanvasAction> before;
  final List<DrawingCanvasAction> after;
  final DrawingWireEffect undoEffect;
  final DrawingWireEffect redoEffect;
}
