import 'dart:ui' as ui;

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/drawing/application/drawing_document_controller.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_canvas_action.dart';
import 'package:dodam/features/drawing/presentation/models/drawing_stroke.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps stroke and fill actions in creation order', () async {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    final patch = await _patch();

    controller.addStroke(_stroke(Offset.zero));
    controller.addFill(patch: patch, documentSize: const Size(64, 64));
    controller.addStroke(_stroke(const Offset(20, 20)));

    expect(controller.actions.map((action) => action.runtimeType), [
      DrawingStrokeAction,
      DrawingFillAction,
      DrawingStrokeAction,
    ]);
    expect(controller.actions.map((action) => action.id), [1, 2, 3]);
    expect(controller.hasVisibleContent, isTrue);
  });

  test('fill and a stroke erase gesture have no wire effect', () async {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    final patch = await _patch();

    expect(
      controller
          .addFill(patch: patch, documentSize: const Size(64, 64))
          .wireEffect,
      DrawingWireEffect.none,
    );
    controller.addStroke(_stroke(Offset.zero));
    controller.beginStrokeEraseGesture();
    expect(controller.eraseStrokeAt(const Offset(5, 0), radius: 1), isTrue);
    expect(
      controller.endStrokeEraseGesture().wireEffect,
      DrawingWireEffect.none,
    );
  });

  test('pen stroke undo and redo expose matching journal effects', () {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    final stroke = _stroke(Offset.zero);

    expect(
      controller.addStroke(stroke).wireEffect,
      DrawingWireEffect.appendStroke,
    );
    expect(controller.undo().wireEffect, DrawingWireEffect.undo);
    expect(controller.redo().wireEffect, DrawingWireEffect.redo);
  });

  test('one erase gesture removes every hit pen stroke as one undo unit', () {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    controller.addStroke(_stroke(Offset.zero));
    controller.addStroke(_stroke(const Offset(0, 8)));
    controller.addStroke(_stroke(const Offset(0, 40)));

    controller.beginStrokeEraseGesture();
    expect(controller.eraseStrokeAt(const Offset(10, 0), radius: 4), isTrue);
    expect(controller.eraseStrokeAt(const Offset(10, 8), radius: 4), isTrue);
    expect(controller.endStrokeEraseGesture().changed, isTrue);
    expect(controller.visibleStrokes, hasLength(1));

    controller.undo();
    expect(controller.visibleStrokes, hasLength(3));
    expect(controller.redo().changed, isTrue);
    expect(controller.visibleStrokes, hasLength(1));
  });

  test(
    'new action discards redo and clear removes active plus redo history',
    () {
      final controller = DrawingDocumentController();
      addTearDown(controller.dispose);
      controller.addStroke(_stroke(Offset.zero));
      controller.undo();
      expect(controller.canRedo, isTrue);

      controller.addStroke(_stroke(const Offset(30, 30)));
      expect(controller.canRedo, isFalse);
      expect(controller.clearAll().changed, isTrue);
      expect(controller.actions, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
    },
  );

  test('completing an erase publishes redo invalidation after the gesture', () {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    controller.addStroke(_stroke(Offset.zero));
    controller.addStroke(_stroke(const Offset(30, 30)));
    controller.undo();
    final redoStates = <bool>[];
    controller.addListener(() => redoStates.add(controller.canRedo));

    controller.beginStrokeEraseGesture();
    expect(controller.eraseStrokeAt(const Offset(10, 0), radius: 1), isTrue);
    expect(controller.endStrokeEraseGesture().changed, isTrue);

    expect(redoStates, [true, false]);
    expect(controller.canRedo, isFalse);
  });

  test('clearing redo-only history notifies listeners', () {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    controller.addStroke(_stroke(Offset.zero));
    controller.undo();
    var notificationCount = 0;
    controller.addListener(() => notificationCount += 1);

    final change = controller.clearAll();

    expect(change.changed, isFalse);
    expect(controller.canRedo, isFalse);
    expect(notificationCount, 1);
  });

  test('cancelling an erase restores its original actions', () {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    controller.addStroke(_stroke(Offset.zero));

    controller.beginStrokeEraseGesture();
    controller.eraseStrokeAt(const Offset(10, 0), radius: 1);
    controller.cancelStrokeEraseGesture();

    expect(controller.visibleStrokes, hasLength(1));
    expect(controller.canUndo, isTrue);
  });

  test('eraser-only actions do not count as visible content', () {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);

    controller.addStroke(
      _stroke(Offset.zero).copyWith(tool: DrawingTool.eraser),
    );

    expect(controller.hasVisibleContent, isFalse);
  });

  test(
    'action IDs and texture seeds remain monotonic across history changes',
    () {
      final controller = DrawingDocumentController(initialTextureSeed: 11);
      addTearDown(controller.dispose);

      controller.addStroke(_stroke(Offset.zero));
      controller.undo();
      controller.redo();
      controller.clearAll();
      controller.addStroke(_stroke(const Offset(30, 30)));

      final action = controller.actions.single as DrawingStrokeAction;
      expect(action.id, 2);
      expect(action.stroke.textureSeed, 12);
    },
  );

  test('public action and stroke views cannot mutate document state', () {
    final controller = DrawingDocumentController();
    addTearDown(controller.dispose);
    controller.addStroke(_stroke(Offset.zero));

    expect(() => controller.actions.clear(), throwsUnsupportedError);
    expect(() => controller.visibleStrokes.clear(), throwsUnsupportedError);
    expect(controller.actions, hasLength(1));
  });
}

DrawingStroke _stroke(Offset offset) => DrawingStroke(
  points: [
    DrawingPoint(position: offset, elapsedMilliseconds: 0),
    DrawingPoint(
      position: offset + const Offset(20, 0),
      elapsedMilliseconds: 10,
    ),
  ],
  color: AppColors.drawingRed,
  thickness: 8,
);

Future<ui.Image> _patch() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = AppColors.drawingBlue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  return image;
}
