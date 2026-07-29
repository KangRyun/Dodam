import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/drawing/application/drawing_session_start_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('활성 그림 세션이 있으면 새 세션을 만들지 않고 재개한다', () async {
    final repository = _SessionStartRepository(
      activeSessions: [_activeSession(81)],
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    final resolution = await controller.resolveSession(childId: 3);

    expect(resolution.sessionId, 81);
    expect(resolution.currentStage, 'DRAWING');
    expect(resolution.isDrawingStage, isTrue);
    expect(repository.getDrawingTypesCalls, 0);
    expect(repository.createCalls, 0);
  });

  test('활성 세션이 대화 단계면 그림 단계가 아님을 알린다', () async {
    final repository = _SessionStartRepository(
      activeSessions: [_activeSession(84, currentStage: 'CONVERSING')],
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    final resolution = await controller.resolveSession(childId: 3);

    expect(resolution.sessionId, 84);
    expect(resolution.currentStage, 'CONVERSING');
    expect(resolution.isDrawingStage, isFalse);
    expect(repository.createCalls, 0);
  });

  test('임시 저장본이나 그림 완료 단계가 있을 때만 선택 팝업 대상이다', () {
    final controller = DrawingSessionStartController(
      repository: _SessionStartRepository(activeSessions: const [null]),
    );

    expect(controller.hasSavedDrawing(_activeSession(81)), isFalse);
    expect(
      controller.hasSavedDrawing(_activeSession(82, hasDraft: true)),
      isTrue,
    );
    expect(
      controller.hasSavedDrawing(
        _activeSession(83, currentStage: 'CONVERSING'),
      ),
      isTrue,
    );
  });

  test('새 활동은 기존 세션을 삭제하지 않고 서버의 원자적 교체 옵션으로 생성한다', () async {
    final repository = _SessionStartRepository(
      activeSessions: const [null],
      createdSessionId: 91,
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 29, 1),
    );

    final resolution = await controller.createSelectedSession(
      childId: 3,
      drawingTypeId: 11,
      replaceActive: true,
    );

    expect(repository.deletedSessionIds, isEmpty);
    expect(repository.createCalls, 1);
    expect(repository.createRequest?.replaceActive, isTrue);
    expect(resolution.sessionId, 91);
    expect(resolution.isDrawingStage, isTrue);
  });

  test('HTP 선택은 HOUSE 세션과 활동 컨텍스트를 함께 반환한다', () async {
    final repository = _SessionStartRepository(activeSessions: const [null]);
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 29, 1),
    );

    final resolution = await controller.createHtpAssessment(
      childId: 3,
      replaceActive: true,
    );

    expect(repository.startHtpRequest?.replaceActive, isTrue);
    expect(resolution.sessionId, 201);
    expect(resolution.activityContext.isHtp, isTrue);
    expect(resolution.activityContext.stepOrder, 1);
    expect(resolution.activityContext.drawingSubject, 'HOUSE');
  });

  test('활성 그림 세션이 없으면 첫 번째 그림 유형으로 새 세션을 만든다', () async {
    final repository = _SessionStartRepository(
      activeSessions: [null],
      createdSessionId: 82,
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    final resolution = await controller.resolveSession(childId: 3);

    expect(resolution.sessionId, 82);
    expect(resolution.isDrawingStage, isTrue);
    expect(repository.getDrawingTypesCalls, 1);
    expect(repository.createCalls, 1);
    expect(repository.createRequest?.drawingTypeId, 11);
    expect(
      repository.createRequest?.clientStartedAt,
      '2026-07-26T01:00:00.000Z',
    );
  });

  test('세션 생성 경쟁으로 409가 발생하면 활성 세션을 한 번 재조회한다', () async {
    final repository = _SessionStartRepository(
      activeSessions: [null, _activeSession(83)],
      createFailure: _activeSessionExistsFailure,
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    final resolution = await controller.resolveSession(childId: 3);

    expect(resolution.sessionId, 83);
    expect(repository.getActiveSessionCalls, 2);
    expect(repository.createCalls, 1);
  });

  test('활성 세션 충돌 외의 생성 오류는 그대로 전달한다', () async {
    final failure = ApiResponseFailure(
      statusCode: 409,
      error: ApiError(
        timestamp: '2026-07-26T01:00:00Z',
        path: '/api/v1/drawing-sessions',
        code: 'DRAWING_409_002',
        message: '멱등성 키가 충돌했습니다.',
      ),
    );
    final repository = _SessionStartRepository(
      activeSessions: [null],
      createFailure: failure,
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    await expectLater(
      controller.resolveSession(childId: 3),
      throwsA(same(failure)),
    );
    expect(repository.getActiveSessionCalls, 1);
  });

  test('선택 가능한 그림 유형이 없으면 세션 생성 전에 실패한다', () async {
    final repository = _SessionStartRepository(
      activeSessions: [null],
      drawingTypes: const [],
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    await expectLater(
      controller.resolveSession(childId: 3),
      throwsA(isA<StateError>()),
    );
    expect(repository.createCalls, 0);
  });

  test('활성 세션이 없으면 홈에서 지정한 그림 유형으로 세션을 만든다', () async {
    final repository = _SessionStartRepository(activeSessions: [null]);
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    final resolution = await controller.resolveSession(
      childId: 3,
      drawingTypeId: 12,
    );

    expect(resolution.sessionId, 82);
    expect(repository.createRequest?.drawingTypeId, 12);
  });

  test('지정한 그림 유형이 목록에 없으면 첫 번째 유형으로 되돌아간다', () async {
    final repository = _SessionStartRepository(activeSessions: [null]);
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    final resolution = await controller.resolveSession(
      childId: 3,
      drawingTypeId: 999,
    );

    expect(resolution.sessionId, 82);
    expect(repository.createRequest?.drawingTypeId, 11);
  });

  test('지정한 그림 유형이 있어도 활성 세션을 먼저 재개한다', () async {
    final repository = _SessionStartRepository(
      activeSessions: [_activeSession(81)],
    );
    final controller = DrawingSessionStartController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 26, 1),
    );

    final resolution = await controller.resolveSession(
      childId: 3,
      drawingTypeId: 12,
    );

    expect(resolution.sessionId, 81);
    expect(repository.createCalls, 0);
    expect(repository.getDrawingTypesCalls, 0);
  });
}

final _activeSessionExistsFailure = ApiResponseFailure(
  statusCode: 409,
  error: ApiError(
    timestamp: '2026-07-26T01:00:00Z',
    path: '/api/v1/drawing-sessions',
    code: 'DRAWING_409_001',
    message: '진행 중인 그림 활동이 이미 존재합니다.',
  ),
);

ActiveDrawingSessionDto _activeSession(
  int id, {
  String currentStage = 'DRAWING',
  bool hasDraft = false,
}) => ActiveDrawingSessionDto(
  drawingSessionId: id,
  childId: 3,
  drawingType: const DrawingTypeSummaryDto(
    drawingTypeId: 11,
    code: 'FREE_DRAWING',
    name: '자유 그리기',
  ),
  inputMethod: 'CANVAS',
  sessionStatus: 'IN_PROGRESS',
  currentStage: currentStage,
  startedAt: '2026-07-26T01:00:00Z',
  latestDraft: hasDraft
      ? const ActiveDrawingDraftDto(
          drawingAssetId: 301,
          assetVersion: 2,
          lastEventSequence: 18,
          savedAt: '2026-07-29T01:00:00Z',
        )
      : null,
);

final class _SessionStartRepository
    implements
        DrawingRepository,
        HtpDrawingRepository,
        DrawingSessionDiscarder {
  _SessionStartRepository({
    required this.activeSessions,
    this.createdSessionId = 82,
    this.createFailure,
    this.drawingTypes = const [
      DrawingTypeDto(
        drawingTypeId: 12,
        code: 'SECOND',
        name: '두 번째',
        activityCategory: 'GENERAL',
        selectableBy: 'BOTH',
        recommendedAgeMin: null,
        recommendedAgeMax: null,
        guideText: null,
        displayOrder: 2,
      ),
      DrawingTypeDto(
        drawingTypeId: 11,
        code: 'FIRST',
        name: '첫 번째',
        activityCategory: 'GENERAL',
        selectableBy: 'BOTH',
        recommendedAgeMin: null,
        recommendedAgeMax: null,
        guideText: null,
        displayOrder: 1,
      ),
    ],
  });

  final List<ActiveDrawingSessionDto?> activeSessions;
  final int createdSessionId;
  final Object? createFailure;
  final List<DrawingTypeDto> drawingTypes;
  int getActiveSessionCalls = 0;
  int getDrawingTypesCalls = 0;
  int createCalls = 0;
  final List<int> deletedSessionIds = [];
  CreateDrawingSessionRequestDto? createRequest;
  StartHtpAssessmentRequestDto? startHtpRequest;

  @override
  Future<HtpAssessmentDto> startHtpAssessment(
    StartHtpAssessmentRequestDto request,
  ) async {
    startHtpRequest = request;
    return const HtpAssessmentDto(
      htpAssessmentId: 91,
      status: 'IN_PROGRESS',
      expiresAt: '2026-07-30T01:00:00Z',
      currentStep: HtpAssessmentStepDto(
        stepOrder: 1,
        drawingSubject: 'HOUSE',
        drawingSessionId: 201,
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'DRAWING',
      ),
      allStepsCompleted: false,
    );
  }

  @override
  Future<void> deleteSession(int sessionId) async {
    deletedSessionIds.add(sessionId);
  }

  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) async =>
      activeSessions[getActiveSessionCalls++];

  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) async {
    getDrawingTypesCalls += 1;
    return ApiPage(
      content: drawingTypes,
      page: 0,
      size: drawingTypes.length,
      totalElements: drawingTypes.length,
      totalPages: drawingTypes.isEmpty ? 0 : 1,
      hasNext: false,
    );
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) async {
    createCalls += 1;
    createRequest = request;
    final failure = createFailure;
    if (failure != null) throw failure;
    return DrawingSessionDto(
      drawingSessionId: createdSessionId,
      childId: request.childId,
      drawingType: const DrawingTypeSummaryDto(
        drawingTypeId: 11,
        code: 'FIRST',
        name: '첫 번째',
      ),
      inputMethod: request.inputMethod,
      title: null,
      sessionStatus: 'DRAWING',
      currentStage: 'DRAWING',
      selectedEmotions: null,
      expressedEmotionText: null,
      startedAt: request.clientStartedAt,
      completedAt: null,
      conversation: null,
      latestAnalysis: null,
      assets: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
