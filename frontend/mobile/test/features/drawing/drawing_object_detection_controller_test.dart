import 'dart:async';

import 'package:dodam/features/drawing/application/drawing_object_detection_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('마지막 입력 후 debounce가 끝나면 최신 DRAFT를 저장하고 탐지를 요청한다', () async {
    var saveCalls = 0;
    final requests = <Object>[];
    final controller = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 10),
      saveDraft: () async {
        saveCalls += 1;
        return _draft(120);
      },
      requestDetection: (request) async {
        requests.add(request);
        return _detection(request.drawingAssetId);
      },
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await _waitForStatus(controller, DrawingObjectDetectionStatus.succeeded);

    expect(saveCalls, 1);
    expect(requests.single, isA<ObjectDetectionRequestDto>());
    expect(
      (requests.single as ObjectDetectionRequestDto).toJson(),
      containsPair('triggerReason', 'PAUSE'),
    );
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
    await _waitForStatus(controller, DrawingObjectDetectionStatus.requesting);

    controller.onDrawingInputStarted();
    detection.complete(_detection(120));
    // 완료 콜백은 마이크로태스크로 예약되고 zero 타이머는 그 뒤에 돈다 — 시간 가정이 아니다.
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, DrawingObjectDetectionStatus.idle);
    expect(controller.validResult, isNull);
  });

  test('같은 drawingAssetId에는 객체 탐지를 한 번만 요청한다', () async {
    var requestCalls = 0;
    final controller = DrawingObjectDetectionController(
      debounceDuration: const Duration(milliseconds: 5),
      saveDraft: () async => _draft(120),
      requestDetection: (request) async {
        requestCalls += 1;
        return _detection(request.drawingAssetId);
      },
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await _waitForStatus(controller, DrawingObjectDetectionStatus.succeeded);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    // 2회차는 같은 assetId 라 요청 없이 idle 로 되돌아온다. saving 까지 기다린 뒤
    //   saveDraft 이후 연속 실행(전부 마이크로태스크)을 zero 타이머로 흘려보내면
    //   그 분기가 끝나 있다 — "20ms 면 되겠지"가 아니라 순서가 보장된다.
    await _waitForStatus(controller, DrawingObjectDetectionStatus.saving);
    await Future<void>.delayed(Duration.zero);

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
      requestDetection: (request) async => _detection(request.drawingAssetId),
    );
    addTearDown(controller.dispose);

    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    // 첫 debounce 가 살아 있는 동안 두 번째 입력이 들어오는 상황이다. 원래는 15ms 중
    //   5ms 만 자고 "아직 안 터졌겠지"를 가정했는데 — 앞의 것들과 방향만 반대인 같은 결함이다.
    //   부하가 걸리면 그 사이 타이머가 터져 저장이 2회가 된다. 대기 없이 이어 호출하면
    //   가정 자체가 사라지고, 검증하려던 것(두 번째 입력이 첫 debounce 를 취소한다)은 그대로다.
    controller.onDrawingInputStarted();
    controller.onDrawingInputEnded();
    await _waitForStatus(controller, DrawingObjectDetectionStatus.succeeded);

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
    await _waitForStatus(controller, DrawingObjectDetectionStatus.failed);

    expect(controller.validResult, isNull);
  });

  test('dispose 뒤 도착한 객체 탐지 응답은 상태를 갱신하지 않는다', () async {
    final detection = Completer<ObjectDetectionResponseDto>();
    final controller = DrawingObjectDetectionController(
      debounceDuration: Duration.zero,
      saveDraft: () async => _draft(120),
      requestDetection: (_) => detection.future,
    );

    controller.onDrawingInputEnded();
    // requesting 까지 확실히 보낸 뒤 dispose 한다. zero 타이머 한 번만 흘리면
    //   요청이 나가기 전에 dispose 될 수도 있어, 정작 이름이 말하는 상황
    //   ("dispose 뒤 도착한 응답")을 검증하지 못한 채 통과할 수 있다.
    await _waitForStatus(controller, DrawingObjectDetectionStatus.requesting);
    controller.dispose();
    detection.complete(_detection(120));

    await expectLater(Future<void>.delayed(Duration.zero), completes);
  });
}

/// 컨트롤러가 [target] 상태에 도달할 때까지 기다린다.
///
/// 왜 고정 시간을 자지 않는가: 이 파일은 원래 `await Future.delayed(20ms)` 뒤에
/// 상태를 단정했는데, 5~10ms 디바운스 타이머와 그 뒤 async 연속 실행이 20ms 안에
/// 끝난다는 보장이 없다. 부하가 걸린 CI 에서 실제로 깨졌다 —
/// 2026-08-09 빌드 #345·#346 이 load average 25 에서 `saving` 을 붙잡고 실패했고,
/// 프로덕션 코드는 멀쩡했다. 상태 변화를 구독하면 도달 즉시 깨므로
/// 결정적이면서 고정 대기보다 빠르다(느린 기계에서도 안 깨지고, 빠른 기계에서 안 논다).
Future<void> _waitForStatus(
  DrawingObjectDetectionController controller,
  DrawingObjectDetectionStatus target,
) {
  if (controller.status == target) return Future<void>.value();
  final reached = Completer<void>();
  void listener() {
    if (controller.status == target && !reached.isCompleted) reached.complete();
  }

  controller.addListener(listener);
  // 영원히 매달리는 대신 현재 상태를 담아 명확히 실패시킨다.
  return reached.future
      .timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
          '$target 상태에 도달하지 못했다 (현재: ${controller.status})',
        ),
      )
      .whenComplete(() => controller.removeListener(listener));
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
