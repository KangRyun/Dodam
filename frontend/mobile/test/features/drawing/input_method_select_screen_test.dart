import 'dart:async';
import 'dart:convert';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/drawing/application/drawing_session_start_controller.dart';
import 'package:dodam/features/drawing/application/drawing_upload_error.dart';
import 'package:dodam/features/drawing/application/photo_upload_validation.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/photo_permission_service.dart';
import 'package:dodam/features/drawing/domain/photo_picker_adapter.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/screens/input_method_select_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1Pe'
  'AAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

void main() {
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    void Function(DrawingSessionResolution?)? onPopped,
  }) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
    );
    unawaited(
      navigatorKey.currentState!
          .push<DrawingSessionResolution>(
            MaterialPageRoute(builder: (_) => screen),
          )
          .then(onPopped ?? (_) {}),
    );
    await tester.pumpAndSettle();
  }

  Widget buildScreen({
    required DrawingRepository repository,
    int childId = 7,
    PhotoPickerAdapter? photoPickerAdapter,
    PhotoPermissionService? photoPermissionService,
    PhotoDimensionReader? dimensionReader,
    int? htpAssessmentId,
    int? existingDrawingSessionId,
    DrawingActivityContextDto? restoredActivityContext,
    bool htpPhotoUploadEnabled = true,
  }) => InputMethodSelectScreen(
    childId: childId,
    drawingTypeId: 5,
    title: '그림일기',
    description: '오늘 있었던 일을 그림으로 그려 볼까?',
    icon: Icons.menu_book_rounded,
    accentColor: Colors.orange,
    repository: repository,
    htpAssessmentId: htpAssessmentId,
    existingDrawingSessionId: existingDrawingSessionId,
    restoredActivityContext: restoredActivityContext,
    // 기존 테스트는 대부분 사진 흐름을 검증하므로 기본으로 켜두고,
    // 기본값(꺼짐) 자체를 확인하는 테스트만 명시적으로 false를 넘긴다.
    htpPhotoUploadEnabled: htpPhotoUploadEnabled,
    photoPickerAdapter: photoPickerAdapter ?? _FakePhotoPickerAdapter(),
    photoPermissionService: photoPermissionService,
    // 320~8192px 검증 범위 안의 값으로 기본값을 잡아, 크기 자체를 검증하는
    // 테스트가 아닌 한 통과하게 한다.
    dimensionReader: dimensionReader ?? ((_) async => (400, 400)),
    now: () => DateTime.utc(2026, 7, 29, 1),
  );

  Future<void> goToPhotoSource(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('input-method-photo')));
    await tester.pumpAndSettle();
  }

  group('캔버스 선택', () {
    testWidgets('캔버스를 고르면 inputMethod CANVAS로 세션을 만들고 결과를 pop한다', (
      tester,
    ) async {
      final repository = _FakeDrawingRepository();
      DrawingSessionResolution? popped;

      await pumpScreen(
        tester,
        buildScreen(repository: repository),
        onPopped: (value) => popped = value,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.startHtpRequest?.inputMethod, 'CANVAS');
      expect(repository.startHtpRequest?.childId, 7);
      expect(popped?.sessionId, 900);
      expect(repository.uploadCalls, 0);
    });

    testWidgets('캔버스 생성 실패 시 오류를 보여주고 재시도하면 성공한다', (tester) async {
      final repository = _FakeDrawingRepository(createFailures: [true, false]);
      DrawingSessionResolution? popped;

      await pumpScreen(
        tester,
        buildScreen(repository: repository),
        onPopped: (value) => popped = value,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('input-method-canvas-error')),
        findsOneWidget,
      );
      expect(repository.createCalls, 1);

      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, 2);
      expect(popped?.sessionId, 900);
    });
  });

  group('capability flag (HTP_PHOTO_UPLOAD_ENABLED)', () {
    testWidgets('꺼져 있으면 사진 경로로 들어갈 수 없고 업로드·세션 생성이 0회다', (tester) async {
      final adapter = _FakePhotoPickerAdapter();
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(
          repository: repository,
          photoPickerAdapter: adapter,
          htpPhotoUploadEnabled: false,
        ),
      );

      // 카드 자체는 안내를 위해 남지만 비활성 상태다.
      expect(find.byKey(const ValueKey('input-method-photo')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('input-method-photo')));
      await tester.pumpAndSettle();

      // 사진 선택 단계로 넘어가지 않는다.
      expect(find.byKey(const ValueKey('input-method-camera')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-gallery')), findsNothing);
      expect(adapter.cameraCalls, 0);
      expect(adapter.galleryCalls, 0);
      expect(repository.uploadCalls, 0);
      expect(repository.createCalls, 0);
    });

    testWidgets('꺼져 있어도 캔버스 흐름은 그대로 동작한다', (tester) async {
      final repository = _FakeDrawingRepository();
      DrawingSessionResolution? popped;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, htpPhotoUploadEnabled: false),
        onPopped: (value) => popped = value,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pumpAndSettle();

      expect(repository.startHtpRequest?.inputMethod, 'CANVAS');
      expect(popped?.sessionId, 900);
      expect(repository.uploadCalls, 0);
    });

    testWidgets('켜져 있으면 사진 선택 흐름에 접근할 수 있다', (tester) async {
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, htpPhotoUploadEnabled: true),
      );
      await tester.tap(find.byKey(const ValueKey('input-method-photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-gallery')),
        findsOneWidget,
      );
    });
  });

  group('주제 전환 Idempotency-Key', () {
    testWidgets('같은 방식으로 재시도하면 steps/next에 같은 Key를 보낸다', (tester) async {
      final repository = _FakeDrawingRepository()
        ..nextStepFailures = const [true, false];

      await pumpScreen(
        tester,
        buildScreen(repository: repository, htpAssessmentId: 91),
      );

      // 1차 시도 — 실패.
      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pumpAndSettle();
      expect(repository.nextStepCalls, 1);
      expect(
        find.byKey(const ValueKey('input-method-canvas-error')),
        findsOneWidget,
      );

      // 같은 방식으로 재시도 — 같은 논리 요청이므로 Key를 재사용한다.
      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pumpAndSettle();

      expect(repository.nextStepCalls, 2);
      expect(repository.nextStepKeys.first, repository.nextStepKeys.last);
      expect(repository.nextStepInputMethods, ['CANVAS', 'CANVAS']);
      // 전환에서는 새 HTP 활동을 만들지 않는다.
      expect(repository.createCalls, 0);
    });

    testWidgets('같은 inputMethod여도 다른 assessment는 새 Key를 쓰고 느린 성공을 버린다', (
      tester,
    ) async {
      final nextA = Completer<HtpAssessmentDto>();
      final nextB = Completer<HtpAssessmentDto>();
      final repository = _FakeDrawingRepository(
        nextStepCompleters: [nextA, nextB],
      );
      var assessmentId = 91;
      late StateSetter updateIdentity;
      var popCount = 0;

      await pumpScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            updateIdentity = setState;
            return buildScreen(
              repository: repository,
              htpAssessmentId: assessmentId,
            );
          },
        ),
        onPopped: (_) => popCount += 1,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pump();
      expect(repository.nextStepCalls, 1);

      updateIdentity(() => assessmentId = 92);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pump();

      expect(repository.nextStepCalls, 2);
      expect(repository.nextStepAssessmentIds, [91, 92]);
      expect(repository.nextStepInputMethods, ['CANVAS', 'CANVAS']);
      expect(repository.nextStepKeys, hasLength(2));
      expect(repository.nextStepKeys.toSet(), hasLength(2));

      nextA.complete(
        repository.nextStepAssessment(assessmentId: 91, sessionId: 901),
      );
      await tester.pump();
      await tester.pump();

      expect(popCount, 0);
      expect(find.byKey(const ValueKey('input-method-canvas')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-canvas-error')),
        findsNothing,
      );

      nextB.complete(
        repository.nextStepAssessment(assessmentId: 92, sessionId: 902),
      );
      await tester.pumpAndSettle();

      expect(popCount, 1);
      expect(repository.nextStepCalls, 2);
    });

    testWidgets('같은 assessment여도 다른 HTP stage는 새 Key를 쓰고 느린 실패를 버린다', (
      tester,
    ) async {
      final nextA = Completer<HtpAssessmentDto>();
      final nextB = Completer<HtpAssessmentDto>();
      final repository = _FakeDrawingRepository(
        nextStepCompleters: [nextA, nextB],
      );
      var stepOrder = 1;
      var drawingSubject = 'HOUSE';
      late StateSetter updateIdentity;
      var popCount = 0;

      await pumpScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            updateIdentity = setState;
            return buildScreen(
              repository: repository,
              htpAssessmentId: 91,
              restoredActivityContext: DrawingActivityContextDto(
                activityKind: 'HTP',
                htpAssessmentId: 91,
                htpStatus: 'IN_PROGRESS',
                stepOrder: stepOrder,
                drawingSubject: drawingSubject,
              ),
            );
          },
        ),
        onPopped: (_) => popCount += 1,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pump();
      expect(repository.nextStepCalls, 1);

      updateIdentity(() {
        stepOrder = 2;
        drawingSubject = 'TREE';
      });
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pump();

      expect(repository.nextStepCalls, 2);
      expect(repository.nextStepAssessmentIds, [91, 91]);
      expect(repository.nextStepInputMethods, ['CANVAS', 'CANVAS']);
      expect(repository.nextStepKeys, hasLength(2));
      expect(repository.nextStepKeys.toSet(), hasLength(2));

      nextA.completeError(
        const ApiTransportFailure(type: ApiTransportFailureType.connection),
      );
      await tester.pump();
      await tester.pump();

      expect(popCount, 0);
      expect(find.byKey(const ValueKey('input-method-canvas')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-canvas-error')),
        findsNothing,
      );

      nextB.complete(
        repository.nextStepAssessment(assessmentId: 91, sessionId: 902),
      );
      await tester.pumpAndSettle();

      expect(popCount, 1);
      expect(repository.nextStepCalls, 2);
    });

    testWidgets('입력 방식을 바꾸면 새 Key를 쓴다', (tester) async {
      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final repository = _FakeDrawingRepository()
        ..nextStepFailures = const [true];
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);

      await pumpScreen(
        tester,
        buildScreen(
          repository: repository,
          photoPickerAdapter: adapter,
          htpAssessmentId: 91,
        ),
      );

      // CANVAS로 시도했다가 실패.
      await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
      await tester.pumpAndSettle();
      expect(repository.nextStepInputMethods, ['CANVAS']);

      // 방식을 UPLOAD로 바꿔 진행하면 다른 논리 요청이므로 새 Key여야 한다.
      await tester.tap(find.byKey(const ValueKey('input-method-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.nextStepInputMethods, ['CANVAS', 'UPLOAD']);
      expect(
        repository.nextStepKeys.first,
        isNot(repository.nextStepKeys.last),
      );
    });

    testWidgets('업로드 재시도는 같은 업로드·완료 Key를 재사용한다', (tester) async {
      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final repository = _FakeDrawingRepository(
        uploadFailures: [
          const ApiTransportFailure(type: ApiTransportFailureType.connection),
          null,
        ],
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo, photo]);

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await tester.tap(find.byKey(const ValueKey('input-method-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.uploadCalls, 2);
      // 같은 사진 재시도는 같은 Key로 나가야 서버가 중복 저장하지 않는다.
      expect(repository.uploadKeys.first, repository.uploadKeys.last);
      // 세션도 한 번만 만든다.
      expect(repository.createCalls, 1);
    });
  });

  group('취소', () {
    testWidgets('입력 방식 화면에서 바로 취소하면 세션을 만들지 않고 null을 pop한다', (tester) async {
      final repository = _FakeDrawingRepository();
      var poppedCalled = false;
      DrawingSessionResolution? popped;

      await pumpScreen(
        tester,
        buildScreen(repository: repository),
        onPopped: (value) {
          popped = value;
          poppedCalled = true;
        },
      );

      await tester.tap(find.byKey(const ValueKey('input-method-cancel')));
      await tester.pumpAndSettle();

      expect(poppedCalled, isTrue);
      expect(popped, isNull);
      expect(repository.createCalls, 0);
    });
  });

  group('사진 선택 — 카메라·앨범 위임 및 picker 취소', () {
    testWidgets('카메라로 촬영하면 시스템 카메라 위임 어댑터가 호출되고 미리보기로 넘어간다', (tester) async {
      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final adapter = _FakePhotoPickerAdapter(cameraResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);

      await tester.tap(find.byKey(const ValueKey('input-method-camera')));
      await tester.pumpAndSettle();

      expect(adapter.cameraCalls, 1);
      expect(adapter.galleryCalls, 0);
      expect(
        find.byKey(const ValueKey('input-method-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('앨범에서 고르면 시스템 Photo Picker 어댑터가 호출되고 미리보기로 넘어간다', (
      tester,
    ) async {
      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);

      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      expect(adapter.galleryCalls, 1);
      expect(
        find.byKey(const ValueKey('input-method-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('picker를 취소하면 오류 없이 사진 선택 화면에 그대로 남는다', (tester) async {
      final adapter = _FakePhotoPickerAdapter(
        cameraResults: [null],
        galleryResults: [null],
      );
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);

      await tester.tap(find.byKey(const ValueKey('input-method-camera')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-photo-error')),
        findsNothing,
      );
      expect(repository.createCalls, 0);

      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('input-method-photo-error')),
        findsNothing,
      );
      expect(repository.createCalls, 0);
    });

    testWidgets('카메라 권한이 거부되면 기기 설정 이동 안내를 표시한다', (tester) async {
      const permissionChannel = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      final permissionCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (call) async {
            permissionCalls.add(call.method);
            return switch (call.method) {
              'checkPermissionStatus' => 4,
              'openAppSettings' => true,
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(permissionChannel, null),
      );
      final adapter = _FakePhotoPickerAdapter(
        cameraError: PlatformException(
          code: 'camera_access_denied',
          message: 'The user did not allow camera access.',
        ),
      );
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);

      await tester.tap(find.byKey(const ValueKey('input-method-camera')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('input-method-permission-error')),
        findsOneWidget,
      );
      expect(find.text('기기 설정에서 카메라 권한을 허용해 주세요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-open-settings')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('input-method-open-settings')),
      );
      await tester.pump();
      expect(permissionCalls, contains('checkPermissionStatus'));
      expect(permissionCalls, contains('openAppSettings'));
      expect(repository.createCalls, 0);
    });

    testWidgets('앨범 접근이 제한되면 사진 권한 설정 이동 안내를 표시한다', (tester) async {
      const permissionChannel = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (call) async {
            return switch (call.method) {
              'checkPermissionStatus' => 4,
              'openAppSettings' => true,
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(permissionChannel, null),
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryError: PlatformException(
          code: 'photo_access_restricted',
          message: 'The user cannot allow photo access.',
        ),
      );
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);

      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      expect(find.text('기기 설정에서 사진 권한을 허용해 주세요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-open-settings')),
        findsOneWidget,
      );
      expect(repository.createCalls, 0);
    });

    testWidgets('기기 설정 화면을 열지 못하면 직접 설정 안내를 표시한다', (tester) async {
      final adapter = _FakePhotoPickerAdapter(
        cameraError: PlatformException(code: 'camera_access_denied'),
      );
      final permissionService = _FakePhotoPermissionService(
        permissionStatus: PhotoPermissionStatus.permanentlyDenied,
        openSettingsResult: false,
      );

      await pumpScreen(
        tester,
        buildScreen(
          repository: _FakeDrawingRepository(),
          photoPickerAdapter: adapter,
          photoPermissionService: permissionService,
        ),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-camera')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('input-method-open-settings')),
      );
      await tester.pumpAndSettle();

      expect(permissionService.openSettingsCalls, 1);
      expect(
        find.text('설정 화면을 열지 못했어요. 기기 설정에서 직접 카메라 권한을 허용해 주세요.'),
        findsOneWidget,
      );
    });

    testWidgets('권한 설정의 느린 false는 다른 route identity에 오류를 표시하지 않는다', (
      tester,
    ) async {
      final settings = Completer<bool>();
      final adapter = _FakePhotoPickerAdapter(
        cameraError: PlatformException(code: 'camera_access_denied'),
      );
      final permissionService = _FakePhotoPermissionService(
        permissionStatus: PhotoPermissionStatus.permanentlyDenied,
        openSettingsCompleter: settings,
      );
      var childId = 7;
      late StateSetter updateIdentity;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateIdentity = setState;
              return buildScreen(
                repository: _FakeDrawingRepository(),
                photoPickerAdapter: adapter,
                photoPermissionService: permissionService,
                childId: childId,
              );
            },
          ),
        ),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-camera')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('input-method-open-settings')),
      );
      await tester.pump();

      expect(permissionService.openSettingsCalls, 1);
      updateIdentity(() => childId = 8);
      await tester.pump();
      expect(find.byKey(const ValueKey('input-method-photo')), findsOneWidget);

      settings.complete(false);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('설정 화면을 열지 못했어요. 기기 설정에서 직접 카메라 권한을 허용해 주세요.'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('input-method-photo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('기기 정책으로 제한된 사진 권한에는 설정 이동을 제공하지 않는다', (tester) async {
      const permissionChannel = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (call) async {
            return call.method == 'checkPermissionStatus' ? 2 : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(permissionChannel, null),
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryError: PlatformException(code: 'photo_access_restricted'),
      );

      await pumpScreen(
        tester,
        buildScreen(
          repository: _FakeDrawingRepository(),
          photoPickerAdapter: adapter,
        ),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      expect(find.text('사진 사용이 기기 설정 또는 보호자 정책으로 제한되어 있어요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-open-settings')),
        findsNothing,
      );
    });
  });

  group('형식·크기·해상도 검증', () {
    testWidgets('지원하지 않는 형식은 차단하고 오류 배너를 보여준다', (tester) async {
      final photo = PickedPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'photo.gif',
        mimeType: 'image/gif',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('input-method-photo-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('input-method-confirm')), findsNothing);
    });

    testWidgets('10MiB를 넘는 사진은 차단한다', (tester) async {
      final photo = PickedPhoto(
        bytes: Uint8List(kMaxPhotoUploadBytes + 1),
        fileName: 'huge.jpg',
        mimeType: 'image/jpeg',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('input-method-photo-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('input-method-confirm')), findsNothing);
    });

    testWidgets('디코딩할 수 없는 사진(잘못된 차원 포함)은 차단한다', (tester) async {
      final photo = PickedPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'broken.png',
        mimeType: 'image/png',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(
          repository: repository,
          photoPickerAdapter: adapter,
          dimensionReader: (_) async => throw const FormatException('bad'),
        ),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('input-method-photo-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('input-method-confirm')), findsNothing);
    });
  });

  group('미리보기 — 다시 선택·취소', () {
    Future<void> pickValidPhoto(WidgetTester tester) async {
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
    }

    testWidgets('다시 선택을 누르면 사진 선택 화면으로 돌아간다', (tester) async {
      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await pickValidPhoto(tester);
      expect(
        find.byKey(const ValueKey('input-method-confirm')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
      expect(repository.createCalls, 0);
    });

    testWidgets('사진을 확보하기 전에는 세션을 만들지 않는다', (tester) async {
      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await pickValidPhoto(tester);

      expect(repository.createCalls, 0);
      expect(repository.uploadCalls, 0);
    });

    testWidgets('업로드 세션을 만든 뒤 취소하면 세션을 정리하고 null을 pop한다', (tester) async {
      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(
        uploadFailures: [
          const ApiTransportFailure(type: ApiTransportFailureType.connection),
        ],
      );
      DrawingSessionResolution? popped;
      var poppedCalled = false;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (value) {
          popped = value;
          poppedCalled = true;
        },
      );
      await pickValidPhoto(tester);

      // 업로드가 실패해도 세션 자체는 이미 만들어졌다 — 취소 시 정리 대상이 된다.
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      expect(repository.createCalls, 1);

      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedSessionIds, [900]);
      expect(poppedCalled, isTrue);
      expect(popped, isNull);
    });
  });

  group('업로드 성공·실패·재시도', () {
    Future<PickedPhoto> validPhoto() async => PickedPhoto(
      bytes: _tinyPngBytes,
      fileName: 'photo.png',
      mimeType: 'image/png',
    );

    testWidgets('사진 전송이 시작되면 실제 진행률을 기다리는 0% 상태를 표시한다', (tester) async {
      final photo = await validPhoto();
      final uploadGate = Completer<void>();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(uploadGate: uploadGate);

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      for (
        var attempt = 0;
        attempt < 5 && repository.uploadCalls == 0;
        attempt++
      ) {
        await tester.pump();
      }
      await tester.pump();

      expect(repository.uploadCalls, 1);
      expect(
        find.byKey(const ValueKey('input-method-upload-progress')),
        findsOneWidget,
      );
      expect(find.text('사진을 올리고 있어요 0%'), findsOneWidget);

      uploadGate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('전송 100% 뒤 서버 응답을 기다리는 상태를 구분해 표시한다', (tester) async {
      final photo = await validPhoto();
      final uploadGate = Completer<void>();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(
        uploadGate: uploadGate,
        uploadProgressEvents: const [(100, 100)],
      );

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      for (
        var attempt = 0;
        attempt < 5 && repository.uploadCalls == 0;
        attempt++
      ) {
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('업로드 100% · 사진을 확인하고 있어요'), findsOneWidget);

      uploadGate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('전송 callback의 실제 바이트 진행률을 백분율로 표시한다', (tester) async {
      final photo = await validPhoto();
      final uploadGate = Completer<void>();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(
        uploadGate: uploadGate,
        uploadProgressEvents: const [(42, 100)],
      );

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      for (
        var attempt = 0;
        attempt < 5 && repository.uploadCalls == 0;
        attempt++
      ) {
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('사진을 올리고 있어요 42%'), findsOneWidget);
      expect(find.bySemanticsLabel('사진 업로드 42퍼센트'), findsOneWidget);

      uploadGate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('업로드에 성공하면 inputMethod UPLOAD 세션을 만들고 최신 세션 상태로 pop한다', (
      tester,
    ) async {
      final photo = await validPhoto();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(
        getSessionCurrentStage: 'CONVERSING',
      );
      DrawingSessionResolution? popped;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (value) => popped = value,
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.startHtpRequest?.inputMethod, 'UPLOAD');
      expect(repository.uploadCalls, 1);
      expect(repository.getSessionCalls, 0);
      expect(popped?.sessionId, 900);
      expect(popped?.currentStage, 'CONVERSING');
      expect(popped?.isDrawingStage, isFalse);
    });

    for (final stage in const [(1, 'HOUSE'), (2, 'TREE'), (3, 'PERSON')]) {
      testWidgets('HTP ${stage.$2} 기존 세션은 identity를 보존해 업로드·완료한다', (
        tester,
      ) async {
        final photo = await validPhoto();
        final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
        final repository = _FakeDrawingRepository(
          getSessionCurrentStage: 'CONVERSING',
        );
        DrawingSessionResolution? popped;

        await pumpScreen(
          tester,
          buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
            existingDrawingSessionId: 900 + stage.$1,
            restoredActivityContext: DrawingActivityContextDto(
              activityKind: 'HTP',
              htpAssessmentId: 91,
              htpStatus: 'IN_PROGRESS',
              stepOrder: stage.$1,
              drawingSubject: stage.$2,
            ),
          ),
          onPopped: (value) => popped = value,
        );
        await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
        await tester.pumpAndSettle();

        expect(repository.createCalls, 0);
        expect(repository.uploadSessionIds, [900 + stage.$1]);
        expect(repository.completionKeys, hasLength(1));
        expect(popped, isNotNull);
        final activityContext = popped?.activityContext;
        expect(activityContext, isNotNull);
        expect(activityContext?.drawingSubject, stage.$2);
        expect(activityContext?.stepOrder, stage.$1);
      });
    }

    testWidgets('연속으로 두 번 탭해도 세션 생성과 업로드는 한 번만 일어난다', (tester) async {
      final photo = await validPhoto();
      final uploadGate = Completer<void>();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(uploadGate: uploadGate);

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pump();

      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 1);

      uploadGate.complete();
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 1);
      expect(repository.completionKeys, hasLength(1));
    });

    for (final testCase in [('STORAGE_422_001', '크기가 적절하지')]) {
      testWidgets('실제 422 서버 오류 ${testCase.$1}는 안내 후 재시도를 차단한다', (
        tester,
      ) async {
        final photo = await validPhoto();
        final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
        final failure = ApiResponseFailure(
          statusCode: 422,
          error: ApiError(code: testCase.$1, message: '검증 실패'),
        );
        final repository = _FakeDrawingRepository(uploadFailures: [failure]);
        DrawingSessionResolution? popped;

        await pumpScreen(
          tester,
          buildScreen(repository: repository, photoPickerAdapter: adapter),
          onPopped: (value) => popped = value,
        );
        await goToPhotoSource(tester);
        await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('input-method-upload-error')),
          findsOneWidget,
        );
        expect(find.textContaining(testCase.$2), findsOneWidget);
        expect(repository.createCalls, 1);
        expect(repository.uploadCalls, 1);
        expect(
          find.byKey(const ValueKey('input-method-confirm')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('input-method-reselect')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('input-method-preview-cancel')),
          findsOneWidget,
        );
        expect(popped, isNull);
      });
    }

    testWidgets('네트워크 오류 뒤 재시도하면 같은 사진으로 성공한다', (tester) async {
      final photo = await validPhoto();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(
        uploadFailures: [
          const ApiTransportFailure(type: ApiTransportFailureType.connection),
        ],
      );
      DrawingSessionResolution? popped;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (value) => popped = value,
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('input-method-upload-error')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 2);
      expect(repository.uploadKeys.toSet(), hasLength(1));
      expect(
        repository.uploadImages[0].bytes,
        orderedEquals(repository.uploadImages[1].bytes),
      );
      expect(
        repository.uploadMetadata[0].toJson(),
        repository.uploadMetadata[1].toJson(),
      );
      expect(popped?.sessionId, 900);
    });

    testWidgets('completion 5xx 재시도도 동일 upload·completion snapshot을 재사용한다', (
      tester,
    ) async {
      final photo = await validPhoto();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository(
        completionFailures: [
          const ApiResponseFailure(
            statusCode: 503,
            error: ApiError(code: 'COMMON_503', message: 'temporary'),
          ),
        ],
      );

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('다시 시도'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.uploadCalls, 2);
      expect(repository.completionKeys, hasLength(2));
      expect(repository.uploadKeys.toSet(), hasLength(1));
      expect(repository.completionKeys.toSet(), hasLength(1));
      expect(
        repository.uploadMetadata[0].toJson(),
        repository.uploadMetadata[1].toJson(),
      );
      expect(
        repository.completionMetadata[0].toJson(),
        repository.completionMetadata[1].toJson(),
      );
    });
  });

  group('업로드 오류 재시도 정책', () {
    test('network·timeout·unknown·5xx만 upload 재시도를 허용한다', () {
      for (final type in [
        ApiTransportFailureType.connection,
        ApiTransportFailureType.connectionTimeout,
        ApiTransportFailureType.sendTimeout,
        ApiTransportFailureType.receiveTimeout,
        ApiTransportFailureType.transformTimeout,
        ApiTransportFailureType.unknown,
      ]) {
        expect(
          DrawingUploadErrorPresentation.of(
            ApiTransportFailure(type: type),
          ).canRetry,
          isTrue,
          reason: '$type',
        );
      }
      expect(
        DrawingUploadErrorPresentation.of(
          const ApiResponseFailure(
            statusCode: 500,
            error: ApiError(code: 'DRAWING_UPLOAD_FAILED', message: 'failed'),
          ),
        ).canRetry,
        isTrue,
      );
    });

    test('cancelled와 400·401·403·404·409·422는 upload 재시도를 차단한다', () {
      expect(
        DrawingUploadErrorPresentation.of(
          const ApiTransportFailure(type: ApiTransportFailureType.cancelled),
        ).canRetry,
        isFalse,
      );
      for (final status in [400, 401, 403, 404, 409, 422]) {
        expect(
          DrawingUploadErrorPresentation.of(
            ApiResponseFailure(
              statusCode: status,
              error: const ApiError(code: 'DRAWING_ERROR', message: 'failed'),
            ),
          ).canRetry,
          isFalse,
          reason: '$status',
        );
      }
    });

    test('처리 중 409는 completion의 DRAWING_409_017에만 재시도를 허용한다', () {
      const processing = ApiResponseFailure(
        statusCode: 409,
        error: ApiError(code: 'DRAWING_409_017', message: 'processing'),
      );
      expect(DrawingUploadErrorPresentation.of(processing).canRetry, isFalse);
      expect(
        DrawingUploadErrorPresentation.of(
          processing,
          endpoint: DrawingUploadEndpoint.completion,
        ).canRetry,
        isTrue,
      );
      expect(
        DrawingUploadErrorPresentation.of(
          const ApiResponseFailure(
            statusCode: 409,
            error: ApiError(
              code: 'DRAWING_UPLOAD_IDEMPOTENCY_CONFLICT',
              message: 'conflict',
            ),
          ),
          endpoint: DrawingUploadEndpoint.completion,
        ).canRetry,
        isFalse,
      );
    });
  });

  group('실제 취소·generation·stale 응답', () {
    Future<void> waitForUpload(
      WidgetTester tester,
      _FakeDrawingRepository repository,
      int calls,
    ) async {
      for (
        var attempt = 0;
        attempt < 10 && repository.uploadCalls < calls;
        attempt++
      ) {
        await tester.pump();
      }
      expect(repository.uploadCalls, calls);
      await tester.pump();
    }

    Future<void> selectGalleryPhoto(WidgetTester tester) async {
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
    }

    testWidgets('업로드 취소는 전송만 1회 취소하고 늦은 성공에도 completion을 시작하지 않는다', (
      tester,
    ) async {
      final upload = Completer<DrawingUploadResponseDto>();
      final repository = _FakeDrawingRepository(uploadCompleters: [upload]);
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'first.png',
            mimeType: 'image/png',
          ),
        ],
      );

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 1);

      final cancel = find.byKey(const ValueKey('input-method-preview-cancel'));
      expect(find.bySemanticsLabel('업로드 취소'), findsWidgets);
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(cancel).width, greaterThanOrEqualTo(48));
      await tester.tap(cancel);
      await tester.pump();

      expect(repository.cancellationSignals, 1);
      expect(repository.completionKeys, isEmpty);
      expect(
        find.byKey(const ValueKey('input-method-upload-error')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('input-method-confirm')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('업로드 취소 중'), findsWidgets);
      expect(find.bySemanticsLabel('이 사진 사용하기 처리 중'), findsWidgets);

      upload.complete(repository._uploadResponse(900, 1));
      await tester.pump();
      await tester.pump();

      expect(repository.completionKeys, isEmpty);
      expect(
        find.byKey(const ValueKey('input-method-confirm')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('이 사진 사용하기'), findsWidgets);
    });

    testWidgets('A 취소 settlement 전 재선택·B 전송을 막고 정리 후 B만 완료한다', (tester) async {
      final uploadA = Completer<DrawingUploadResponseDto>();
      final uploadB = Completer<DrawingUploadResponseDto>();
      final repository = _FakeDrawingRepository(
        uploadCompleters: [uploadA, uploadB],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'a.png',
            mimeType: 'image/png',
          ),
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'b.png',
            mimeType: 'image/png',
          ),
        ],
      );

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 1);
      repository.emitUploadProgress(0, 42, 100);
      await tester.pump();
      expect(find.text('사진을 올리고 있어요 42%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.pump();
      expect(repository.cancellationSignals, 0);
      expect(find.byKey(const ValueKey('input-method-gallery')), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.pump();
      expect(repository.cancellationSignals, 1);
      repository.emitUploadProgress(0, 99, 100);
      await tester.pump();
      expect(find.textContaining('99%'), findsNothing);

      uploadA.complete(repository._uploadResponse(900, 1));
      await tester.pump();
      await tester.pump();
      expect(repository.completionKeys, isEmpty);

      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 2);

      uploadB.complete(repository._uploadResponse(900, 2));
      await tester.pumpAndSettle();

      expect(repository.completionKeys, hasLength(1));
      expect(repository.completionMetadata.single.sourceAssetId, 2);
      expect(repository.uploadImages.map((image) => image.fileName), [
        'a.png',
        'b.png',
      ]);
      expect(repository.uploadKeys.toSet(), hasLength(2));
    });

    testWidgets('취소된 A의 늦은 실패가 정리된 뒤 B 오류 상태를 덮지 않는다', (tester) async {
      final uploadA = Completer<DrawingUploadResponseDto>();
      final uploadB = Completer<DrawingUploadResponseDto>();
      final repository = _FakeDrawingRepository(
        uploadCompleters: [uploadA, uploadB],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'a.png',
            mimeType: 'image/png',
          ),
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'b.png',
            mimeType: 'image/png',
          ),
        ],
      );

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 1);
      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.pump();
      uploadA.completeError(
        const ApiTransportFailure(type: ApiTransportFailureType.connection),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 2);
      expect(
        find.byKey(const ValueKey('input-method-upload-error')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('업로드 취소'), findsWidgets);

      uploadB.complete(repository._uploadResponse(900, 2));
      await tester.pumpAndSettle();
      expect(repository.completionKeys, hasLength(1));
    });

    testWidgets('completion settlement 동안 재시도·재선택을 막고 back 결과를 한 번만 반환한다', (
      tester,
    ) async {
      final completion = Completer<DrawingStageCompleteResponseDto>();
      final repository = _FakeDrawingRepository(
        completionCompleters: [completion],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;
      DrawingSessionResolution? popped;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (value) {
          popCount += 1;
          popped = value;
        },
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      for (
        var attempt = 0;
        attempt < 10 && repository.completionKeys.isEmpty;
        attempt++
      ) {
        await tester.pump();
      }
      await tester.pump();

      expect(repository.uploadCalls, 1);
      expect(repository.completionKeys, hasLength(1));
      expect(find.text('완료 처리 중이에요'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.pump();
      expect(repository.uploadCalls, 1);
      expect(repository.completionKeys, hasLength(1));

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(popCount, 0);
      expect(repository.deletedSessionIds, isEmpty);

      completion.complete(repository.completionResponse(900, 1));
      await tester.pumpAndSettle();

      expect(popCount, 1);
      expect(popped?.sessionId, 900);
      expect(popped?.currentStage, 'CONVERSING');
      expect(repository.uploadCalls, 1);
      expect(repository.completionKeys, hasLength(1));
    });

    testWidgets('completion 늦은 실패 전에는 중복 요청이 없고 settlement 뒤 같은 Key로 재시도한다', (
      tester,
    ) async {
      final completion = Completer<DrawingStageCompleteResponseDto>();
      final repository = _FakeDrawingRepository(
        completionCompleters: [completion],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (_) => popCount += 1,
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      for (
        var attempt = 0;
        attempt < 10 && repository.completionKeys.isEmpty;
        attempt++
      ) {
        await tester.pump();
      }
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.pump();
      expect(repository.uploadCalls, 1);
      expect(repository.completionKeys, hasLength(1));
      expect(popCount, 0);

      completion.completeError(
        const ApiTransportFailure(type: ApiTransportFailureType.connection),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('input-method-upload-error')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('다시 시도'), findsWidgets);
      expect(popCount, 0);

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.uploadCalls, 2);
      expect(repository.completionKeys, hasLength(2));
      expect(repository.uploadKeys.toSet(), hasLength(1));
      expect(repository.completionKeys.toSet(), hasLength(1));
      expect(popCount, 1);
    });

    testWidgets('completion pending 중 dispose되면 늦은 성공이 navigation을 만들지 않는다', (
      tester,
    ) async {
      final completion = Completer<DrawingStageCompleteResponseDto>();
      final repository = _FakeDrawingRepository(
        completionCompleters: [completion],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (_) => popCount += 1,
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      for (
        var attempt = 0;
        attempt < 10 && repository.completionKeys.isEmpty;
        attempt++
      ) {
        await tester.pump();
      }
      expect(repository.completionKeys, hasLength(1));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      completion.complete(repository.completionResponse(900, 1));
      await tester.pump();
      await tester.pump();

      expect(popCount, 0);
      expect(repository.completionKeys, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'completion pending 중 route identity 변경도 settlement 전 새 시작을 막는다',
      (tester) async {
        final completion = Completer<DrawingStageCompleteResponseDto>();
        final repository = _FakeDrawingRepository(
          completionCompleters: [completion],
        );
        final adapter = _FakePhotoPickerAdapter(
          galleryResults: [
            PickedPhoto(
              bytes: _tinyPngBytes,
              fileName: 'stage-a.png',
              mimeType: 'image/png',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: buildScreen(
              repository: repository,
              photoPickerAdapter: adapter,
            ),
          ),
        );
        await goToPhotoSource(tester);
        await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
        for (
          var attempt = 0;
          attempt < 10 && repository.completionKeys.isEmpty;
          attempt++
        ) {
          await tester.pump();
        }

        await tester.pumpWidget(
          MaterialApp(
            home: buildScreen(
              repository: repository,
              photoPickerAdapter: adapter,
              childId: 8,
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('input-method-photo')));
        await tester.tap(find.byKey(const ValueKey('input-method-canvas')));
        await tester.pump();

        expect(repository.createCalls, 1);
        expect(repository.uploadCalls, 1);
        expect(repository.completionKeys, hasLength(1));
        expect(
          find.byKey(const ValueKey('input-method-gallery')),
          findsNothing,
        );

        completion.complete(repository.completionResponse(900, 1));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('input-method-photo')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('input-method-gallery')),
          findsOneWidget,
        );
        expect(repository.completionKeys, hasLength(1));
      },
    );

    testWidgets('세션 생성 취소는 늦은 성공을 보존하고 다음 확인에서 같은 세션을 재사용한다', (tester) async {
      final creation = Completer<HtpAssessmentDto>();
      final repository = _FakeDrawingRepository(
        sessionCreationCompleters: [creation],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pump();

      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 0);
      expect(find.text('사진을 올릴 준비를 하고 있어요'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('준비 취소 중'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.pump();
      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 0);

      creation.complete(repository.createdAssessment());
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('이 사진 사용하기'), findsWidgets);
      expect(repository.uploadCalls, 0);

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.uploadSessionIds, [900]);
      expect(repository.completionKeys, hasLength(1));
    });

    testWidgets('다른 route identity의 늦은 세션 생성 결과가 현재 stage를 덮지 않는다', (
      tester,
    ) async {
      final creationA = Completer<HtpAssessmentDto>();
      final creationB = Completer<HtpAssessmentDto>();
      final repository = _FakeDrawingRepository(
        sessionCreationCompleters: [creationA, creationB],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'stage-a.png',
            mimeType: 'image/png',
          ),
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'stage-b.png',
            mimeType: 'image/png',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
          ),
        ),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pump();
      expect(repository.createCalls, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
            childId: 8,
          ),
        ),
      );
      await tester.pump();
      creationA.complete(repository.createdAssessment(sessionId: 900));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('input-method-photo')), findsOneWidget);
      expect(find.byKey(const ValueKey('input-method-confirm')), findsNothing);
      expect(repository.uploadCalls, 0);

      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pump();
      expect(repository.createCalls, 2);

      creationB.complete(repository.createdAssessment(sessionId: 901));
      await tester.pumpAndSettle();
      expect(repository.uploadSessionIds, [901]);
      expect(repository.uploadImages.single.fileName, 'stage-b.png');
    });

    testWidgets('세션 생성 중 leave는 늦게 생긴 세션 삭제까지 기다리고 한 번만 pop한다', (tester) async {
      final creation = Completer<HtpAssessmentDto>();
      final deletion = Completer<void>();
      final repository = _FakeDrawingRepository(
        sessionCreationCompleters: [creation],
        deleteGate: deletion,
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (_) => popCount += 1,
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pump();
      expect(repository.createCalls, 1);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(popCount, 0);

      creation.complete(repository.createdAssessment());
      await tester.pump();
      await tester.pump();
      expect(repository.deletedSessionIds, [900]);
      expect(popCount, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repository.createCalls, 1);
      expect(repository.deletedSessionIds, [900]);
      expect(popCount, 0);

      deletion.complete();
      await tester.pumpAndSettle();
      expect(popCount, 1);
      expect(repository.uploadCalls, 0);
    });

    testWidgets('delete settlement 동안 모든 진입을 막고 정리 뒤 한 번만 pop한다', (
      tester,
    ) async {
      final deletion = Completer<void>();
      final repository = _FakeDrawingRepository(
        uploadFailures: const [
          ApiTransportFailure(type: ApiTransportFailureType.connection),
        ],
        deleteGate: deletion,
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (_) => popCount += 1,
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 1);

      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.pump();
      expect(repository.deletedSessionIds, [900]);
      expect(popCount, 0);

      final confirmButton = tester.widget<FilledButton>(
        find
            .descendant(
              of: find.byKey(const ValueKey('input-method-confirm')),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(confirmButton.onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.tap(
        find.byKey(const ValueKey('input-method-preview-cancel')),
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 1);
      expect(repository.deletedSessionIds, [900]);
      expect(popCount, 0);

      deletion.complete();
      await tester.pumpAndSettle();
      expect(popCount, 1);
    });

    testWidgets('delete pending의 사진 선택 화면에서 camera·picker·back 실제 탭을 차단한다', (
      tester,
    ) async {
      final deletion = Completer<void>();
      final repository = _FakeDrawingRepository(
        uploadFailures: const [
          ApiTransportFailure(type: ApiTransportFailureType.connection),
        ],
        deleteGate: deletion,
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (_) => popCount += 1,
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('input-method-cancel')));
      await tester.pump();
      expect(repository.deletedSessionIds, [900]);
      expect(popCount, 0);

      await tester.tap(find.byKey(const ValueKey('input-method-camera')));
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.tap(find.byKey(const ValueKey('input-method-back')));
      await tester.tap(find.byKey(const ValueKey('input-method-cancel')));
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(adapter.cameraCalls, 0);
      expect(adapter.galleryCalls, 1);
      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 1);
      expect(repository.completionKeys, isEmpty);
      expect(repository.deletedSessionIds, [900]);
      expect(popCount, 0);

      deletion.complete();
      await tester.pumpAndSettle();
      expect(popCount, 1);
    });

    testWidgets('route identity가 바뀐 뒤 늦은 picker A 결과를 버리고 B만 업로드한다', (
      tester,
    ) async {
      final pickerA = Completer<PickedPhoto?>();
      final pickerB = Completer<PickedPhoto?>();
      final repository = _FakeDrawingRepository();
      final adapter = _FakePhotoPickerAdapter(
        galleryCompleters: [pickerA, pickerB],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
          ),
        ),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pump();
      expect(adapter.galleryCalls, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
            childId: 8,
          ),
        ),
      );
      await tester.pump();
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pump();
      expect(adapter.galleryCalls, 2);

      pickerA.complete(
        PickedPhoto(
          bytes: _tinyPngBytes,
          fileName: 'stale-a.png',
          mimeType: 'image/png',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('input-method-confirm')), findsNothing);

      pickerB.complete(
        PickedPhoto(
          bytes: _tinyPngBytes,
          fileName: 'current-b.png',
          mimeType: 'image/png',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('input-method-confirm')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      expect(repository.uploadImages.single.fileName, 'current-b.png');
    });

    testWidgets('route identity 변경 뒤 picker A 늦은 실패가 현재 오류·step을 덮지 않는다', (
      tester,
    ) async {
      final pickerA = Completer<PickedPhoto?>();
      final repository = _FakeDrawingRepository();
      final adapter = _FakePhotoPickerAdapter(
        galleryCompleters: [pickerA],
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'current-b.png',
            mimeType: 'image/png',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
          ),
        ),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
            childId: 8,
          ),
        ),
      );
      await tester.pump();
      pickerA.completeError(StateError('stale picker failure'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('input-method-photo')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('input-method-photo-error')),
        findsNothing,
      );

      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(repository.uploadImages.single.fileName, 'current-b.png');
      expect(repository.createCalls, 1);
    });

    testWidgets('dispose는 업로드를 취소하고 늦은 성공의 API·navigation을 차단한다', (
      tester,
    ) async {
      final upload = Completer<DrawingUploadResponseDto>();
      final repository = _FakeDrawingRepository(uploadCompleters: [upload]);
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (_) => popCount += 1,
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 1);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(repository.cancellationSignals, 1);

      upload.complete(repository._uploadResponse(900, 1));
      await tester.pump();
      await tester.pump();
      expect(repository.completionKeys, isEmpty);
      expect(popCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('시스템 back은 업로드를 취소하고 늦은 완료에도 한 번만 pop한다', (tester) async {
      final upload = Completer<DrawingUploadResponseDto>();
      final repository = _FakeDrawingRepository(uploadCompleters: [upload]);
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      var popCount = 0;

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
        onPopped: (_) => popCount += 1,
      );
      await selectGalleryPhoto(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 1);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(repository.cancellationSignals, 1);
      expect(repository.completionKeys, isEmpty);
      expect(popCount, 1);

      upload.complete(repository._uploadResponse(900, 1));
      await tester.pump();
      await tester.pump();
      expect(repository.completionKeys, isEmpty);
      expect(popCount, 1);
    });

    testWidgets('HTP session·stage identity 변경은 이전 전송을 취소하고 새 snapshot을 쓴다', (
      tester,
    ) async {
      final uploadA = Completer<DrawingUploadResponseDto>();
      final uploadB = Completer<DrawingUploadResponseDto>();
      final repository = _FakeDrawingRepository(
        uploadCompleters: [uploadA, uploadB],
      );
      final adapter = _FakePhotoPickerAdapter(
        galleryResults: [
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'house.png',
            mimeType: 'image/png',
          ),
          PickedPhoto(
            bytes: _tinyPngBytes,
            fileName: 'tree.png',
            mimeType: 'image/png',
          ),
        ],
      );

      Widget stageScreen(int sessionId, int step, String subject) =>
          buildScreen(
            repository: repository,
            photoPickerAdapter: adapter,
            existingDrawingSessionId: sessionId,
            restoredActivityContext: DrawingActivityContextDto(
              activityKind: 'HTP',
              htpAssessmentId: 91,
              htpStatus: 'IN_PROGRESS',
              stepOrder: step,
              drawingSubject: subject,
            ),
          );

      await tester.pumpWidget(MaterialApp(home: stageScreen(901, 1, 'HOUSE')));
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 1);

      await tester.pumpWidget(MaterialApp(home: stageScreen(902, 2, 'TREE')));
      await tester.pump();
      expect(repository.cancellationSignals, 1);
      expect(
        find.byKey(const ValueKey('input-method-gallery')),
        findsOneWidget,
      );

      uploadA.complete(repository._uploadResponse(901, 1));
      await tester.pump();
      expect(repository.completionKeys, isEmpty);

      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await waitForUpload(tester, repository, 2);
      uploadB.complete(repository._uploadResponse(902, 2));
      await tester.pumpAndSettle();

      expect(repository.uploadSessionIds, [901, 902]);
      expect(repository.uploadKeys.toSet(), hasLength(2));
      expect(repository.completionMetadata.single.sourceAssetId, 2);
    });
  });

  group('접근성·좁은 화면', () {
    testWidgets('좁은 화면과 2배 텍스트에서도 오버플로 없이 모든 단계를 오간다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final photo = PickedPhoto(
        bytes: _tinyPngBytes,
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(),
          ),
        ),
      );
      unawaited(
        navigatorKey.currentState!.push<DrawingSessionResolution>(
          MaterialPageRoute(
            builder: (_) => buildScreen(
              repository: repository,
              photoPickerAdapter: adapter,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byKey(const ValueKey('input-method-photo')),
      );
      await tester.tap(find.byKey(const ValueKey('input-method-photo')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byKey(const ValueKey('input-method-gallery')),
      );
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final confirmButton = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(const ValueKey('input-method-confirm')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(confirmButton.properties.button, isTrue);
    });
  });
}

final class _FakePhotoPickerAdapter implements PhotoPickerAdapter {
  _FakePhotoPickerAdapter({
    this.cameraResults = const [],
    this.galleryResults = const [],
    this.galleryCompleters = const [],
    this.cameraError,
    this.galleryError,
  });

  final List<PickedPhoto?> cameraResults;
  final List<PickedPhoto?> galleryResults;
  final List<Completer<PickedPhoto?>> galleryCompleters;
  final Object? cameraError;
  final Object? galleryError;
  int cameraCalls = 0;
  int galleryCalls = 0;

  @override
  Future<PickedPhoto?> pickFromCamera() async {
    cameraCalls += 1;
    final error = cameraError;
    if (error != null) throw error;
    return cameraResults[cameraCalls - 1];
  }

  @override
  Future<PickedPhoto?> pickFromGallery() async {
    final index = galleryCalls;
    galleryCalls += 1;
    final error = galleryError;
    if (error != null) throw error;
    if (index < galleryCompleters.length) {
      return galleryCompleters[index].future;
    }
    return galleryResults[index - galleryCompleters.length];
  }
}

final class _FakePhotoPermissionService implements PhotoPermissionService {
  _FakePhotoPermissionService({
    this.permissionStatus = PhotoPermissionStatus.denied,
    this.openSettingsResult = true,
    this.openSettingsCompleter,
  });

  final PhotoPermissionStatus permissionStatus;
  final bool openSettingsResult;
  final Completer<bool>? openSettingsCompleter;
  int openSettingsCalls = 0;

  @override
  Future<PhotoPermissionStatus> status(PhotoPermissionKind kind) async =>
      permissionStatus;

  @override
  Future<bool> openSettings() async {
    openSettingsCalls += 1;
    return openSettingsCompleter?.future ?? openSettingsResult;
  }
}

final class _FakeDrawingRepository
    implements
        CancellableDrawingUploadRepository,
        HtpDrawingRepository,
        UploadedDrawingCompletionRepository,
        DrawingSessionDiscarder {
  _FakeDrawingRepository({
    List<bool>? createFailures,
    this.uploadFailures = const [],
    this.uploadGate,
    this.uploadCompleters = const [],
    this.sessionCreationCompleters = const [],
    this.nextStepCompleters = const [],
    this.uploadProgressEvents = const [],
    this.completionFailures = const [],
    this.completionCompleters = const [],
    this.deleteGate,
    this.getSessionCurrentStage = 'DRAWING',
  }) : createFailures = createFailures ?? const [];

  static const createdSessionId = 900;

  final List<bool> createFailures;
  final List<Object?> uploadFailures;
  final Completer<void>? uploadGate;
  final List<Completer<DrawingUploadResponseDto>> uploadCompleters;
  final List<Completer<HtpAssessmentDto>> sessionCreationCompleters;
  final List<Completer<HtpAssessmentDto>> nextStepCompleters;
  final List<(int sent, int total)> uploadProgressEvents;
  final List<Object?> completionFailures;
  final List<Completer<DrawingStageCompleteResponseDto>> completionCompleters;
  final Completer<void>? deleteGate;
  final String getSessionCurrentStage;

  int createCalls = 0;
  int uploadCalls = 0;
  int getSessionCalls = 0;
  int nextStepCalls = 0;
  final List<int> deletedSessionIds = [];
  final List<int> nextStepAssessmentIds = [];
  final List<String> nextStepKeys = [];
  final List<String> nextStepInputMethods = [];
  final List<String> uploadKeys = [];
  final List<String> completionKeys = [];
  final List<int> uploadSessionIds = [];
  final List<BinaryUploadDto> uploadImages = [];
  final List<UploadDrawingImageMetadataDto> uploadMetadata = [];
  final List<DrawingCompleteMetadataDto> completionMetadata = [];
  final List<DrawingUploadCancellation> uploadCancellations = [];
  final List<DrawingUploadProgressCallback?> uploadProgressCallbacks = [];
  final Map<String, int> _assetIdsByUploadKey = {};
  int cancellationSignals = 0;
  CreateDrawingSessionRequestDto? createRequest;
  StartHtpAssessmentRequestDto? startHtpRequest;

  /// 다음 주제 전환. 실패 목록으로 재시도 시나리오를 만든다.
  List<bool> nextStepFailures = const [];

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    final index = nextStepCalls;
    nextStepCalls += 1;
    nextStepAssessmentIds.add(assessmentId);
    nextStepKeys.add(idempotencyKey);
    nextStepInputMethods.add(inputMethod);
    if (index < nextStepFailures.length && nextStepFailures[index]) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    if (index < nextStepCompleters.length) {
      return nextStepCompleters[index].future;
    }
    return nextStepAssessment(assessmentId: assessmentId, sessionId: 902);
  }

  HtpAssessmentDto nextStepAssessment({
    required int assessmentId,
    required int sessionId,
  }) => HtpAssessmentDto(
    htpAssessmentId: assessmentId,
    status: 'IN_PROGRESS',
    expiresAt: '2026-07-30T01:00:00Z',
    currentStep: HtpAssessmentStepDto(
      stepOrder: 2,
      drawingSubject: 'TREE',
      drawingSessionId: sessionId,
      sessionStatus: 'IN_PROGRESS',
      currentStage: 'DRAWING',
    ),
    allStepsCompleted: false,
  );

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    final index = createCalls;
    startHtpRequest = request;
    final shouldFail = index < createFailures.length && createFailures[index];
    createCalls += 1;
    if (shouldFail) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    if (index < sessionCreationCompleters.length) {
      return sessionCreationCompleters[index].future;
    }
    return createdAssessment();
  }

  HtpAssessmentDto createdAssessment({int sessionId = createdSessionId}) =>
      HtpAssessmentDto(
        htpAssessmentId: 91,
        status: 'IN_PROGRESS',
        expiresAt: '2026-07-30T01:00:00Z',
        currentStep: HtpAssessmentStepDto(
          stepOrder: 1,
          drawingSubject: 'HOUSE',
          drawingSessionId: sessionId,
          sessionStatus: 'IN_PROGRESS',
          currentStage: 'DRAWING',
        ),
        allStepsCompleted: false,
      );

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async => const ApiPage(
    content: [
      DrawingTypeDto(
        drawingTypeId: 5,
        code: 'ART_DIARY',
        name: '그림일기',
        activityCategory: 'GENERAL',
        selectableBy: 'BOTH',
        recommendedAgeMin: null,
        recommendedAgeMax: null,
        guideText: null,
        displayOrder: 1,
      ),
    ],
    page: 0,
    size: 1,
    totalElements: 1,
    totalPages: 1,
    hasNext: false,
  );

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    createRequest = request;
    final shouldFail =
        createCalls < createFailures.length && createFailures[createCalls];
    createCalls += 1;
    if (shouldFail) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    return DrawingSessionDto.fromCreateJson({
      'drawingSessionId': createdSessionId,
      'childId': request.childId,
      'drawingType': {
        'drawingTypeId': request.drawingTypeId,
        'code': 'ART_DIARY',
        'name': '그림일기',
      },
      'inputMethod': request.inputMethod,
      'title': null,
      'sessionStatus': 'DRAWING',
      'currentStage': 'DRAWING',
      'selectedEmotions': null,
      'expressedEmotionText': null,
      'startedAt': request.clientStartedAt,
      'completedAt': null,
      'conversation': null,
      'latestAnalysis': null,
      'assets': [],
    });
  }

  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    required UploadDrawingImageMetadataDto metadata,
    required String idempotencyKey,
    DrawingUploadProgressCallback? onProgress,
    DrawingUploadCancellation? cancellation,
  }) async {
    final index = uploadCalls;
    uploadCalls += 1;
    uploadSessionIds.add(sessionId);
    uploadImages.add(image);
    uploadMetadata.add(metadata);
    uploadKeys.add(idempotencyKey);
    uploadProgressCallbacks.add(onProgress);
    if (cancellation != null) {
      uploadCancellations.add(cancellation);
      unawaited(
        cancellation.whenCancelled.then((_) => cancellationSignals += 1),
      );
    }
    if (index < uploadFailures.length) {
      final failure = uploadFailures[index];
      if (failure != null) throw failure;
    }
    for (final event in uploadProgressEvents) {
      onProgress?.call(event.$1, event.$2);
    }
    await uploadGate?.future;
    if (index < uploadCompleters.length) {
      return uploadCompleters[index].future;
    }
    return _uploadResponse(
      sessionId,
      _assetIdsByUploadKey.putIfAbsent(idempotencyKey, () => index + 1),
    );
  }

  void emitUploadProgress(int attempt, int sent, int total) {
    uploadProgressCallbacks[attempt]?.call(sent, total);
  }

  DrawingUploadResponseDto _uploadResponse(int sessionId, int assetId) {
    return DrawingUploadResponseDto.fromJson({
      'drawingSessionId': sessionId,
      'drawingAssetId': assetId,
      'assetType': 'UPLOADED',
      'drawingSubject': 'HOUSE',
      'currentStage': 'DRAWING',
      'previewUrl': '/api/v1/drawing-assets/$assetId/file',
      'mimeType': 'image/png',
      'fileSizeBytes': 100,
      'widthPx': 100,
      'heightPx': 100,
      'capturedAt': '2026-07-29T01:00:00Z',
      'uploadedAt': '2026-07-29T01:00:01Z',
      'qualityWarnings': const <String>[],
    });
  }

  @override
  Future<DrawingStageCompleteResponseDto> completeUploadedDrawingStage(
    int sessionId, {
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async {
    final index = completionKeys.length;
    completionKeys.add(idempotencyKey);
    completionMetadata.add(metadata);
    if (index < completionFailures.length) {
      final failure = completionFailures[index];
      if (failure != null) throw failure;
    }
    if (index < completionCompleters.length) {
      return completionCompleters[index].future;
    }
    return completionResponse(sessionId, metadata.sourceAssetId!);
  }

  DrawingStageCompleteResponseDto completionResponse(
    int sessionId,
    int assetId,
  ) => DrawingStageCompleteResponseDto.fromJson({
    'drawingSessionId': sessionId,
    'finalAssetId': assetId,
    'sessionStatus': 'IN_PROGRESS',
    'currentStage': 'CONVERSING',
    'analysis': {
      'analysisId': 10,
      'analysisType': 'OBJECT_DETECTION',
      'status': 'SUCCEEDED',
    },
    'nextAction': 'SELECT_EMOTION',
  });

  @override
  Future<DrawingSessionDto> getSession(int sessionId) async {
    getSessionCalls += 1;
    return DrawingSessionDto.fromDetailJson({
      'drawingSessionId': sessionId,
      'child': {'childId': 7},
      'drawingType': {'drawingTypeId': 5, 'code': 'ART_DIARY', 'name': '그림일기'},
      'inputMethod': 'UPLOAD',
      'title': null,
      'sessionStatus': getSessionCurrentStage,
      'currentStage': getSessionCurrentStage,
      'selectedEmotions': null,
      'expressedEmotionText': null,
      'startedAt': '2026-07-29T00:00:00Z',
      'completedAt': null,
      'conversation': null,
      'latestAnalysis': null,
      'conversationId': null,
      'reportId': null,
      'assets': [],
    });
  }

  @override
  Future<void> deleteSession(int sessionId) async {
    deletedSessionIds.add(sessionId);
    await deleteGate?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
