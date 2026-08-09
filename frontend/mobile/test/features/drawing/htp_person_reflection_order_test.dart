import 'dart:typed_data';

import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PERSON 감정 화면이 확정 계약 순서대로 서버를 호출하는지 고정한다.
///
///   HTP Reflection 저장 → steps/next → complete
///
/// 백엔드는 PERSON 세션이 `REFLECTION` 단계일 때만 Reflection을 받고
/// `steps/next`가 그 세션을 `COMPLETED`로 바꾸므로, 순서가 뒤바뀌면 Reflection이
/// 영구히 저장되지 않는다.
const _personContext = DrawingActivityContextDto(
  activityKind: 'HTP',
  htpAssessmentId: 91,
  htpStatus: 'IN_PROGRESS',
  stepOrder: 3,
  drawingSubject: 'PERSON',
);

const _personFinalImage = BinaryUploadDto(
  bytes: [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    2,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    244,
    34,
    127,
    138,
    0,
    0,
    0,
    14,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    248,
    207,
    192,
    0,
    66,
    255,
    1,
    15,
    249,
    3,
    253,
    133,
    17,
    153,
    118,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ],
  fileName: 'person-final.png',
  mimeType: 'image/png',
);

Future<void> _pumpPersonEmotionScreen(
  WidgetTester tester, {
  required _RecordingHtpRepository repository,
  ActivityRepository? activityRepository,
  String inputMethod = 'UPLOAD',
  BinaryUploadDto? completedDrawingImage = _personFinalImage,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name != AppRoutes.activityComplete('3')) return null;
        // 완료 화면은 route 인자를 받지 않는다 — 접수 뒤의 전달 화면이라 세션
        // 식별자도 리포지토리도 필요 없다.
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('activity-complete')),
        );
      },
      home: EmotionSelectScreen(
        childId: '3',
        sessionId: 44,
        drawingRepository: repository,
        activityRepository:
            activityRepository ?? const _PreviewActivityRepository(),
        conversationAlreadyEnded: true,
        activityContext: _personContext,
        inputMethod: inputMethod,
        completedDrawingImage: completedDrawingImage,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickEmotionAndSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
  await tester.pumpAndSettle();
  await _submitAgain(tester);
}

Future<void> _submitAgain(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('emotion-submit')));
  await tester.pumpAndSettle();
}

Future<void> _skipAndSubmit(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('emotion-skip')),
    220,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('emotion-screen-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.byKey(const ValueKey('emotion-skip')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('emotion-skip-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PERSON 감정 화면은 단일 memory 대신 HTP 3장 인증 preview를 표시한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _RecordingHtpRepository();

    await _pumpPersonEmotionScreen(tester, repository: repository);

    expect(find.bySemanticsLabel('내가 완성한 그림'), findsNothing);
    expect(
      find.byKey(const ValueKey('htp-emotion-preview-HOUSE')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('htp-emotion-preview-TREE')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('htp-emotion-preview-PERSON')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('집 그림'), findsOneWidget);
    expect(find.bySemanticsLabel('나무 그림'), findsOneWidget);
    expect(find.bySemanticsLabel('사람 그림'), findsOneWidget);
    final previews = find.descendant(
      of: find.byKey(const ValueKey('htp-emotion-preview-gallery')),
      matching: find.byKey(const ValueKey('authenticated-image-success')),
    );
    expect(previews, findsNWidgets(3));
    for (final image in tester.widgetList<Image>(previews)) {
      expect(image.fit, BoxFit.contain);
    }
    semantics.dispose();
  });

  testWidgets('PERSON은 Reflection → steps/next → complete 순서로 호출한다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository();

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _pickEmotionAndSubmit(tester);

    expect(repository.callLog, [
      'saveHtpReflection(91)',
      'stepsNext(UPLOAD)',
      'complete(91)',
    ]);
    // HTP 흐름에서 Drawing Session Reflection은 절대 호출하지 않는다.
    expect(repository.drawingSessionReflectionCalls, 0);
    expect(find.text('activity-complete'), findsOneWidget);
  });

  testWidgets('PERSON skip도 빈 감정 Reflection → steps/next → complete 순서를 유지한다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository();

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _skipAndSubmit(tester);

    expect(repository.lastReflection?.selectedEmotions, isEmpty);
    expect(repository.lastReflection?.expressedEmotionText, isNull);
    expect(repository.lastReflection?.skipped, isTrue);
    expect(repository.callLog, [
      'saveHtpReflection(91)',
      'stepsNext(UPLOAD)',
      'complete(91)',
    ]);
    expect(repository.drawingSessionReflectionCalls, 0);
    expect(find.text('activity-complete'), findsOneWidget);
  });

  testWidgets('steps/next에 세션의 실제 inputMethod를 전달한다(CANVAS 하드코딩 없음)', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository();

    await _pumpPersonEmotionScreen(
      tester,
      repository: repository,
      inputMethod: 'UPLOAD',
    );
    await _pickEmotionAndSubmit(tester);

    expect(repository.stepInputMethods, ['UPLOAD']);
  });

  testWidgets('Reflection이 실패하면 steps/next와 complete를 호출하지 않는다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository(failReflectionOnce: true);

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _pickEmotionAndSubmit(tester);

    expect(repository.callLog, ['saveHtpReflection(91)']);
    expect(repository.stepCalls, 0);
    expect(repository.completeCalls, 0);
    // 완료 화면으로 넘어가지 않고 감정 화면에 머문다.
    expect(find.text('activity-complete'), findsNothing);
  });

  testWidgets('complete만 실패한 재시도는 Reflection·steps/next를 다시 부르지 않는다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository(failCompleteOnce: true);

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _pickEmotionAndSubmit(tester);

    // 1차: Reflection·steps/next는 성공했고 complete만 실패했다.
    expect(repository.reflectionCalls, 1);
    expect(repository.stepCalls, 1);
    expect(repository.completeCalls, 1);
    expect(find.text('activity-complete'), findsNothing);

    // 재시도 — complete만 다시 나가야 한다.
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(repository.reflectionCalls, 1);
    expect(repository.stepCalls, 1);
    expect(repository.completeCalls, 2);
    // complete 재시도는 같은 Key를 재사용한다.
    expect(repository.completeKeys.first, repository.completeKeys.last);
    expect(find.text('activity-complete'), findsOneWidget);
  });

  testWidgets('PERSON skip complete 재시도는 Reflection·step과 기존 Key를 재사용한다', (
    tester,
  ) async {
    final repository = _RecordingHtpRepository(failCompleteOnce: true);

    await _pumpPersonEmotionScreen(tester, repository: repository);
    await _skipAndSubmit(tester);

    expect(repository.reflectionCalls, 1);
    expect(repository.stepCalls, 1);
    expect(repository.completeCalls, 1);
    expect(find.text('activity-complete'), findsNothing);

    await _skipAndSubmit(tester);

    expect(repository.reflectionCalls, 1);
    expect(repository.stepCalls, 1);
    expect(repository.completeCalls, 2);
    expect(repository.stepKeys, hasLength(1));
    expect(repository.completeKeys.first, repository.completeKeys.last);
    expect(repository.lastReflection?.selectedEmotions, isEmpty);
    expect(repository.lastReflection?.skipped, isTrue);
    expect(find.text('activity-complete'), findsOneWidget);
  });
}

final class _PreviewActivityRepository implements ActivityRepository {
  const _PreviewActivityRepository();

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async => ApiPage(
    content: [
      ActivitySummaryDto(
        activityId: 44,
        title: 'HTP',
        drawingType: const ActivityDrawingTypeDto(code: 'HTP', name: 'HTP'),
        inputMethod: 'UPLOAD',
        sessionStatus: 'REFLECTION',
        selectedEmotions: const [],
        thumbnailUrl: null,
        analysisStatus: null,
        report: null,
        startedAt: '2026-08-03T00:00:00Z',
        completedAt: null,
        activityKind: 'HTP',
        htpAssessmentId: 91,
        htpStatus: 'IN_PROGRESS',
        htpDrawings: const [
          HtpActivityDrawingDto(
            drawingSubject: 'HOUSE',
            drawingSessionId: 42,
            thumbnailUrl: '/api/v1/house',
          ),
          HtpActivityDrawingDto(
            drawingSubject: 'TREE',
            drawingSessionId: 43,
            thumbnailUrl: '/api/v1/tree',
          ),
          HtpActivityDrawingDto(
            drawingSubject: 'PERSON',
            drawingSessionId: 44,
            thumbnailUrl: '/api/v1/person',
          ),
        ],
      ),
    ],
    page: 0,
    size: 20,
    totalElements: 1,
    totalPages: 1,
    hasNext: false,
  );

  @override
  Future<Uint8List> downloadImage(String url) async =>
      Uint8List.fromList(_personFinalImage.bytes);

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();
}

final class _RecordingHtpRepository
    implements DrawingRepository, HtpDrawingRepository {
  _RecordingHtpRepository({
    this.failReflectionOnce = false,
    this.failCompleteOnce = false,
  });

  bool failReflectionOnce;
  bool failCompleteOnce;

  final List<String> callLog = [];
  final List<String> stepInputMethods = [];
  final List<String> stepKeys = [];
  final List<String> completeKeys = [];
  int reflectionCalls = 0;
  int stepCalls = 0;
  int completeCalls = 0;
  int drawingSessionReflectionCalls = 0;
  SaveDrawingReflectionRequestDto? lastReflection;

  @override
  Future<void> saveHtpReflection(
    int assessmentId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    reflectionCalls += 1;
    lastReflection = request;
    callLog.add('saveHtpReflection($assessmentId)');
    if (failReflectionOnce) {
      failReflectionOnce = false;
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
  }

  @override
  Future<HtpAssessmentDto> moveToNextHtpStep(
    int assessmentId, {
    required String inputMethod,
    required String idempotencyKey,
  }) async {
    // Reflection보다 먼저 불리면 계약 위반이다.
    if (reflectionCalls == 0) {
      throw StateError('steps/next가 HTP Reflection보다 먼저 호출됐다.');
    }
    stepCalls += 1;
    stepInputMethods.add(inputMethod);
    stepKeys.add(idempotencyKey);
    callLog.add('stepsNext($inputMethod)');
    return HtpAssessmentDto(
      htpAssessmentId: assessmentId,
      status: 'IN_PROGRESS',
      expiresAt: '2026-08-01T00:00:00Z',
      currentStep: const HtpAssessmentStepDto(
        stepOrder: 3,
        drawingSubject: 'PERSON',
        drawingSessionId: 44,
        sessionStatus: 'COMPLETED',
        currentStage: 'COMPLETED',
      ),
      allStepsCompleted: true,
    );
  }

  @override
  Future<void> completeHtpAssessment(
    int assessmentId, {
    required String idempotencyKey,
  }) async {
    completeCalls += 1;
    completeKeys.add(idempotencyKey);
    callLog.add('complete($assessmentId)');
    if (failCompleteOnce) {
      failCompleteOnce = false;
      throw const ApiTransportFailure(type: ApiTransportFailureType.connection);
    }
  }

  /// HTP 흐름에서 호출되면 안 되는 세션 단위 Reflection.
  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    drawingSessionReflectionCalls += 1;
    throw StateError('HTP 흐름에서 Drawing Session Reflection을 부르면 안 된다.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
