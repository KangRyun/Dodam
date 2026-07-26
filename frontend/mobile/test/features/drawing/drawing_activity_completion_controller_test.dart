import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/core/network/api_failure.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/application/drawing_activity_completion_controller.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/drawing/domain/repositories/drawing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Conversation End 다음 회고 저장과 Activity Complete를 순서대로 처리한다', () async {
    final calls = <String>[];
    final conversation = _RecordingConversationEndRepository(calls);
    final drawing = _RecordingDrawingRepository(calls: calls, preflight: false);
    final keys = ['conversation-key', 'activity-key'].iterator;
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: 20,
      conversationAlreadyEnded: false,
      conversationEndRepository: conversation,
      idempotencyKeyProvider: () {
        keys.moveNext();
        return keys.current;
      },
      pollInterval: Duration.zero,
    );

    final completed = await controller.submit(
      reflection: _reflection,
      lastQuestionMessageId: 31,
    );

    expect(completed, isTrue);
    expect(calls, ['end', 'reflection', 'complete', 'status']);
    expect(conversation.request?.reason, ConversationEndReason.childRequest);
    expect(conversation.request?.lastQuestionMessageId, 31);
    expect(drawing.completeRequest?.conversationSkipped, isFalse);
    expect(drawing.completeRequest?.requestReport, isTrue);
    expect(conversation.keys.single, 'conversation-key');
    expect(drawing.completeKeys.single, 'activity-key');
    expect(conversation.keys.single, isNot(drawing.completeKeys.single));
    expect(controller.status, DrawingActivityCompletionStatus.completed);
    expect(controller.analysisStatus, 'SUCCESS');
    expect(controller.reportId, 501);
  });

  test('대화가 생성되지 않았으면 End를 생략하고 conversationSkipped를 보낸다', () async {
    final calls = <String>[];
    final drawing = _RecordingDrawingRepository(calls: calls);
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      pollInterval: Duration.zero,
    );

    final completed = await controller.submit(
      reflection: _reflection,
      lastQuestionMessageId: null,
    );

    expect(completed, isTrue);
    expect(calls, ['status', 'reflection', 'complete', 'status']);
    expect(drawing.completeRequest?.conversationSkipped, isTrue);
  });

  test('Resume 인자에 conversationId가 없어도 세션 상세에서 대화를 확인한다', () async {
    final calls = <String>[];
    final conversation = _RecordingConversationEndRepository(calls);
    final drawing = _RecordingDrawingRepository(
      calls: calls,
      existingConversationId: 20,
    );
    final keys = ['conversation-key', 'activity-key'].iterator;
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: conversation,
      idempotencyKeyProvider: () {
        keys.moveNext();
        return keys.current;
      },
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isTrue,
    );
    expect(calls, ['status', 'end', 'reflection', 'complete', 'status']);
    expect(drawing.completeRequest?.conversationSkipped, isFalse);
  });

  test('Conversation End 실패 시 회고와 Activity Complete를 호출하지 않는다', () async {
    final calls = <String>[];
    final conversation = _RecordingConversationEndRepository(
      calls,
      shouldFail: true,
    );
    final drawing = _RecordingDrawingRepository(calls: calls);
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: 20,
      conversationAlreadyEnded: false,
      conversationEndRepository: conversation,
      idempotencyKeyProvider: () => 'conversation-key',
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: 31,
      ),
      isFalse,
    );
    expect(calls, ['end']);
    expect(controller.status, DrawingActivityCompletionStatus.failed);
  });

  test('회고 저장 실패 시 Activity Complete를 호출하지 않는다', () async {
    final calls = <String>[];
    final drawing = _RecordingDrawingRepository(
      calls: calls,
      reflectionFailure: StateError('reflection failed'),
    );
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isFalse,
    );
    expect(calls, ['status', 'reflection']);
  });

  test('Conversation End 실패 후 수정한 최신 감정으로 Reflection을 저장한다', () async {
    final calls = <String>[];
    final conversation = _RecordingConversationEndRepository(
      calls,
      failures: 1,
    );
    final drawing = _RecordingDrawingRepository(calls: calls, preflight: false);
    final keys = ['conversation-key', 'activity-key'].iterator;
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: 20,
      conversationAlreadyEnded: false,
      conversationEndRepository: conversation,
      idempotencyKeyProvider: () {
        keys.moveNext();
        return keys.current;
      },
      pollInterval: Duration.zero,
    );
    const changedReflection = SaveDrawingReflectionRequestDto(
      title: '바꾼 제목',
      selectedEmotions: [DrawingEmotionType.calm],
      expressedEmotionText: null,
      skipped: false,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: 31,
      ),
      isFalse,
    );
    expect(controller.reflectionInputLocked, isFalse);
    expect(
      await controller.submit(
        reflection: changedReflection,
        lastQuestionMessageId: 99,
      ),
      isTrue,
    );

    expect(conversation.keys, ['conversation-key', 'conversation-key']);
    expect(
      conversation.requests.map((request) => request.toJson()),
      everyElement({'reason': 'CHILD_REQUEST', 'lastQuestionMessageId': 31}),
    );
    expect(drawing.reflectionRequests, [changedReflection]);
  });

  test('이전 화면의 불확실한 Conversation End Key와 Body를 그대로 이어받는다', () async {
    final calls = <String>[];
    final conversation = _RecordingConversationEndRepository(calls);
    final drawing = _RecordingDrawingRepository(calls: calls, preflight: false);
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: 20,
      conversationAlreadyEnded: false,
      conversationEndRepository: conversation,
      idempotencyKeyProvider: () => 'activity-key',
      previousConversationEndIdempotencyKey: 'existing-end-key',
      previousConversationEndRequest: const ConversationEndRequest(
        reason: ConversationEndReason.childRequest,
        lastQuestionMessageId: 31,
      ),
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: 99,
      ),
      isTrue,
    );
    expect(conversation.keys, ['existing-end-key']);
    expect(conversation.requests.single.toJson(), {
      'reason': 'CHILD_REQUEST',
      'lastQuestionMessageId': 31,
    });
  });

  test('Reflection 응답 유실 후 같은 Body로 재시도한다', () async {
    final drawing = _RecordingDrawingRepository(
      calls: [],
      reflectionFailures: [
        const ApiTransportFailure(type: ApiTransportFailureType.receiveTimeout),
      ],
    );
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isFalse,
    );
    expect(controller.reflectionInputLocked, isTrue);
    expect(
      await controller.submit(
        reflection: const SaveDrawingReflectionRequestDto(
          title: '바뀌면 안 되는 제목',
          selectedEmotions: [DrawingEmotionType.angry],
          expressedEmotionText: null,
          skipped: false,
        ),
        lastQuestionMessageId: null,
      ),
      isTrue,
    );

    expect(drawing.reflectionRequests.length, 2);
    expect(
      drawing.reflectionRequests.map((request) => request.toJson()),
      everyElement(_reflection.toJson()),
    );
  });

  test('Reflection 400 응답 후 snapshot을 해제하고 최신 입력을 사용한다', () async {
    final drawing = _RecordingDrawingRepository(
      calls: [],
      reflectionFailures: [
        const ApiResponseFailure(statusCode: 400, error: null),
      ],
    );
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      pollInterval: Duration.zero,
    );
    const changedReflection = SaveDrawingReflectionRequestDto(
      title: '수정한 제목',
      selectedEmotions: [DrawingEmotionType.calm],
      expressedEmotionText: null,
      skipped: false,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isFalse,
    );
    expect(controller.reflectionInputLocked, isFalse);
    expect(
      await controller.submit(
        reflection: changedReflection,
        lastQuestionMessageId: null,
      ),
      isTrue,
    );
    expect(drawing.reflectionRequests, [_reflection, changedReflection]);
  });

  test('Reflection 415 응답은 snapshot을 해제해 입력 수정을 허용한다', () async {
    final drawing = _RecordingDrawingRepository(
      calls: [],
      reflectionFailures: [
        const ApiResponseFailure(statusCode: 415, error: null),
      ],
    );
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isFalse,
    );
    expect(controller.reflectionInputLocked, isFalse);
  });

  test('실패 후 재시도는 Activity Complete Key와 Body를 그대로 재사용한다', () async {
    final calls = <String>[];
    final drawing = _RecordingDrawingRepository(
      calls: calls,
      completeFailures: 1,
    );
    var keyCalls = 0;
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () {
        keyCalls += 1;
        return 'activity-key';
      },
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isFalse,
    );
    expect(
      await controller.submit(
        reflection: const SaveDrawingReflectionRequestDto(
          title: '변경된 값',
          selectedEmotions: [],
          expressedEmotionText: null,
          skipped: true,
        ),
        lastQuestionMessageId: null,
      ),
      isTrue,
    );

    expect(drawing.reflectionRequests, [_reflection]);
    expect(drawing.completeKeys, ['activity-key', 'activity-key']);
    expect(
      drawing.completeRequests[0].toJson(),
      drawing.completeRequests[1].toJson(),
    );
    expect(keyCalls, 1);
  });

  test('polling에서 FAILED를 받으면 완료 화면으로 진행하지 않는다', () async {
    final drawing = _RecordingDrawingRepository(
      calls: [],
      terminalSessionStatus: 'FAILED',
      terminalStage: 'REPORTING',
    );
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: null,
      conversationAlreadyEnded: false,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      pollInterval: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isFalse,
    );
    expect(controller.status, DrawingActivityCompletionStatus.failed);
  });

  test('polling transient 오류는 최대 3회 backoff 후 성공할 수 있다', () async {
    final drawing = _RecordingDrawingRepository(
      calls: [],
      preflight: false,
      statusFailures: [
        const ApiTransportFailure(type: ApiTransportFailureType.connection),
        const ApiResponseFailure(statusCode: 503, error: null),
        const ApiResponseFailure(statusCode: 429, error: null),
      ],
    );
    final delays = <Duration>[];
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: 20,
      conversationAlreadyEnded: true,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      delay: (duration) async => delays.add(duration),
      pollInterval: Duration.zero,
      transientPollBackoff: const Duration(milliseconds: 100),
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isTrue,
    );
    expect(drawing.statusCallCount, 4);
    expect(delays, const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 200),
      Duration(milliseconds: 400),
    ]);
  });

  test('polling transient 오류가 3회 재시도를 넘으면 실패한다', () async {
    final drawing = _RecordingDrawingRepository(
      calls: [],
      preflight: false,
      statusFailures: List<Object>.generate(
        4,
        (_) =>
            const ApiTransportFailure(type: ApiTransportFailureType.connection),
      ),
    );
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: 20,
      conversationAlreadyEnded: true,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      delay: (_) async {},
      pollInterval: Duration.zero,
      transientPollBackoff: Duration.zero,
    );

    expect(
      await controller.submit(
        reflection: _reflection,
        lastQuestionMessageId: null,
      ),
      isFalse,
    );
    expect(drawing.statusCallCount, 4);
  });

  test('dispose 후 대기 중인 polling은 추가 GET 없이 종료한다', () async {
    final pollingStarted = Completer<void>();
    final releasePolling = Completer<void>();
    final drawing = _RecordingDrawingRepository(calls: [], preflight: false);
    final controller = DrawingActivityCompletionController(
      drawingRepository: drawing,
      sessionId: 42,
      conversationId: 20,
      conversationAlreadyEnded: true,
      conversationEndRepository: null,
      idempotencyKeyProvider: () => 'activity-key',
      delay: (_) {
        if (!pollingStarted.isCompleted) pollingStarted.complete();
        return releasePolling.future;
      },
      pollInterval: const Duration(seconds: 1),
    );

    final completion = controller.submit(
      reflection: _reflection,
      lastQuestionMessageId: null,
    );
    await pollingStarted.future;
    controller.dispose();
    releasePolling.complete();

    expect(await completion, isFalse);
    expect(drawing.statusCallCount, 0);
  });
}

const _reflection = SaveDrawingReflectionRequestDto(
  title: '우리 가족',
  selectedEmotions: [DrawingEmotionType.happy],
  expressedEmotionText: null,
  skipped: false,
);

final class _RecordingConversationEndRepository
    implements ConversationEndRepository {
  _RecordingConversationEndRepository(
    this.calls, {
    this.shouldFail = false,
    this.failures = 0,
  });

  final List<String> calls;
  final bool shouldFail;
  final int failures;
  final List<String> keys = [];
  final List<ConversationEndRequest> requests = [];
  ConversationEndRequest? request;
  int callCount = 0;

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    calls.add('end');
    callCount += 1;
    keys.add(idempotencyKey);
    this.request = request;
    requests.add(request);
    if (shouldFail || callCount <= failures) throw StateError('end failed');
    return ConversationEndResult(
      conversationId: conversationId,
      conversationStatus: 'COMPLETED',
      completed: true,
      completionReason: request.reason.apiValue,
      completedAt: '2026-07-26T12:00:00',
      nextStage: 'REFLECTION',
    );
  }
}

final class _RecordingDrawingRepository implements DrawingRepository {
  _RecordingDrawingRepository({
    required this.calls,
    this.reflectionFailure,
    List<Object> reflectionFailures = const [],
    this.completeFailures = 0,
    List<Object> statusFailures = const [],
    this.terminalSessionStatus = 'COMPLETED',
    this.terminalStage = 'COMPLETED',
    this.existingConversationId,
    this.preflight = true,
  }) : reflectionFailures = [...reflectionFailures],
       statusFailures = [...statusFailures];

  final List<String> calls;
  final Object? reflectionFailure;
  final List<Object> reflectionFailures;
  final int completeFailures;
  final List<Object> statusFailures;
  final String terminalSessionStatus, terminalStage;
  final int? existingConversationId;
  final bool preflight;
  int completeCallCount = 0;
  int statusCallCount = 0;
  final List<SaveDrawingReflectionRequestDto> reflectionRequests = [];
  final List<DrawingActivityCompleteRequestDto> completeRequests = [];
  final List<String> completeKeys = [];

  DrawingActivityCompleteRequestDto? get completeRequest =>
      completeRequests.lastOrNull;

  @override
  Future<void> saveReflection(
    int sessionId,
    SaveDrawingReflectionRequestDto request,
  ) async {
    calls.add('reflection');
    reflectionRequests.add(request);
    if (reflectionFailures.isNotEmpty) throw reflectionFailures.removeAt(0);
    if (reflectionFailure case final failure?) throw failure;
  }

  @override
  Future<DrawingActivityCompleteResponseDto> completeActivity(
    int sessionId, {
    required DrawingActivityCompleteRequestDto request,
    required String idempotencyKey,
  }) async {
    calls.add('complete');
    completeCallCount += 1;
    completeRequests.add(request);
    completeKeys.add(idempotencyKey);
    if (completeCallCount <= completeFailures) {
      throw StateError('complete failed');
    }
    return DrawingActivityCompleteResponseDto(
      drawingSessionId: sessionId,
      sessionStatus: 'IN_PROGRESS',
      currentStage: 'REPORTING',
      analysisId: 700,
      analysisStatus: 'PENDING',
      reportId: 501,
      reportStatus: 'GENERATING',
    );
  }

  @override
  Future<DrawingSessionCompletionStatusDto> getSessionCompletionStatus(
    int sessionId,
  ) async {
    calls.add('status');
    statusCallCount += 1;
    if (statusFailures.isNotEmpty) throw statusFailures.removeAt(0);
    if (preflight && statusCallCount == 1) {
      return DrawingSessionCompletionStatusDto(
        drawingSessionId: sessionId,
        sessionStatus: 'IN_PROGRESS',
        currentStage: 'CONVERSING',
        latestAnalysis: null,
        reportId: null,
        conversationId: existingConversationId,
      );
    }
    return DrawingSessionCompletionStatusDto(
      drawingSessionId: sessionId,
      sessionStatus: terminalSessionStatus,
      currentStage: terminalStage,
      latestAnalysis: const DrawingSessionLatestAnalysisDto(
        drawingAnalysisId: 700,
        analysisScope: 'FINAL',
        analysisType: 'ACTIVITY_REPORT',
        analysisStatus: 'SUCCESS',
      ),
      reportId: 501,
    );
  }

  @override
  Future<DrawingSessionDto> createSession(
    CreateDrawingSessionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<void> deleteDraft(int sessionId) => throw UnimplementedError();
  @override
  Future<Uint8List> downloadDraftPreview(String previewUrl) =>
      throw UnimplementedError();
  @override
  Future<ActiveDrawingSessionDto?> getActiveSession(int childId) =>
      throw UnimplementedError();
  @override
  Future<DraftRecoveryDto?> getDraft(int sessionId) =>
      throw UnimplementedError();
  @override
  Future<DrawingSessionDto> getSession(int sessionId) =>
      throw UnimplementedError();
  @override
  Future<ApiPage<DrawingTypeDto>> getDrawingTypes({
    required int childId,
    String? category,
    bool activeOnly = true,
  }) => throw UnimplementedError();
  @override
  Future<ObjectDetectionResponseDto> requestObjectDetection(
    int sessionId,
    ObjectDetectionRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DraftSaveResponseDto> saveDraft(
    int sessionId,
    BinaryUploadDto preview,
    DraftCanvasStateDto canvasState,
  ) => throw UnimplementedError();
  @override
  Future<StrokeBatchResponseDto> sendStrokeBatch(
    int sessionId,
    StrokeBatchRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<DrawingStageCompleteResponseDto> completeDrawingStage(
    int sessionId, {
    required BinaryUploadDto finalImage,
    required DrawingCompleteMetadataDto metadata,
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<DrawingUploadResponseDto> uploadDrawing(
    int sessionId,
    BinaryUploadDto image, {
    String? objectCode,
  }) => throw UnimplementedError();
}
