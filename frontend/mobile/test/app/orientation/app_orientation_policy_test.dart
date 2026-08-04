import 'dart:async';

import 'package:dodam/app/orientation/app_orientation_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup은 두 가로 방향을 한 번만 요청한다', (tester) async {
    final calls = <List<DeviceOrientation>>[];
    final policy = AppOrientationPolicy(
      setPreferredOrientations: (orientations) async {
        calls.add(List.of(orientations));
      },
    );
    addTearDown(() {
      policy.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    expect(await policy.start(), isTrue);
    expect(await policy.start(), isTrue);
    expect(await policy.ensureLandscape(), isTrue);

    expect(calls, [
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    ]);
  });

  testWidgets('paused·hidden 연속 통지 뒤 resume은 한 번만 재적용한다', (tester) async {
    final calls = <List<DeviceOrientation>>[];
    final policy = AppOrientationPolicy(
      setPreferredOrientations: (orientations) async {
        calls.add(List.of(orientations));
      },
    );
    addTearDown(() {
      policy.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await policy.start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, hasLength(2));
  });

  testWidgets('갤러리 picker와 앱 설정에서 각각 복귀하면 landscape를 재확인한다', (tester) async {
    var calls = 0;
    final policy = AppOrientationPolicy(
      setPreferredOrientations: (_) async => calls += 1,
    );
    addTearDown(() {
      policy.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await policy.start();

    // Gallery/Photo Picker가 앱을 가리는 lifecycle 순서.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // OS 앱 설정을 열었다 돌아오는 lifecycle 순서.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, 3);
  });

  testWidgets('빠른 background·resume에서는 오래된 완료 뒤 최신 generation을 적용한다', (
    tester,
  ) async {
    final secondAttempt = Completer<void>();
    var calls = 0;
    final policy = AppOrientationPolicy(
      setPreferredOrientations: (_) {
        calls += 1;
        if (calls == 2) return secondAttempt.future;
        return Future<void>.value();
      },
    );
    addTearDown(() {
      policy.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await policy.start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(calls, 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(calls, 2);

    secondAttempt.complete();
    await tester.pump();
    await tester.pump();

    expect(calls, 3);
  });

  testWidgets('orientation 적용 실패는 보고하고 앱 흐름을 막지 않으며 복귀 때 재시도한다', (
    tester,
  ) async {
    final errors = <Object>[];
    var calls = 0;
    final policy = AppOrientationPolicy(
      setPreferredOrientations: (_) async {
        calls += 1;
        if (calls == 1) throw StateError('platform failure');
      },
      reportError: (error, _) => errors.add(error),
    );
    addTearDown(() {
      policy.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    expect(await policy.start(), isFalse);
    expect(errors.single, isA<StateError>());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, 2);
    expect(await policy.ensureLandscape(), isTrue);
  });

  testWidgets('dispose 이후 lifecycle과 직접 요청은 orientation을 적용하지 않는다', (
    tester,
  ) async {
    var calls = 0;
    final policy = AppOrientationPolicy(
      setPreferredOrientations: (_) async => calls += 1,
    );
    await policy.start();
    policy.markPlatformStateUncertain();
    policy.dispose();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(await policy.ensureLandscape(), isFalse);
    expect(await policy.start(), isFalse);
    expect(calls, 1);
  });

  testWidgets('진행 중 호출이 dispose 뒤 완료돼도 추가 적용이나 오류 보고를 하지 않는다', (tester) async {
    final pending = Completer<void>();
    final errors = <Object>[];
    var calls = 0;
    final policy = AppOrientationPolicy(
      setPreferredOrientations: (_) {
        calls += 1;
        if (calls == 2) return pending.future;
        return Future<void>.value();
      },
      reportError: (error, _) => errors.add(error),
    );
    await policy.start();
    policy.markPlatformStateUncertain();
    final applying = policy.ensureLandscape();
    expect(calls, 2);

    policy.dispose();
    pending.complete();

    expect(await applying, isFalse);
    expect(await policy.ensureLandscape(), isFalse);
    expect(calls, 2);
    expect(errors, isEmpty);
  });
}
