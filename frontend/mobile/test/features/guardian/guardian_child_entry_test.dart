import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('로그아웃하면 선택 아동을 초기화하고 로그인 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('child-7')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('logout-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃').last);
    await tester.pumpAndSettle();

    expect(find.text('그림과 대화로\n아이의 마음을 만나봐요'), findsOneWidget);
  });

  test('보호자 선택 상태를 초기화한다', () async {
    final controller = GuardianChildController(
      _FakeChildRepository(children: _children),
    );
    await controller.loadChildren();
    controller.selectChild(_children.first);

    expect(controller.selectedChildId, _children.first.childId);
    controller.clearSelection();

    expect(controller.selectedChild, isNull);
    controller.dispose();
  });

  test('로그아웃하면 아동 목록과 선택 및 등록 상태를 모두 초기화한다', () async {
    final controller = GuardianChildController(
      _FakeChildRepository(children: _children),
    );
    await controller.loadChildren();
    controller.selectChild(_children.first);

    controller.clear();

    expect(controller.status, ChildListStatus.idle);
    expect(controller.children, isEmpty);
    expect(controller.selectedChild, isNull);
    expect(controller.registrationStatus, ChildRegistrationStatus.idle);
    expect(controller.registrationError, isNull);
    controller.dispose();
  });

  testWidgets('Child 목록 Loading 상태를 표시한다', (tester) async {
    final completer = Completer<List<ChildSummaryDto>>();
    final repository = _FakeChildRepository(pending: completer);

    await tester.pumpWidget(DodamApp(childRepository: repository));

    expect(find.byKey(const ValueKey('child-list-loading')), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('Child 목록 Error에서 Retry하면 다시 조회한다', (tester) async {
    final repository = _FakeChildRepository(error: StateError('network'));
    await tester.pumpWidget(DodamApp(childRepository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-error')), findsOneWidget);
    repository
      ..error = null
      ..children = _children;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.getChildrenCalls, 2);
    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
  });

  testWidgets('Child 목록 Empty 상태를 표시한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: const [])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-empty')), findsOneWidget);
  });

  testWidgets('Child 목록 Success와 실제 DTO 정보를 표시한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
    expect(find.text('도담이'), findsWidgets);
    expect(find.text('봄이'), findsOneWidget);
    expect(find.textContaining('활동 12회'), findsOneWidget);
  });

  testWidgets('선택된 childId를 유지해 해당 아동 모드로 진입한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('child-7')));
    await tester.pump();
    await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
    await tester.pumpAndSettle();

    expect(find.text('봄이, 오늘은 무엇을 그려 볼까?'), findsOneWidget);
    expect(find.byKey(const ValueKey('draw-action')), findsOneWidget);
  });

  testWidgets('선택된 아동의 그림 활동 시작 버튼은 Drawing placeholder로 연결된다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pump();
    await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
    await tester.pumpAndSettle();

    await _tapAfterScroll(tester, const ValueKey('draw-action'));
    await tester.pumpAndSettle();

    expect(find.text('그림 활동'), findsWidgets);
  });

  testWidgets('활성 그림 세션이 있으면 새로 만들지 않고 기존 sessionId로 재개한다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(activeSessionId: 812);
    await _pumpChildHome(tester, drawingRepository);

    await _tapAfterScroll(tester, const ValueKey('draw-action'));
    await tester.pumpAndSettle();

    expect(drawingRepository.createCalls, 0);
    expect(drawingRepository.getTypesChildId, isNull);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('실제 앱 진입 흐름에서 생성한 세션으로 완료부터 보호자 홈까지 이어진다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(sessionId: 731);
    await tester.pumpWidget(
      DodamApp(
        childRepository: _FakeChildRepository(children: _children),
        drawingRepository: drawingRepository,
        drawingCompletionSnapshotProvider: () async => _png,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pump();
    await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
    await tester.pumpAndSettle();

    await _tapAfterScroll(tester, const ValueKey('draw-action'));
    await tester.pumpAndSettle();

    expect(drawingRepository.getTypesChildId, 3);
    expect(drawingRepository.createCalls, 1);
    expect(drawingRepository.createRequest?.childId, 3);
    expect(drawingRepository.createRequest?.drawingTypeId, 77);
    expect(drawingRepository.createRequest?.inputMethod, 'CANVAS');
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);

    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-canvas')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(30, 20));
    await gesture.up();
    await tester.pump();
    final complete = find.byKey(const ValueKey('drawing-complete'));
    await tester.ensureVisible(complete);
    await tester.pump();
    await tester.tap(complete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 그렸어요'));
    for (
      var attempt = 0;
      attempt < 30 && drawingRepository.completeSessionId == null;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(drawingRepository.completeSessionId, 731);
    await tester.pumpAndSettle();
    expect(find.text('내 마음 고르기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('emotion-기쁨')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('emotion-submit')));
    await tester.pumpAndSettle();

    expect(drawingRepository.reflectionSessionId, 731);
    expect(find.text('그림 활동을 모두 마쳤어요!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guardian-handoff')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('보호자 홈'), findsWidgets);
    expect(find.text('내 마음 고르기'), findsNothing);
  });

  testWidgets('세션 생성 실패 시 Drawing으로 이동하지 않고 다시 시도할 수 있다', (tester) async {
    final drawingRepository = _TrackingDrawingRepository(
      createError: StateError('create failed'),
    );
    await _pumpChildHome(tester, drawingRepository);

    await _tapAfterScroll(tester, const ValueKey('draw-action'));
    await tester.pumpAndSettle();

    expect(drawingRepository.createCalls, 1);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsNothing);
    expect(find.textContaining('그림 활동을 시작하지 못했어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('draw-action')), findsOneWidget);
  });

  testWidgets('활동 시작 연속 탭은 DrawingSession을 중복 생성하지 않는다', (tester) async {
    final pending = Completer<DrawingSessionDto>();
    final drawingRepository = _TrackingDrawingRepository(pending: pending);
    await _pumpChildHome(tester, drawingRepository);

    final action = find.byKey(const ValueKey('draw-action'));
    await _tapAfterScroll(tester, const ValueKey('draw-action'));
    await tester.pump();
    await tester.tap(action);
    await tester.pump();

    expect(drawingRepository.createCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    pending.complete(drawingRepository.session());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
  });

  testWidgets('아동 모드에는 보호자 전용 요약과 리포트 정보가 노출되지 않는다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pump();
    await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
    await tester.pumpAndSettle();

    expect(find.text('월간 활동 요약'), findsNothing);
    expect(find.text('관찰 리포트'), findsNothing);
    expect(find.textContaining('위험'), findsNothing);
    expect(find.textContaining('분석 상세'), findsNothing);
  });

  testWidgets('childId가 없는 직접 아동 모드 접근은 보호한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(
        childRepository: _FakeChildRepository(children: _children),
        initialRoute: AppRoutes.childModeHome('7'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('선택된 아동이 없어요'), findsOneWidget);
    expect(find.text('봄이, 오늘은 무엇을 그려 볼까?'), findsNothing);
  });
}

Future<void> _tapAfterScroll(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await tester.tap(target);
}

Future<void> _pumpChildHome(
  WidgetTester tester,
  DrawingRepository drawingRepository,
) async {
  await tester.pumpWidget(
    DodamApp(
      childRepository: _FakeChildRepository(children: _children),
      drawingRepository: drawingRepository,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('child-3')));
  await tester.pump();
  await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
  await tester.pumpAndSettle();
}

const _children = [
  ChildSummaryDto(
    childId: 3,
    nickname: '도담이',
    birthDate: '2019-03-14',
    age: 7,
    profileImageUrl: null,
    preferredCharacter: 'BEAR',
    questionDifficulty: 'PRESCHOOL',
    tutorialStatus: 'COMPLETED',
    relationshipType: 'MOTHER',
    recentActivity: ChildRecentActivityDto(
      lastActivityAt: '2026-07-20T08:15:00Z',
      totalActivityCount: 12,
    ),
  ),
  ChildSummaryDto(
    childId: 7,
    nickname: '봄이',
    birthDate: '2016-11-02',
    age: 9,
    profileImageUrl: null,
    preferredCharacter: 'RABBIT',
    questionDifficulty: 'ELEMENTARY',
    tutorialStatus: 'NOT_STARTED',
    relationshipType: 'MOTHER',
    recentActivity: ChildRecentActivityDto(
      lastActivityAt: null,
      totalActivityCount: 0,
    ),
  ),
];

const _png = BinaryUploadDto(
  bytes: [137, 80, 78, 71],
  fileName: 'final.png',
  mimeType: 'image/png',
);

final class _FakeChildRepository implements ChildRepository {
  _FakeChildRepository({this.children = const [], this.error, this.pending});

  List<ChildSummaryDto> children;
  Object? error;
  Completer<List<ChildSummaryDto>>? pending;
  int getChildrenCalls = 0;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    getChildrenCalls += 1;
    if (pending case final pending?) return pending.future;
    if (error case final error?) throw error;
    return children;
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();
  @override
  Future<void> deleteChild(int childId, {bool cascade = true}) =>
      throw UnimplementedError();
  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();
  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();
  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}

final class _TrackingDrawingRepository implements DrawingRepository {
  _TrackingDrawingRepository({
    this.sessionId = 731,
    this.activeSessionId,
    this.createError,
    this.pending,
  });

  final int sessionId;
  final int? activeSessionId;
  final Object? createError;
  final Completer<DrawingSessionDto>? pending;
  int createCalls = 0;
  int? getTypesChildId;
  int? completeSessionId;
  int? reflectionSessionId;
  CreateDrawingSessionRequestDto? createRequest;

  DrawingSessionDto session() => DrawingSessionDto.fromJson({
    'drawingSessionId': sessionId,
    'childId': 3,
    'drawingType': {'drawingTypeId': 77, 'code': 'FREE', 'name': '자유화'},
    'inputMethod': 'CANVAS',
    'title': null,
    'sessionStatus': 'DRAWING',
    'currentStage': 'DRAWING',
    'selectedEmotions': null,
    'expressedEmotionText': null,
    'startedAt': '2026-07-22T00:00:00Z',
    'completedAt': null,
    'conversation': null,
    'latestAnalysis': null,
    'assets': <Object>[],
  });

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async {
    getTypesChildId = childId;
    return const ApiPage(
      content: [
        DrawingTypeDto(
          drawingTypeId: 77,
          code: 'FREE',
          name: '자유화',
          activityCategory: 'GENERAL',
          selectableBy: 'GUARDIAN_OR_CHILD',
          recommendedAgeMin: null,
          recommendedAgeMax: null,
          guideText: '자유롭게 그려 보세요.',
          displayOrder: 1,
        ),
      ],
      page: 0,
      size: 1,
      totalElements: 1,
      totalPages: 1,
      hasNext: false,
    );
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    createCalls += 1;
    createRequest = request;
    if (createError case final error?) throw error;
    return pending?.future ?? session();
  }

  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) async => null;
  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async {
    final id = activeSessionId;
    if (id == null) return null;
    return ActiveDrawingSessionDto(
      drawingSessionId: id,
      childId: childId,
      drawingType: const DrawingTypeSummaryDto(
        drawingTypeId: 77,
        code: 'FREE',
        name: '자유화',
      ),
      inputMethod: 'CANVAS',
      sessionStatus: 'DRAWING',
      currentStage: 'DRAWING',
      startedAt: '2026-07-22T00:00:00Z',
      latestDraft: null,
    );
  }

  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) =>
      throw UnimplementedError();

  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) async => StrokeBatchResponseDto(
    batchId: 1,
    batchSequence: request.batchSequence,
    acceptedEventCount: request.events.length,
    lastEventSequence: request.lastEventSequence,
    receivedAt: '2026-07-22T00:00:00Z',
  );

  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) async {
    completeSessionId = sessionId;
    return DrawingStageCompleteResponseDto.fromJson({
      'drawingSessionId': sessionId,
      'finalAssetId': 900,
      'sessionStatus': 'IN_PROGRESS',
      'currentStage': 'CONVERSING',
      'analysis': {
        'analysisId': 901,
        'analysisType': 'INTERMEDIATE',
        'status': 'SUCCEEDED',
      },
      'nextAction': 'SELECT_EMOTION',
    });
  }

  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async => reflectionSessionId = sessionId;

  @override
  Future<DrawingActivityCompleteResponseDto> completeActivity(
    int sessionId, {
    required DrawingActivityCompleteRequestDto request,
    required String idempotencyKey,
  }) async => DrawingActivityCompleteResponseDto(
    drawingSessionId: sessionId,
    sessionStatus: 'IN_PROGRESS',
    currentStage: 'REPORTING',
    analysisId: 902,
    analysisStatus: 'PENDING',
    reportId: 903,
    reportStatus: 'GENERATING',
  );

  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState,
  ) async => DraftSaveResponseDto(
    drawingAssetId: 1,
    assetVersion: 1,
    lastEventSequence: canvasState.lastEventSequence,
    savedAt: '2026-07-22T00:00:00Z',
    expiresAt: null,
  );

  @override
  Future<void> deleteDraft(int sessionId) async {}
  @override
  Future<DrawingSessionDto> getSession(int sessionId) async => session();
  @override
  Future<DrawingSessionCompletionStatusDto> getSessionCompletionStatus(
    int sessionId,
  ) async => DrawingSessionCompletionStatusDto(
    drawingSessionId: sessionId,
    sessionStatus: 'COMPLETED',
    currentStage: 'COMPLETED',
    latestAnalysis: const DrawingSessionLatestAnalysisDto(
      drawingAnalysisId: 902,
      analysisScope: 'FINAL',
      analysisType: 'ACTIVITY_REPORT',
      analysisStatus: 'SUCCESS',
    ),
    reportId: 903,
  );
  @override
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  }) => throw UnimplementedError();
}
