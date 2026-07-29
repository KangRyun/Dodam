import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/drawing/application/drawing_session_start_controller.dart';
import 'package:dodam/features/drawing/application/photo_upload_validation.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/photo_picker_adapter.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/screens/input_method_select_screen.dart';
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
    PhotoPickerAdapter? photoPickerAdapter,
    PhotoDimensionReader? dimensionReader,
  }) => InputMethodSelectScreen(
    childId: 7,
    drawingTypeId: 5,
    title: '그림일기',
    description: '오늘 있었던 일을 그림으로 그려 볼까?',
    icon: Icons.menu_book_rounded,
    accentColor: Colors.orange,
    repository: repository,
    photoPickerAdapter: photoPickerAdapter ?? _FakePhotoPickerAdapter(),
    dimensionReader: dimensionReader ?? ((_) async => (100, 100)),
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
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
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

    testWidgets('연속으로 두 번 탭해도 세션 생성과 업로드는 한 번만 일어난다', (tester) async {
      final photo = await validPhoto();
      final adapter = _FakePhotoPickerAdapter(galleryResults: [photo]);
      final repository = _FakeDrawingRepository();

      await pumpScreen(
        tester,
        buildScreen(repository: repository, photoPickerAdapter: adapter),
      );
      await goToPhotoSource(tester);
      await tester.tap(find.byKey(const ValueKey('input-method-gallery')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      // 첫 탭으로 버튼이 로딩 상태로 바뀌는 애니메이션 프레임 중이라 두 번째
      // 탭이 히트테스트를 놓칠 수 있다 — 중복 탭 방지 자체는 onPressed가
      // null이 되는 로직이 맡으므로 경고는 무시해도 된다.
      await tester.tap(
        find.byKey(const ValueKey('input-method-confirm')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.uploadCalls, 1);
    });

    for (final testCase in [
      ('IMAGE_TOO_BLURRY', '흐려서'),
      ('DRAWING_REGION_NOT_FOUND', '보이지 않아요'),
      ('IMAGE_DIMENSION_INVALID', '크기가 적절하지'),
      ('UPLOAD_FAILED', '올리지 못했어요'),
    ]) {
      testWidgets('서버 오류 ${testCase.$1}는 아이콘·문구로 안내하고 같은 사진으로 재시도할 수 있다', (
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

        // 같은 세션·같은 사진으로 재시도 — 세션을 다시 만들지 않는다.
        await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
        await tester.pumpAndSettle();

        expect(repository.createCalls, 1);
        expect(repository.uploadCalls, 2);
        expect(popped?.sessionId, 900);
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
      expect(popped?.sessionId, 900);
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
  });

  final List<PickedPhoto?> cameraResults;
  final List<PickedPhoto?> galleryResults;
  int cameraCalls = 0;
  int galleryCalls = 0;

  @override
  Future<PickedPhoto?> pickFromCamera() async => cameraResults[cameraCalls++];

  @override
  Future<PickedPhoto?> pickFromGallery() async =>
      galleryResults[galleryCalls++];
}

final class _FakeDrawingRepository
    implements
        DrawingRepository,
        HtpDrawingRepository,
        UploadedDrawingCompletionRepository,
        DrawingSessionDiscarder {
  _FakeDrawingRepository({
    List<bool>? createFailures,
    this.uploadFailures = const [],
    this.getSessionCurrentStage = 'DRAWING',
  }) : createFailures = createFailures ?? const [];

  static const createdSessionId = 900;

  final List<bool> createFailures;
  final List<Object?> uploadFailures;
  final String getSessionCurrentStage;

  int createCalls = 0;
  int uploadCalls = 0;
  int getSessionCalls = 0;
  final List<int> deletedSessionIds = [];
  CreateDrawingSessionRequestDto? createRequest;
  StartHtpAssessmentRequestDto? startHtpRequest;

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    startHtpRequest = request;
    final shouldFail =
        createCalls < createFailures.length && createFailures[createCalls];
    createCalls += 1;
    if (shouldFail) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    return const HtpAssessmentDto(
      htpAssessmentId: 91,
      status: 'IN_PROGRESS',
      expiresAt: '2026-07-30T01:00:00Z',
      currentStep: HtpAssessmentStepDto(
        stepOrder: 1,
        drawingSubject: 'HOUSE',
        drawingSessionId: createdSessionId,
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
      ),
      allStepsCompleted: false,
    );
  }

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
  }) async {
    final index = uploadCalls;
    uploadCalls += 1;
    if (index < uploadFailures.length) {
      final failure = uploadFailures[index];
      if (failure != null) throw failure;
    }
    return DrawingUploadResponseDto.fromJson({
      'drawingSessionId': sessionId,
      'drawingAssetId': 1,
      'assetType': 'UPLOADED',
      'drawingSubject': 'HOUSE',
      'currentStage': 'DRAWING',
      'previewUrl': '/api/v1/drawing-assets/1/file',
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
  }) async => DrawingStageCompleteResponseDto.fromJson({
    'drawingSessionId': sessionId,
    'finalAssetId': metadata.sourceAssetId,
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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
