import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/app/router/app_router.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child_mode/domain/dodam_costume.dart';
import 'package:dodam/features/child_mode/presentation/screens/child_mode_screens.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_session_start_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/photo_permission_service.dart';
import 'package:dodam/features/drawing/domain/photo_picker_adapter.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:dodam/features/drawing/presentation/screens/input_method_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// S15P11B209-834 — HTP 사진 흐름이 HOUSE→TREE→PERSON 3회 이어지는지 검증한다.
///
/// * 결함 A: 첫 업로드 후 아동 홈에 멈추지 않고 대화로 자동 진입
/// * 결함 B: 주제 전환이 입력 방식을 보고 사진 화면으로 되돌아옴
///
/// flag는 dart-define 기본값에 의존하지 않고 테스트가 항상 명시적으로 넣는다.
void main() {
  group('결함 B — 주제 전환은 입력 방식을 보고 화면을 고른다', () {
    testWidgets('UPLOAD 다음 주제는 캔버스를 열지 않고 상위 진입 화면에 올려보낸다', (tester) async {
      final repository = _FakeDrawingRepository();
      final drawingRoutes = <DrawingRouteArguments>[];
      final popped = await _pumpHouseConversation(
        tester,
        repository: repository,
        inputMethod: 'UPLOAD',
        drawingRoutes: drawingRoutes,
      );

      await _endConversation(tester);

      expect(repository.nextStepCalls, 1);
      expect(repository.nextStepInputMethods, ['UPLOAD']);
      // 캔버스를 직접 열지 않는다 — 사진 화면 결정은 상위 진입 화면 몫이다.
      expect(drawingRoutes, isEmpty);
      final result = await popped;
      expect(result, isNotNull);
      final next = result!.nextResolution;
      expect(next, isNotNull);
      expect(next!.inputMethod, 'UPLOAD');
      expect(next.currentStage, 'DRAWING');
      expect(next.target, DrawingResolutionTarget.photoInput);
      expect(next.activityContext.drawingSubject, 'TREE');
      expect(next.sessionId, 902);
    });

    testWidgets('CANVAS 다음 주제는 기존처럼 캔버스를 바로 연다', (tester) async {
      final repository = _FakeDrawingRepository();
      final drawingRoutes = <DrawingRouteArguments>[];
      await _pumpHouseConversation(
        tester,
        repository: repository,
        inputMethod: 'CANVAS',
        drawingRoutes: drawingRoutes,
      );

      await _endConversation(tester);

      expect(repository.nextStepCalls, 1);
      expect(repository.nextStepInputMethods, ['CANVAS']);
      expect(drawingRoutes, hasLength(1));
      expect(drawingRoutes.single.inputMethod, 'CANVAS');
      expect(drawingRoutes.single.startFresh, isTrue);
      // 그림 단계이므로 대화를 이어열지 않는다.
      expect(drawingRoutes.single.resumeConversation, isFalse);
      expect(drawingRoutes.single.autoRestoreDraft, isFalse);
      expect(drawingRoutes.single.companion, DodamCostume.octopus);
    });

    testWidgets('주제 전환 실패 후 재시도는 같은 Key를 재사용한다', (tester) async {
      final repository = _FakeDrawingRepository()
        ..nextStepFailures = const [true];
      await _pumpHouseConversation(
        tester,
        repository: repository,
        inputMethod: 'UPLOAD',
        drawingRoutes: <DrawingRouteArguments>[],
      );

      await _endConversation(tester);
      expect(repository.nextStepCalls, 1);
      expect(find.byKey(const ValueKey('htp-advance-error')), findsOneWidget);

      final retry = find.byKey(const ValueKey('htp-advance-retry'));
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(repository.nextStepCalls, 2);
      expect(repository.nextStepKeys.first, repository.nextStepKeys.last);
      expect(repository.nextStepInputMethods, ['UPLOAD', 'UPLOAD']);
    });
  });

  group('보호자 경로 자동 시작 조건', () {
    // 보호자가 넘긴 resolution 중 어떤 것만 홈을 건너뛰어야 하는지 못 박는다.
    // 캔버스 최초 선택까지 자동으로 열면 S834 범위를 넘어 기존 계약이 깨진다.
    bool autoStarts(DrawingSessionResolution resolution) =>
        resolution.isUploadInput &&
        resolution.target == DrawingResolutionTarget.conversation;

    test('사진 업로드가 끝난 UPLOAD + CONVERSING만 자동 시작한다', () {
      expect(
        autoStarts(
          _resolution(
            sessionId: 901,
            stage: 'CONVERSING',
            inputMethod: 'UPLOAD',
            subject: 'HOUSE',
          ),
        ),
        isTrue,
      );
    });

    test('최초 CANVAS + DRAWING은 자동 시작하지 않는다', () {
      expect(
        autoStarts(
          _resolution(
            sessionId: 700,
            stage: 'DRAWING',
            inputMethod: 'CANVAS',
            subject: 'HOUSE',
          ),
        ),
        isFalse,
      );
    });

    test('사진을 아직 올리지 않은 UPLOAD + DRAWING도 자동 시작하지 않는다', () {
      expect(
        autoStarts(
          _resolution(
            sessionId: 901,
            stage: 'DRAWING',
            inputMethod: 'UPLOAD',
            subject: 'HOUSE',
          ),
        ),
        isFalse,
      );
    });

    test('CANVAS + CONVERSING 이어 그리기도 자동 시작하지 않는다', () {
      expect(
        autoStarts(
          _resolution(
            sessionId: 700,
            stage: 'CONVERSING',
            inputMethod: 'CANVAS',
            subject: 'HOUSE',
          ),
        ),
        isFalse,
      );
    });
  });

  group('결함 A — 첫 업로드 뒤 홈에서 멈추지 않는다', () {
    testWidgets('사진 업로드·완료 후 추가 탭 없이 대화로 자동 진입한다', (tester) async {
      final harness = _FlowHarness(htpPhotoUploadEnabled: true);
      await harness.pumpPrepared(
        tester,
        _resolution(
          sessionId: 901,
          stage: 'CONVERSING',
          inputMethod: 'UPLOAD',
          subject: 'HOUSE',
        ),
      );

      // 아동 홈의 그림 그리기 버튼을 다시 누르지 않았는데 대화가 열려 있다.
      expect(find.byKey(const ValueKey('draw-entry')), findsNothing);
      expect(find.text('conversation-901'), findsOneWidget);
      expect(harness.drawingRoutes, hasLength(1));
      expect(harness.drawingRoutes.single.resumeConversation, isTrue);
      expect(harness.drawingRoutes.single.sessionId, 901);
      expect(harness.drawingRoutes.single.companion, DodamCostume.dino);
      // UPLOAD 세션에는 Canvas Draft가 없다 — 조회·복원을 시도하지 않는다.
      expect(harness.drawingRoutes.single.autoRestoreDraft, isFalse);
      expect(harness.repository.createCalls, 0);
      expect(harness.repository.htpStartCalls, 0);
      expect(harness.repository.nextStepCalls, 0);
      expect(harness.repository.deletedSessionIds, isEmpty);
    });

    testWidgets('CANVAS 이어 그리기는 기존 Draft 복원 계약을 유지한다', (tester) async {
      final harness = _FlowHarness();
      await harness.pumpPrepared(
        tester,
        _resolution(
          sessionId: 700,
          stage: 'DRAWING',
          inputMethod: 'CANVAS',
          subject: 'HOUSE',
        ),
      );

      expect(harness.drawingRoutes, hasLength(1));
      expect(harness.drawingRoutes.single.autoRestoreDraft, isTrue);
      expect(harness.drawingRoutes.single.resumeConversation, isFalse);
    });
  });

  group('HOUSE→TREE→PERSON 사진 3회', () {
    testWidgets('세 주제 모두 사진을 새로 골라 올리고 각각 대화로 넘어간다', (tester) async {
      final harness = _FlowHarness(
        htpPhotoUploadEnabled: true,
        nextSubjects: [
          _resolution(
            sessionId: 902,
            stage: 'DRAWING',
            inputMethod: 'UPLOAD',
            subject: 'TREE',
          ),
          _resolution(
            sessionId: 903,
            stage: 'DRAWING',
            inputMethod: 'UPLOAD',
            subject: 'PERSON',
          ),
        ],
      );
      await harness.pumpPhotoStage(tester, sessionId: 901, subject: 'HOUSE');

      // HOUSE
      expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
      await harness.capturePhoto(tester);
      expect(harness.picker.cameraCalls, 1);
      expect(harness.repository.uploadCalls, 1);
      expect(harness.repository.completionKeys, hasLength(1));
      expect(find.text('conversation-901'), findsOneWidget);

      // TREE
      await harness.endConversation(tester);
      expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
      await harness.capturePhoto(tester);
      expect(harness.picker.cameraCalls, 2);
      expect(harness.repository.uploadCalls, 2);
      expect(harness.repository.completionKeys, hasLength(2));
      expect(find.text('conversation-902'), findsOneWidget);

      // PERSON
      await harness.endConversation(tester);
      expect(find.byKey(const ValueKey('input-method-camera')), findsOneWidget);
      await harness.capturePhoto(tester);
      expect(harness.picker.cameraCalls, 3);
      expect(harness.repository.uploadCalls, 3);
      expect(harness.repository.completionKeys, hasLength(3));
      expect(find.text('conversation-903'), findsOneWidget);

      // 총계 — 사진 3회, 업로드 3회, 완료 3회, 대화 3회.
      expect(harness.picker.cameraCalls, 3);
      expect(harness.picker.galleryCalls, 0);
      expect(harness.repository.uploadSessionIds, [901, 902, 903]);
      expect(harness.drawingRoutes.map((it) => it.sessionId), [901, 902, 903]);
      expect(
        harness.drawingRoutes.every((it) => it.resumeConversation),
        isTrue,
      );
      expect(harness.drawingRoutes.map((it) => it.companion).toSet(), {
        DodamCostume.dino,
      });
      // 세 주제의 asset이 서로 다르다.
      expect(
        harness.repository.completionMetadata
            .map((it) => it.sourceAssetId)
            .toSet(),
        hasLength(3),
      );
      // 업로드·완료 Key가 단계마다 달라 중복 완료가 생기지 않는다.
      expect(harness.repository.uploadKeys.toSet(), hasLength(3));
      expect(harness.repository.completionKeys.toSet(), hasLength(3));
      // 새 세션·새 assessment를 만들지 않고 기존 세션을 지우지도 않는다.
      expect(harness.repository.createCalls, 0);
      expect(harness.repository.htpStartCalls, 0);
      expect(harness.repository.deletedSessionIds, isEmpty);
      // Canvas Draft는 어느 단계에서도 건드리지 않는다.
      expect(harness.drawingRoutes.every((it) => !it.autoRestoreDraft), isTrue);
    });

    testWidgets('사진 사용하기를 연달아 눌러도 업로드·완료는 한 번이다', (tester) async {
      final harness = _FlowHarness(htpPhotoUploadEnabled: true);
      await harness.pumpPhotoStage(tester, sessionId: 901, subject: 'HOUSE');
      await harness.pickPhoto(tester);

      final confirm = tester.getCenter(
        find.byKey(const ValueKey('input-method-confirm')),
      );
      await tester.tapAt(confirm);
      await tester.tapAt(confirm);
      await tester.pumpAndSettle();

      expect(harness.repository.uploadCalls, 1);
      expect(harness.repository.completionKeys, hasLength(1));
      expect(harness.drawingRoutes, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('업로드 실패 후 재시도는 같은 Key로 한 번만 완료한다', (tester) async {
      final harness = _FlowHarness(
        htpPhotoUploadEnabled: true,
        uploadFailures: const [
          ApiTransportFailure(type: ApiTransportFailureType.connection),
        ],
      );
      await harness.pumpPhotoStage(tester, sessionId: 901, subject: 'HOUSE');
      await harness.pickPhoto(tester);

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();
      expect(harness.repository.uploadCalls, 1);
      expect(harness.repository.completionKeys, isEmpty);
      expect(harness.drawingRoutes, isEmpty);

      await tester.tap(find.byKey(const ValueKey('input-method-confirm')));
      await tester.pumpAndSettle();

      expect(harness.repository.uploadCalls, 2);
      expect(
        harness.repository.uploadKeys.first,
        harness.repository.uploadKeys.last,
      );
      expect(harness.repository.completionKeys, hasLength(1));
      expect(harness.drawingRoutes, hasLength(1));
    });

    testWidgets('미리보기에서 다시 선택하면 업로드하지 않고 사진을 다시 고른다', (tester) async {
      final harness = _FlowHarness(htpPhotoUploadEnabled: true);
      await harness.pumpPhotoStage(tester, sessionId: 901, subject: 'HOUSE');
      await harness.pickPhoto(tester);

      await tester.tap(find.byKey(const ValueKey('input-method-reselect')));
      await tester.pumpAndSettle();

      expect(harness.repository.uploadCalls, 0);
      expect(harness.repository.completionKeys, isEmpty);
      expect(harness.drawingRoutes, isEmpty);
      expect(harness.repository.deletedSessionIds, isEmpty);
    });
  });

  group('flag false containment', () {
    testWidgets('사진 CTA가 없고 사진 API를 한 번도 부르지 않는다', (tester) async {
      final harness = _FlowHarness();
      await harness.pumpPhotoStage(tester, sessionId: 901, subject: 'HOUSE');

      expect(find.byKey(const ValueKey('input-method-photo')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-camera')), findsNothing);
      expect(find.byKey(const ValueKey('input-method-gallery')), findsNothing);
      expect(harness.picker.cameraCalls, 0);
      expect(harness.picker.galleryCalls, 0);
      expect(harness.repository.uploadCalls, 0);
      expect(harness.repository.completionKeys, isEmpty);
      expect(harness.repository.createCalls, 0);
      expect(harness.repository.htpStartCalls, 0);
      expect(harness.repository.deletedSessionIds, isEmpty);
    });
  });

  group('반응형', () {
    for (final size in const [Size(320, 640), Size(1200, 800)]) {
      testWidgets(
        '${size.width.toInt()}×${size.height.toInt()}에서 사진 흐름에 overflow가 없다',
        (tester) async {
          final harness = _FlowHarness(htpPhotoUploadEnabled: true);
          await harness.pumpPhotoStage(
            tester,
            sessionId: 901,
            subject: 'HOUSE',
            size: size,
          );
          await harness.capturePhoto(tester);

          expect(tester.takeException(), isNull);
          expect(harness.drawingRoutes, hasLength(1));
        },
      );
    }
  });
}

// ---------------------------------------------------------------------------
// 결함 B harness — 실제 DrawingScreen 의 대화 종료 제스처를 사용한다.
// ---------------------------------------------------------------------------

/// 실제 [DrawingScreen]을 push 해 대화 종료 뒤 pop 결과까지 관측한다.
Future<Future<DrawingRouteResult?>> _pumpHouseConversation(
  WidgetTester tester, {
  required _FakeDrawingRepository repository,
  required String inputMethod,
  required List<DrawingRouteArguments> drawingRoutes,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.drawing('7')) {
          drawingRoutes.add(settings.arguments! as DrawingRouteArguments);
          return MaterialPageRoute<DrawingRouteResult>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('next-drawing')),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: SizedBox.shrink()),
        );
      },
      home: const Scaffold(body: Text('activity-entry')),
    ),
  );
  await tester.pumpAndSettle();

  final popped = navigatorKey.currentState!.push<DrawingRouteResult>(
    MaterialPageRoute<DrawingRouteResult>(
      builder: (_) => DrawingScreen(
        childId: '7',
        sessionId: 901,
        companion: DodamCostume.octopus,
        drawingRepository: repository,
        conversationRepository: const _ConversationRepository(),
        conversationEndRepository: const _EndRepository(),
        conversationId: 8001,
        resumeConversation: true,
        inputMethod: inputMethod,
        activityContext: const DrawingActivityContextDto(
          activityKind: 'HTP',
          htpAssessmentId: 91,
          htpStatus: 'IN_PROGRESS',
          stepOrder: 1,
          drawingSubject: 'HOUSE',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return popped;
}

Future<void> _endConversation(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai-conversation-end')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('대화 그만하기'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// 결함 A · 3회 흐름 harness — 실제 아동 홈과 실제 사진 입력 화면을 사용한다.
// ---------------------------------------------------------------------------

final class _FlowHarness {
  _FlowHarness({
    this.htpPhotoUploadEnabled = false,
    List<Object?> uploadFailures = const [],
    List<DrawingSessionResolution> nextSubjects = const [],
  }) : repository = _FakeDrawingRepository(uploadFailures: uploadFailures),
       _nextSubjects = List.of(nextSubjects);

  final bool htpPhotoUploadEnabled;
  final _FakeDrawingRepository repository;
  final _FakePhotoPickerAdapter picker = _FakePhotoPickerAdapter();
  final List<DrawingRouteArguments> drawingRoutes = [];
  final List<DrawingSessionResolution> _nextSubjects;

  /// 실제 라우터와 같은 방식으로 세 화면을 잇는다.
  ///
  /// 대화 화면만 대역이다 — 대화 종료 버튼이 캔버스 대신 다음 주제 세션을
  /// 올려보내며, 그 결과를 라우팅하는 것은 실제 아동 홈이다.
  Widget _app(DrawingSessionResolution prepared) => MaterialApp(
    onGenerateRoute: (settings) {
      if (settings.name == AppRoutes.drawingInputMethod('7')) {
        final arguments =
            settings.arguments! as InputMethodSelectRouteArguments;
        return MaterialPageRoute<DrawingSessionResolution>(
          settings: settings,
          builder: (_) => InputMethodSelectScreen(
            childId: arguments.childId,
            drawingTypeId: arguments.drawingTypeId,
            title: arguments.title,
            description: arguments.description,
            icon: arguments.icon,
            accentColor: arguments.accentColor,
            repository: arguments.repository,
            existingDrawingSessionId: arguments.existingDrawingSessionId,
            restoredActivityContext: arguments.restoredActivityContext,
            htpAssessmentId: arguments.htpAssessmentId,
            htpPhotoUploadEnabled: htpPhotoUploadEnabled,
            photoPickerAdapter: picker,
            photoPermissionService: _FakePhotoPermissionService(),
            // 실제 디코더는 위젯 테스트에서 쓸 수 없어 크기만 대역으로 준다.
            dimensionReader: (_) async => (400, 400),
          ),
        );
      }
      if (settings.name == AppRoutes.drawing('7')) {
        final arguments = settings.arguments! as DrawingRouteArguments;
        drawingRoutes.add(arguments);
        return MaterialPageRoute<DrawingRouteResult>(
          settings: settings,
          builder: (routeContext) => Scaffold(
            body: Column(
              children: [
                Text('conversation-${arguments.sessionId}'),
                TextButton(
                  key: const ValueKey('end-conversation'),
                  onPressed: _nextSubjects.isEmpty
                      ? null
                      : () => Navigator.of(routeContext).pop(
                          DrawingRouteResult.advanceTo(
                            _nextSubjects.removeAt(0),
                          ),
                        ),
                  child: const Text('대화 끝'),
                ),
              ],
            ),
          ),
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: SizedBox.shrink()),
      );
    },
    home: ChildModeHomeScreen(
      child: _child,
      drawingRepository: repository,
      htpPhotoUploadEnabled: htpPhotoUploadEnabled,
      preparedResolution: prepared,
      autoStartPrepared: true,
    ),
  );

  Future<void> pumpPrepared(
    WidgetTester tester,
    DrawingSessionResolution prepared, {
    Size size = const Size(1200, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(prepared));
    await tester.pumpAndSettle();
  }

  /// 아직 사진을 올리지 않은 UPLOAD 세션에서 시작한다.
  Future<void> pumpPhotoStage(
    WidgetTester tester, {
    required int sessionId,
    required String subject,
    Size size = const Size(1200, 800),
  }) => pumpPrepared(
    tester,
    _resolution(
      sessionId: sessionId,
      stage: 'DRAWING',
      inputMethod: 'UPLOAD',
      subject: subject,
    ),
    size: size,
  );

  /// 대화를 끝내 다음 주제 세션을 아동 홈으로 올려보낸다.
  Future<void> endConversation(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('end-conversation')));
    await tester.pumpAndSettle();
  }

  /// S471 안내를 지나 카메라로 사진을 고른다.
  ///
  /// 좁은 화면에서는 버튼이 스크롤 밖에 있어 먼저 화면 안으로 끌어온다.
  Future<void> pickPhoto(WidgetTester tester) async {
    await _tap(tester, const ValueKey('input-method-camera'));
    await _tap(tester, const ValueKey('camera-guidance-capture'));
  }

  Future<void> _tap(WidgetTester tester, Key key) async {
    final target = find.byKey(key);
    if (tester.any(find.byType(Scrollable))) {
      await tester.scrollUntilVisible(target, 200);
    }
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// 사진을 고르고 업로드·완료까지 진행한다.
  Future<void> capturePhoto(WidgetTester tester) async {
    await pickPhoto(tester);
    await _tap(tester, const ValueKey('input-method-confirm'));
  }
}

DrawingSessionResolution _resolution({
  required int sessionId,
  required String stage,
  required String inputMethod,
  required String subject,
}) => DrawingSessionResolution(
  sessionId: sessionId,
  currentStage: stage,
  inputMethod: inputMethod,
  activityContext: DrawingActivityContextDto(
    activityKind: 'HTP',
    htpAssessmentId: 91,
    htpStatus: 'IN_PROGRESS',
    stepOrder: switch (subject) {
      'HOUSE' => 1,
      'TREE' => 2,
      _ => 3,
    },
    drawingSubject: subject,
  ),
);

const _child = ChildSummaryDto(
  childId: 7,
  nickname: '도담',
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: 'https://example.invalid/profile.jpg',
  preferredCharacter: 'DINO',
  questionDifficulty: 'EASY',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

final class _FakePhotoPickerAdapter implements PhotoPickerAdapter {
  int cameraCalls = 0;
  int galleryCalls = 0;

  @override
  Future<PickedPhoto?> pickFromCamera() async {
    cameraCalls += 1;
    return _photo('camera-$cameraCalls');
  }

  @override
  Future<PickedPhoto?> pickFromGallery() async {
    galleryCalls += 1;
    return _photo('gallery-$galleryCalls');
  }

  PickedPhoto _photo(String name) => PickedPhoto(
    bytes: Uint8List.fromList(_pngBytes),
    fileName: '$name.png',
    mimeType: 'image/png',
  );
}

final class _FakePhotoPermissionService implements PhotoPermissionService {
  @override
  Future<PhotoPermissionStatus> status(PhotoPermissionKind kind) async =>
      PhotoPermissionStatus.denied;

  @override
  Future<PhotoPermissionStatus> request(PhotoPermissionKind kind) async =>
      PhotoPermissionStatus.denied;

  @override
  Future<bool> openSettings() async => true;
}

final class _ConversationRepository implements ConversationRepository {
  const _ConversationRepository();

  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async => 8001;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async => AiQuestion(
    messageId: 9001,
    conversationId: 8001,
    sequence: 1,
    text: '집을 그렸구나! 누가 살고 있어?',
    options: const [
      AiQuestionOption(
        optionId: 'OPT_1',
        type: 'OPTION',
        label: '가족',
        value: 'family',
      ),
    ],
    ttsAvailable: false,
    createdAt: DateTime.utc(2026, 8, 3),
  );
}

final class _EndRepository implements ConversationEndRepository {
  const _EndRepository();

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async => ConversationEndResult(
    conversationId: conversationId,
    conversationStatus: 'COMPLETED',
    completed: true,
    completionReason: 'CHILD_REQUEST',
    completedAt: '2026-08-03T00:00:00Z',
    nextStage: 'REFLECTION',
  );
}

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1Pe'
  'AAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

final class _FakeDrawingRepository
    implements
        CancellableDrawingUploadRepository,
        HtpDrawingRepository,
        UploadedDrawingCompletionRepository,
        DrawingSessionDiscarder {
  _FakeDrawingRepository({this.uploadFailures = const []});

  final List<Object?> uploadFailures;

  List<bool> nextStepFailures = const [];

  int createCalls = 0;
  int htpStartCalls = 0;
  int uploadCalls = 0;
  int getSessionCalls = 0;
  int nextStepCalls = 0;
  final List<int> deletedSessionIds = [];
  final List<String> nextStepKeys = [];
  final List<String> nextStepInputMethods = [];
  final List<String> uploadKeys = [];
  final List<String> completionKeys = [];
  final List<int> uploadSessionIds = [];
  final List<DrawingCompleteMetadataDto> completionMetadata = [];
  final Map<String, int> _assetIdsByUploadKey = {};

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    final index = nextStepCalls;
    nextStepCalls += 1;
    nextStepKeys.add(idempotencyKey);
    nextStepInputMethods.add(inputMethod);
    if (index < nextStepFailures.length && nextStepFailures[index]) {
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
    return const HtpAssessmentDto(
      htpAssessmentId: 91,
      status: 'IN_PROGRESS',
      expiresAt: '2026-08-30T01:00:00Z',
      currentStep: HtpAssessmentStepDto(
        stepOrder: 2,
        drawingSubject: 'TREE',
        drawingSessionId: 902,
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
      ),
      allStepsCompleted: false,
    );
  }

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    htpStartCalls += 1;
    throw StateError('새 HTP 활동을 만들면 안 된다.');
  }

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async => const ApiPage(
    content: [
      DrawingTypeDto(
        drawingTypeId: 9,
        code: 'HTP',
        name: '집·나무·사람 그림',
        activityCategory: 'ASSESSMENT',
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
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async => null;

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    createCalls += 1;
    throw StateError('새 세션을 만들면 안 된다.');
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
    uploadKeys.add(idempotencyKey);
    if (index < uploadFailures.length) {
      final failure = uploadFailures[index];
      if (failure != null) throw failure;
    }
    final assetId = _assetIdsByUploadKey.putIfAbsent(
      idempotencyKey,
      () => _assetIdsByUploadKey.length + 1,
    );
    return DrawingUploadResponseDto.fromJson({
      'drawingSessionId': sessionId,
      'drawingAssetId': assetId,
      'assetType': 'UPLOADED',
      'drawingSubject': 'HOUSE',
      'currentStage': 'DRAWING',
      'previewUrl': '/api/v1/drawing-assets/$assetId/file',
      'mimeType': 'image/png',
      'fileSizeBytes': 100,
      'widthPx': 400,
      'heightPx': 400,
      'capturedAt': '2026-08-03T01:00:00Z',
      'uploadedAt': '2026-08-03T01:00:01Z',
      'qualityWarnings': const <String>[],
    });
  }

  @override
  Future<DrawingStageCompleteResponseDto> completeUploadedDrawingStage(
    int sessionId, {
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async {
    completionKeys.add(idempotencyKey);
    completionMetadata.add(metadata);
    return DrawingStageCompleteResponseDto.fromJson({
      'drawingSessionId': sessionId,
      'finalAssetId': metadata.sourceAssetId,
      'sessionStatus': 'IN_PROGRESS',
      'currentStage': 'CONVERSING',
      'analysis': {
        'analysisId': 10,
        'analysisType': 'OBJECT_DETECTION',
        'status': 'SUCCEEDED',
      },
      'nextAction': 'START_CONVERSATION',
    });
  }

  @override
  Future<void> deleteSession(int sessionId) async {
    deletedSessionIds.add(sessionId);
  }

  @override
  Future<DrawingSessionDto> getSession(int sessionId) async {
    getSessionCalls += 1;
    return DrawingSessionDto.fromDetailJson({
      'drawingSessionId': sessionId,
      'child': {'childId': 7},
      'drawingType': {'drawingTypeId': 9, 'code': 'HTP', 'name': '집·나무·사람 그림'},
      'inputMethod': 'UPLOAD',
      'title': null,
      'sessionStatus': 'IN_PROGRESS',
      'currentStage': 'DRAWING',
      'selectedEmotions': null,
      'expressedEmotionText': null,
      'startedAt': '2026-08-03T01:00:00Z',
      'completedAt': null,
      'conversation': null,
      'latestAnalysis': null,
      'assets': [],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not stubbed.');
}
