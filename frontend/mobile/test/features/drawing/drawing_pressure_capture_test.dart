import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/application/drawing_sync_coordinator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// S15P11B209-481 — 실제 DrawingScreen의 pointer 흐름으로 필압이
/// journal 이벤트(=Stroke Batch payload 원천)까지 전달되는지 고정한다.
///
/// 정책 계산 자체는 `drawing_pressure_policy_test`가 담당하고, 여기서는
/// production 배선(Listener → _pointFrom → journal → DTO JSON)만 검증한다.
void main() {
  testWidgets('stylus down·move의 필압이 journal 이벤트에 그대로 남는다', (tester) async {
    final coordinator = await _pumpDrawing(tester);

    await _strokeWithPressure(tester, down: 0.4, mid: 0.6, up: 0.8);

    final events = _settle(coordinator).journal.events;
    expect(events.map((event) => event.type), [
      'STROKE_START',
      'STROKE_MOVE',
      'STROKE_END',
    ]);
    expect(events.map((event) => event.pressure), [0.4, 0.6, 0.8]);
  });

  testWidgets('invertedStylus 필압도 기록한다', (tester) async {
    final coordinator = await _pumpDrawing(tester);

    await _strokeWithPressure(
      tester,
      kind: PointerDeviceKind.invertedStylus,
      down: 0.2,
      mid: 0.5,
      up: 0.9,
    );

    expect(_settle(coordinator).journal.events.map((event) => event.pressure), [
      0.2,
      0.5,
      0.9,
    ]);
  });

  testWidgets('일반 터치 gesture는 필압 없이 기록되고 JSON에서 필드가 생략된다', (tester) async {
    final coordinator = await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );

    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(30, 18));
    await gesture.up();
    await tester.pump();

    final events = _settle(coordinator).journal.events;
    expect(events, isNotEmpty);
    expect(events.map((event) => event.pressure), everyElement(isNull));
    for (final event in events) {
      expect(event.toJson(), isNot(contains('pressure')));
    }
  });

  testWidgets('필압 범위를 보고하지 않는 stylus(min==max)는 null로 기록한다', (tester) async {
    final coordinator = await _pumpDrawing(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );

    // TestPointer 기본값이 실제 무압 기기 보고(p=1.0, min=max=1.0)와 같다.
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveBy(const Offset(24, 12));
    await gesture.up();
    await tester.pump();

    final events = _settle(coordinator).journal.events;
    expect(events, isNotEmpty);
    expect(events.map((event) => event.pressure), everyElement(isNull));
  });

  testWidgets('필압 0.0은 null과 구분되어 JSON에 0.0으로 남는다', (tester) async {
    final coordinator = await _pumpDrawing(tester);

    await _strokeWithPressure(tester, down: 0.0, mid: 0.0, up: 0.0);

    final start = _settle(coordinator).journal.events.first;
    expect(start.pressure, 0.0);
    expect(start.toJson(), containsPair('pressure', 0.0));
  });

  testWidgets('1.0 초과 필압은 배선 전체에서 1.0으로 포화된다', (tester) async {
    final coordinator = await _pumpDrawing(tester);

    await _strokeWithPressure(tester, down: 1.25, mid: 1.3, up: 1.25, max: 1.3);

    expect(
      _settle(coordinator).journal.events.map((event) => event.pressure),
      everyElement(1.0),
    );
  });
}

Future<DrawingSyncCoordinator> _pumpDrawing(WidgetTester tester) async {
  final coordinator = DrawingSyncCoordinator(sessionId: null, repository: null);
  addTearDown(coordinator.dispose);
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: DrawingScreen(childId: '3', syncCoordinator: coordinator),
    ),
  );
  await tester.pumpAndSettle();
  return coordinator;
}

/// 주입한 coordinator는 화면이 소유하지 않아 주기 타이머가 남는다.
/// 단언 전에 멈춰 pending timer invariant를 지킨다.
DrawingSyncCoordinator _settle(DrawingSyncCoordinator coordinator) {
  coordinator.pause();
  return coordinator;
}

/// TestPointer는 필압을 지정할 수 없어 raw PointerEvent를 실제 hit test
/// 경로(binding.handlePointerEvent)로 직접 흘린다 — production Listener가
/// 받는 이벤트와 동일한 경로다.
Future<void> _strokeWithPressure(
  WidgetTester tester, {
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  required double down,
  required double mid,
  required double up,
  double min = 0.0,
  double max = 1.0,
}) async {
  final center = tester.getCenter(find.byKey(const ValueKey('drawing-canvas')));
  const pointer = 917;
  tester.binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      kind: kind,
      position: center,
      pressure: down,
      pressureMin: min,
      pressureMax: max,
    ),
  );
  tester.binding.handlePointerEvent(
    PointerMoveEvent(
      pointer: pointer,
      kind: kind,
      position: center + const Offset(20, 10),
      delta: const Offset(20, 10),
      pressure: mid,
      pressureMin: min,
      pressureMax: max,
    ),
  );
  tester.binding.handlePointerEvent(
    PointerMoveEvent(
      pointer: pointer,
      kind: kind,
      position: center + const Offset(40, 20),
      delta: const Offset(20, 10),
      pressure: up,
      pressureMin: min,
      pressureMax: max,
    ),
  );
  tester.binding.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      kind: kind,
      position: center + const Offset(40, 20),
      pressureMin: min,
      pressureMax: max,
    ),
  );
  await tester.pump();
}
