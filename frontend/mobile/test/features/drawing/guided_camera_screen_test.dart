import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dodam/features/drawing/domain/photo_permission_service.dart';
import 'package:dodam/features/drawing/domain/photo_picker_adapter.dart';
import 'package:dodam/features/drawing/presentation/screens/guided_camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _backCamera = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

void main() {
  testWidgets('inactive 이후 resumed에서 controller를 한 번 재초기화한다', (tester) async {
    final first = _FakeCameraController();
    final second = _FakeCameraController();
    final platform = _FakeCameraPlatform(controllers: [first, second]);
    await _pumpCamera(tester, platform: platform);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await _lifecycle(tester, AppLifecycleState.inactive);
    expect(first.disposeCalls, 1);
    expect(find.byKey(const ValueKey('guided-camera-preview')), findsNothing);

    await _lifecycle(tester, AppLifecycleState.resumed);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );
    expect(platform.createCalls, 2);
    expect(second.initializeCalls, 1);
  });

  testWidgets('paused 이후 중복 resumed에도 initialization은 한 번이다', (tester) async {
    final first = _FakeCameraController();
    final second = _FakeCameraController();
    final platform = _FakeCameraPlatform(controllers: [first, second]);
    await _pumpCamera(tester, platform: platform);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    expect(platform.availableCalls, 2);
    expect(platform.createCalls, 2);
    expect(second.initializeCalls, 1);
  });

  testWidgets('늦은 initialization은 무시하고 자신이 만든 controller만 정리한다', (
    tester,
  ) async {
    final pending = Completer<void>();
    final stale = _FakeCameraController(initializeCompleter: pending);
    final current = _FakeCameraController();
    final platform = _FakeCameraPlatform(controllers: [stale, current]);
    await _pumpCamera(tester, platform: platform, pumpFrames: 3);
    expect(stale.initializeCalls, 1);

    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.resumed);
    pending.complete();
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    expect(stale.disposeCalls, 1);
    expect(current.disposeCalls, 0);
    expect(current.initializeCalls, 1);
  });

  testWidgets('initialize 중 화면을 닫아도 늦은 결과는 setState하지 않고 정리한다', (tester) async {
    final pending = Completer<void>();
    final controller = _FakeCameraController(initializeCompleter: pending);
    final harness = await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
      pumpFrames: 3,
    );

    await tester.tap(find.byKey(const ValueKey('guided-camera-close')));
    await tester.pump();
    pending.complete();
    await _pumpFrames(tester, 6);

    expect(harness.popCount, 1);
    expect(controller.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied는 controller 없이 재요청하고 허용되면 초기화한다', (tester) async {
    final permissions = _FakePermissionService(
      statusValue: PhotoPermissionStatus.denied,
      requestValue: PhotoPermissionStatus.denied,
    );
    final platform = _FakeCameraPlatform();
    await _pumpCamera(tester, platform: platform, permissions: permissions);
    await _pumpUntil(tester, find.text('카메라 권한이 필요해요'));

    expect(find.byKey(const ValueKey('guided-camera-retry')), findsOneWidget);
    expect(find.text('권한 다시 요청'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guided-camera-open-settings')),
      findsNothing,
    );
    expect(permissions.requestCalls, 1);
    expect(platform.createCalls, 0);

    permissions.requestValue = PhotoPermissionStatus.granted;
    await tester.tap(find.byKey(const ValueKey('guided-camera-retry')));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    expect(permissions.requestCalls, 2);
    expect(platform.createCalls, 1);
  });

  testWidgets('permanentlyDenied는 설정 이동만 제공한다', (tester) async {
    final permissions = _FakePermissionService(
      statusValue: PhotoPermissionStatus.permanentlyDenied,
    );
    final platform = _FakeCameraPlatform();
    await _pumpCamera(tester, platform: platform, permissions: permissions);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-open-settings')),
    );

    expect(find.byKey(const ValueKey('guided-camera-retry')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('guided-camera-open-settings')));
    await tester.pump();
    expect(permissions.openSettingsCalls, 1);
    expect(platform.createCalls, 0);
  });

  testWidgets('설정 복귀 resumed에서 권한을 다시 확인하고 초기화한다', (tester) async {
    final permissions = _FakePermissionService(
      statusValue: PhotoPermissionStatus.permanentlyDenied,
    );
    final controller = _FakeCameraController();
    final platform = _FakeCameraPlatform(controllers: [controller]);
    await _pumpCamera(tester, platform: platform, permissions: permissions);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-open-settings')),
    );

    await tester.tap(find.byKey(const ValueKey('guided-camera-open-settings')));
    await tester.pump();
    await _lifecycle(tester, AppLifecycleState.inactive);
    permissions.statusValue = PhotoPermissionStatus.granted;
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    expect(permissions.statusCalls, 2);
    expect(permissions.requestCalls, 0);
    expect(platform.createCalls, 1);
  });

  testWidgets('restricted는 제한 안내를 보이고 설정 CTA를 노출하지 않는다', (tester) async {
    final platform = _FakeCameraPlatform();
    await _pumpCamera(
      tester,
      platform: platform,
      permissions: _FakePermissionService(
        statusValue: PhotoPermissionStatus.restricted,
      ),
    );
    await _pumpUntil(tester, find.text('카메라 사용이 제한되어 있어요'));

    expect(
      find.byKey(const ValueKey('guided-camera-open-settings')),
      findsNothing,
    );
    expect(find.textContaining('보호자 정책'), findsOneWidget);
    expect(platform.createCalls, 0);
  });

  testWidgets('사용 가능한 카메라가 없으면 하드웨어 오류와 재시도를 표시한다', (tester) async {
    final platform = _FakeCameraPlatform(cameras: const []);
    await _pumpCamera(tester, platform: platform);
    await _pumpUntil(tester, find.text('카메라를 찾지 못했어요'));

    expect(find.byKey(const ValueKey('guided-camera-retry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guided-camera-open-settings')),
      findsNothing,
    );
    expect(platform.createCalls, 0);
  });

  testWidgets('initialize 실패 후 재시도는 새 controller로 정상 복구한다', (tester) async {
    final failed = _FakeCameraController(initializeError: StateError('failed'));
    final pending = Completer<void>();
    final recovered = _FakeCameraController(initializeCompleter: pending);
    final platform = _FakeCameraPlatform(controllers: [failed, recovered]);
    await _pumpCamera(tester, platform: platform);
    await _pumpUntil(tester, find.text('카메라를 열 수 없어요'));

    expect(failed.disposeCalls, 1);
    await tester.tap(find.byKey(const ValueKey('guided-camera-retry')));
    await tester.tap(find.byKey(const ValueKey('guided-camera-retry')));
    expect(platform.createCalls, 2);
    pending.complete();
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    expect(platform.createCalls, 2);
    expect(recovered.initializeCalls, 1);
    expect(recovered.disposeCalls, 0);
  });

  testWidgets('촬영 성공은 기존 PickedPhoto route 결과를 한 번 반환한다', (tester) async {
    final photo = PickedPhoto(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'house.jpg',
      mimeType: 'image/jpeg',
    );
    final controller = _FakeCameraController(captureResult: photo);
    final harness = await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await tester.tap(find.byKey(const ValueKey('guided-camera-capture')));
    await tester.pumpAndSettle();

    expect(harness.popCount, 1);
    expect(harness.result, same(photo));
    expect(controller.captureCalls, 1);
    expect(controller.disposeCalls, 1);
  });

  testWidgets('촬영 버튼 연타에도 capture와 route 결과는 한 번이다', (tester) async {
    final pending = Completer<PickedPhoto>();
    final controller = _FakeCameraController(captureCompleter: pending);
    final harness = await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await tester.tap(find.byKey(const ValueKey('guided-camera-capture')));
    await tester.tap(find.byKey(const ValueKey('guided-camera-capture')));
    expect(controller.captureCalls, 1);

    pending.complete(controller.captureResult);
    await tester.pumpAndSettle();
    expect(controller.captureCalls, 1);
    expect(harness.popCount, 1);
    expect(harness.result, same(controller.captureResult));
  });

  testWidgets('닫기 버튼은 route를 한 번 pop하고 controller를 정리한다', (tester) async {
    final controller = _FakeCameraController();
    final harness = await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await tester.tap(find.byKey(const ValueKey('guided-camera-close')));
    await tester.pumpAndSettle();

    expect(harness.popCount, 1);
    expect(controller.disposeCalls, 1);
  });

  testWidgets('시스템 back도 route를 한 번 pop하고 controller를 정리한다', (tester) async {
    final controller = _FakeCameraController();
    final harness = await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(harness.popCount, 1);
    expect(controller.disposeCalls, 1);
  });

  testWidgets('preview와 guide overlay는 같은 실제 preview 좌표계를 사용한다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(
        controllers: [_FakeCameraController(aspectRatio: 4 / 3)],
      ),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    final preview = find.byKey(const ValueKey('guided-camera-preview'));
    final guide = find.byKey(const ValueKey('guided-camera-guide'));
    expect(tester.getSize(preview), tester.getSize(guide));
    expect(tester.getTopLeft(preview), tester.getTopLeft(guide));
    expect(tester.getSize(preview).aspectRatio, closeTo(4 / 3, 0.01));
  });

  testWidgets('초점 좌표는 letterbox가 아닌 preview 박스 기준 0~1로 전달한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _FakeCameraController(aspectRatio: 4 / 3);
    await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
    );
    final focusArea = find.byKey(const ValueKey('guided-camera-focus-area'));
    await _pumpUntil(tester, focusArea);
    final rect = tester.getRect(focusArea);

    await tester.tapAt(
      rect.topLeft + Offset(rect.width * 0.25, rect.height * 0.75),
    );
    await _pumpFrames(tester, 3);

    expect(controller.focusPoints.single.dx, closeTo(0.25, 0.01));
    expect(controller.focusPoints.single.dy, closeTo(0.75, 0.01));
    expect(controller.exposurePoints.single, controller.focusPoints.single);
  });

  testWidgets('inactive paused hidden 반복에도 같은 controller dispose는 한 번이다', (
    tester,
  ) async {
    final first = _FakeCameraController();
    final second = _FakeCameraController();
    await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [first, second]),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.hidden);
    expect(first.disposeCalls, 1);

    await _lifecycle(tester, AppLifecycleState.resumed);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );
    expect(second.initializeCalls, 1);
  });

  testWidgets('detached 이후 resumed는 재초기화하지 않는다', (tester) async {
    final first = _FakeCameraController();
    final platform = _FakeCameraPlatform(controllers: [first]);
    await _pumpCamera(tester, platform: platform);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await _lifecycle(tester, AppLifecycleState.detached);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _pumpFrames(tester, 5);

    expect(first.disposeCalls, 1);
    expect(platform.createCalls, 1);
    expect(find.byKey(const ValueKey('guided-camera-preview')), findsNothing);
  });

  testWidgets('설정 화면을 열지 못하면 복구 안내를 표시한다', (tester) async {
    final permissions = _FakePermissionService(
      statusValue: PhotoPermissionStatus.permanentlyDenied,
      openSettingsResult: false,
    );
    await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(),
      permissions: permissions,
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-open-settings')),
    );

    await tester.tap(find.byKey(const ValueKey('guided-camera-open-settings')));
    await _pumpFrames(tester, 3);

    expect(permissions.openSettingsCalls, 1);
    expect(find.textContaining('설정 화면을 열지 못했어요'), findsWidgets);
  });

  testWidgets('CameraException 점유 오류는 설정 CTA 없이 별도 안내한다', (tester) async {
    final controller = _FakeCameraController(
      initializeError: CameraException('CameraInUse', 'busy'),
    );
    await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
    );
    await _pumpUntil(tester, find.text('카메라를 사용 중이에요'));

    expect(find.textContaining('다른 앱'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guided-camera-open-settings')),
      findsNothing,
    );
  });

  testWidgets('촬영 실패는 화면을 유지하고 재촬영 가능한 안내를 표시한다', (tester) async {
    final controller = _FakeCameraController(
      captureError: StateError('failed'),
    );
    final harness = await _pumpCamera(
      tester,
      platform: _FakeCameraPlatform(controllers: [controller]),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('guided-camera-preview')),
    );

    await tester.tap(find.byKey(const ValueKey('guided-camera-capture')));
    await _pumpFrames(tester, 3);

    expect(harness.popCount, 0);
    expect(controller.captureCalls, 1);
    expect(find.textContaining('사진을 찍지 못했어요'), findsWidgets);
    expect(find.byKey(const ValueKey('guided-camera-preview')), findsOneWidget);
  });
}

Future<_CameraHarness> _pumpCamera(
  WidgetTester tester, {
  required _FakeCameraPlatform platform,
  _FakePermissionService? permissions,
  int pumpFrames = 8,
}) async {
  final harness = _CameraHarness();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: harness.navigatorKey,
      home: const Scaffold(body: Text('camera-host')),
    ),
  );
  unawaited(
    harness.navigatorKey.currentState!
        .push<Object?>(
          MaterialPageRoute<Object?>(
            builder: (_) => GuidedCameraScreen(
              drawingSubject: 'HOUSE',
              cameraPlatform: platform,
              permissionService:
                  permissions ??
                  _FakePermissionService(
                    statusValue: PhotoPermissionStatus.granted,
                  ),
              tutorialStore: _FakeTutorialStore(),
            ),
          ),
        )
        .then((value) {
          harness
            ..result = value
            ..popCount += 1;
        }),
  );
  await _pumpFrames(tester, pumpFrames);
  return harness;
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
}) async {
  for (var index = 0; index < maxFrames && finder.evaluate().isEmpty; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(finder, findsOneWidget);
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  tester.binding.handleAppLifecycleStateChanged(state);
  await _pumpFrames(tester, 4);
}

final class _CameraHarness {
  final navigatorKey = GlobalKey<NavigatorState>();
  Object? result;
  int popCount = 0;
}

final class _FakeCameraPlatform implements GuidedCameraPlatform {
  _FakeCameraPlatform({
    this.cameras = const [_backCamera],
    List<_FakeCameraController>? controllers,
  }) : controllers = controllers ?? <_FakeCameraController>[];

  final List<CameraDescription> cameras;
  final List<_FakeCameraController> controllers;
  int availableCalls = 0;
  int createCalls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    availableCalls += 1;
    return cameras;
  }

  @override
  GuidedCameraController createController(CameraDescription description) {
    final index = createCalls;
    createCalls += 1;
    if (index < controllers.length) return controllers[index];
    final controller = _FakeCameraController();
    controllers.add(controller);
    return controller;
  }
}

final class _FakeCameraController implements GuidedCameraController {
  _FakeCameraController({
    this.aspectRatio = 4 / 3,
    this.initializeCompleter,
    this.initializeError,
    this.captureCompleter,
    PickedPhoto? captureResult,
    this.captureError,
  }) : captureResult =
           captureResult ??
           PickedPhoto(
             bytes: Uint8List.fromList([9, 8, 7]),
             fileName: 'capture.jpg',
             mimeType: 'image/jpeg',
           );

  @override
  final double aspectRatio;
  final Completer<void>? initializeCompleter;
  final Object? initializeError;
  final Completer<PickedPhoto>? captureCompleter;
  final PickedPhoto captureResult;
  final Object? captureError;

  @override
  bool isInitialized = false;
  int initializeCalls = 0;
  int disposeCalls = 0;
  int captureCalls = 0;
  final List<Offset> focusPoints = [];
  final List<Offset> exposurePoints = [];

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    await initializeCompleter?.future;
    if (initializeError case final error?) throw error;
    isInitialized = true;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    isInitialized = false;
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {}

  @override
  Future<void> setFocusPoint(Offset point) async => focusPoints.add(point);

  @override
  Future<void> setExposurePoint(Offset point) async =>
      exposurePoints.add(point);

  @override
  Future<PickedPhoto> takePicture() async {
    captureCalls += 1;
    if (captureCompleter case final completer?) return completer.future;
    if (captureError case final error?) throw error;
    return captureResult;
  }
}

final class _FakePermissionService implements PhotoPermissionService {
  _FakePermissionService({
    required this.statusValue,
    PhotoPermissionStatus? requestValue,
    this.openSettingsResult = true,
  }) : requestValue = requestValue ?? statusValue;

  PhotoPermissionStatus statusValue;
  PhotoPermissionStatus requestValue;
  final bool openSettingsResult;
  int statusCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<PhotoPermissionStatus> status(PhotoPermissionKind kind) async {
    statusCalls += 1;
    return statusValue;
  }

  @override
  Future<PhotoPermissionStatus> request(PhotoPermissionKind kind) async {
    requestCalls += 1;
    return requestValue;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls += 1;
    return openSettingsResult;
  }
}

final class _FakeTutorialStore implements GuidedCameraTutorialStore {
  @override
  Future<bool> isHidden() async => true;

  @override
  Future<void> hide() async {}
}
