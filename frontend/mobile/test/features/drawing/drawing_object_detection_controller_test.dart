import 'dart:async';

import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('마지막 입력 후 debounce가 끝나면 최신 DRAFT를 저장하고 탐지를 요청한다', () async {
    var saveCalls = 0;
    final requestedAssetIds = <int>[];
    final controller = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 10),
      saveDraft: () async {
        saveCalls += 1;
        return _draft(120);
      },
      requestDetection: (assetId) async {
        requestedAssetIds.add(assetId);
        return _detection(assetId);
      },
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(saveCalls, 1);
    expect(requestedAssetIds, [120]);
    expect(controller.status, DrawingObjectDetectionStatus.succeeded);
    expect(controller.validResult?.drawingAssetId, 120);
  });

  test('탐지 중 새 입력이 시작되면 이전 결과를 적용하지 않는다', () async {
    final detection = Completer<ObjectDetectionResponseDto>();
    final controller = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 10),
      saveDraft: () async => _draft(120),
      requestDetection: (_) => detection.future,
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.status, DrawingObjectDetectionStatus.requesting);

    controller.onDrawingInputStarted();
    detection.complete(_detection(120));
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, DrawingObjectDetectionStatus.idle);
    expect(controller.validResult, isNull);
  });

  test('같은 drawingAssetId에는 객체 탐지를 한 번만 요청한다', () async {
    var requestCalls = 0;
    final controller = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 5),
      saveDraft: () async => _draft(120),
      requestDetection: (assetId) async {
        requestCalls += 1;
        return _detection(assetId);
      },
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(requestCalls, 1);
    expect(controller.status, DrawingObjectDetectionStatus.idle);
  });

  test('두 번째 입력은 첫 번째 debounce를 취소하고 마지막 그림만 저장한다', () async {
    var saveCalls = 0;
    final controller = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 15),
      saveDraft: () async {
        saveCalls += 1;
        return _draft(120 + saveCalls);
      },
      requestDetection: (assetId) async => _detection(assetId),
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(saveCalls, 1);
    expect(controller.validResult?.drawingAssetId, 121);
  });

  test('응답 drawingAssetId가 최신 DRAFT와 다르면 유효 결과로 저장하지 않는다', () async {
    final controller = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 5),
      saveDraft: () async => _draft(120),
      requestDetection: (_) async => _detection(119),
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.status, DrawingObjectDetectionStatus.failed);
    expect(controller.validResult, isNull);
  });
}

DraftSaveResponseDto _draft(int assetId) => DraftSaveResponseDto(
  drawingAssetId: assetId,
  assetVersion: assetId,
  lastEventSequence: assetId,
  savedAt: '2026-07-23T06:00:00Z',
  expiresAt: null,
);

ObjectDetectionResponseDto _detection(int assetId) =>
    ObjectDetectionResponseDto(
      drawingAnalysisId: 700,
      drawingSessionId: 42,
      drawingAssetId: assetId,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      analysisType: 'OBJECT_DETECTION',
      status: 'SUCCEEDED',
      model: const DrawingAnalysisModelDto(
        name: 'dodam-detector',
        version: '1.0',
      ),
      detections: const [],
      requestedAt: '2026-07-23T06:00:00Z',
      processedAt: '2026-07-23T06:00:01Z',
    );
