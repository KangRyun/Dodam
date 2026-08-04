import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'drawing_stroke.dart';

sealed class DrawingCanvasAction {
  const DrawingCanvasAction({required this.id});

  final int id;
}

final class DrawingStrokeAction extends DrawingCanvasAction {
  const DrawingStrokeAction({required super.id, required this.stroke});

  final DrawingStroke stroke;
}

final class DrawingFillAction extends DrawingCanvasAction {
  const DrawingFillAction({
    required super.id,
    required this.patch,
    required this.documentSize,
  });

  final ui.Image patch;
  final Size documentSize;
}
