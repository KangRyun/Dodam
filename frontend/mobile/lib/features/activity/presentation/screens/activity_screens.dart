import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/network/api_failure_presentation.dart';
import '../../../../design_system/design_system.dart';
import '../../../drawing/application/activity_completion_controller.dart';
import '../../../drawing/application/drawing_object_detection_controller.dart';
import '../../../drawing/application/drawing_activity_completion_controller.dart';
import '../../../drawing/application/drawing_sync_coordinator.dart';
import '../../../drawing/application/drawing_draft_restore_controller.dart';
import '../../../drawing/application/htp_response_flow_controller.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../../drawing/domain/repositories/drawing_repository.dart';
import '../../../drawing/presentation/models/drawing_stroke.dart';
import '../../../drawing/presentation/widgets/drawing_canvas.dart';
import '../../../conversation/conversation.dart';
import '../../domain/models/activity_conversation_turn.dart';
import '../../domain/repositories/activity_repository.dart';

enum _DrawingCompletePhase {
  strokeFlush,
  canvasCapture,
  request,
  contractValidation,
}

void _debugDrawingCompleteFailure({
  required _DrawingCompletePhase phase,
  required Object error,
  required bool snapshotWasNull,
  required DrawingStageCompleteResponseDto? response,
}) {
  if (!kDebugMode) return;
  final exceptionType = error.runtimeType;
  switch (phase) {
    case _DrawingCompletePhase.strokeFlush:
      debugPrint(
        '[DRAWING_COMPLETE] stroke_flush_failure '
        'exceptionType=$exceptionType',
      );
    case _DrawingCompletePhase.canvasCapture:
      debugPrint(
        '[DRAWING_COMPLETE] canvas_capture_failure '
        'kind=${snapshotWasNull ? 'null' : 'exception'} '
        'exceptionType=$exceptionType',
      );
    case _DrawingCompletePhase.request:
      switch (error) {
        case ApiTransportFailure(:final type):
          debugPrint(
            '[DRAWING_COMPLETE] request_transport_failure '
            'transportType=${type.name} exceptionType=$exceptionType',
          );
        case ApiResponseFailure(:final statusCode, :final error):
          debugPrint(
            '[DRAWING_COMPLETE] http_failure '
            'status=${statusCode ?? 'unknown'} '
            'code=${error?.code ?? 'unknown'} '
            'message=${_safeDrawingCompleteMessage(error?.message)} '
            'exceptionType=$exceptionType',
          );
        default:
          debugPrint(
            '[DRAWING_COMPLETE] response_parse_failure '
            'exceptionType=$exceptionType',
          );
      }
    case _DrawingCompletePhase.contractValidation:
      debugPrint(
        '[DRAWING_COMPLETE] contract_mismatch '
        'currentStage=${response?.currentStage ?? 'unknown'} '
        'nextAction=${response?.nextAction ?? 'unknown'} '
        'exceptionType=$exceptionType',
      );
  }
}

String _safeDrawingCompleteMessage(String? message) {
  if (message == null) return 'unknown';
  final singleLine = message.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (singleLine.length <= 200) return singleLine;
  return '${singleLine.substring(0, 200)}…';
}

String _createIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    required this.childId,
    this.sessionId,
    this.drawingRepository,
    this.syncPolicy = const DrawingSyncPolicy(),
    this.syncCoordinator,
    this.objectDetectionController,
    this.draftRestoreController,
    this.draftImageProviderFactory,
    this.completionSnapshotProvider,
    this.idempotencyKeyProvider,
    this.conversationRepository,
    this.conversationAnswerRepository,
    this.questionSkipRepository,
    this.conversationEndRepository,
    this.questionTtsRepository,
    this.questionAudioPlayerFactory,
    this.voiceRecorder,
    this.microphonePermissionService,
    this.voiceNoSpeechTimeout = const Duration(seconds: 3),
    this.voiceAnswerRepository,
    this.sttResultRepository,
    this.activityRepository,
    this.conversationId,
    this.basisAnalysisId,
    this.resumeConversation = false,
    this.autoRestoreDraft = false,
    this.startFresh = false,
    this.activityContext = const DrawingActivityContextDto.general(),
    this.inputMethod,
    super.key,
  });

  final String childId;
  final int? sessionId;

  /// 이 세션이 실제로 쓰는 입력 방식(`CANVAS`|`UPLOAD`). HTP 주제 전환에서 다음
  /// 세션에 그대로 이어 쓰기 위해 들고 다닌다.
  final String? inputMethod;
  final DrawingRepository? drawingRepository;
  final DrawingSyncPolicy syncPolicy;
  final DrawingSyncCoordinator? syncCoordinator;
  final DrawingObjectDetectionController? objectDetectionController;
  final DrawingDraftRestoreController? draftRestoreController;
  final DraftImageProviderFactory? draftImageProviderFactory;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;
  final String Function()? idempotencyKeyProvider;
  final ConversationRepository? conversationRepository;
  final ConversationAnswerRepository? conversationAnswerRepository;
  final QuestionSkipRepository? questionSkipRepository;
  final ConversationEndRepository? conversationEndRepository;
  final QuestionTtsRepository? questionTtsRepository;
  final QuestionAudioPlayerFactory? questionAudioPlayerFactory;
  final VoiceRecorder? voiceRecorder;
  final MicrophonePermissionService? microphonePermissionService;
  final Duration voiceNoSpeechTimeout;
  final VoiceAnswerRepository? voiceAnswerRepository;
  final SttResultRepository? sttResultRepository;
  final ActivityRepository? activityRepository;
  final int? conversationId;
  final int? basisAnalysisId;

  /// 세션이 그림 단계를 지난 상태로 들어온 경우 대화를 즉시 이어받는다.
  ///
  /// 서버는 `IN_PROGRESS` + `DRAWING` 단계에서만 초안·획 저장을 허용하므로
  /// 대화·회고 단계로 복귀할 때는 저장과 객체 탐지를 시작하지 않는다.
  final bool resumeConversation;

  /// 활동 진입 화면에서 이어 그리기를 선택했으면 Draft를 바로 불러온다.
  final bool autoRestoreDraft;

  /// 주제 선택 뒤 생성한 새 활동이면 Draft 선택창 없이 빈 캔버스를 연다.
  final bool startFresh;
  final DrawingActivityContextDto activityContext;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen>
    with WidgetsBindingObserver {
  static const _thin = 4.0;
  static const _regular = 8.0;
  static const _thick = 14.0;

  final List<DrawingStroke> _completedStrokes = [];
  final List<DrawingStroke> _redoStrokes = [];
  DrawingStroke? _activeStroke;
  DrawingTool _tool = DrawingTool.pen;
  Color _color = AppColors.drawingInk;
  double _thickness = _regular;
  int? _activePointer;
  final GlobalKey _canvasBoundaryKey = GlobalKey();
  late final DrawingSyncCoordinator _syncCoordinator;
  late final bool _ownsSyncCoordinator;
  DrawingObjectDetectionController? _objectDetectionController;
  late final bool _ownsObjectDetectionController;
  late final DrawingDraftRestoreController _draftRestoreController;
  late final bool _ownsDraftRestoreController;
  bool _isCompleting = false;
  bool _isLeaving = false;
  bool _appInBackground = false;
  Future<bool>? _lifecycleSave;
  String? _pendingCompletionKey;
  BinaryUploadDto? _pendingCompletionImage;
  DrawingCompleteMetadataDto? _pendingCompletionMetadata;
  AiQuestionController? _questionController;
  late final AiQuestionDisplayController _questionDisplayController;
  late final AiQuestionSelectionController _questionSelectionController;
  OptionAnswerSubmissionController? _answerSubmissionController;
  QuestionSkipController? _questionSkipController;
  ConversationEndController? _conversationEndController;
  AiQuestionTtsController? _questionTtsController;
  VoiceRecordingController? _voiceRecordingController;
  VoiceAnswerUploadController? _voiceAnswerUploadController;
  SttResultController? _sttResultController;
  bool _conversationSetupStarted = false;

  /// 그림 단계 완료(`drawing-complete`)가 접수된 뒤 켜진다.
  ///
  /// 이 뒤로 세션은 `CONVERSING`이므로 캔버스 저장은 막히고 대화만 진행한다.
  bool _drawingStageFinished = false;

  String get _activityTitle {
    final activity = widget.activityContext;
    if (!activity.isHtp) return '그림 활동';
    final subject = switch (activity.drawingSubject) {
      'HOUSE' => '집 그리기',
      'TREE' => '나무 그리기',
      'PERSON' => '사람 그리기',
      _ => 'HTP 그림',
    };
    return '${activity.stepOrder ?? 1}단계 · $subject';
  }

  bool _movedToReflection = false;
  bool _automaticConversationEndStarted = false;
  int? _lastFollowUpAnswerMessageId;
  int? _activeConversationId;
  int? _lastQuestionMessageId;

  /// HOUSE·TREE 다음 주제 전환(`steps/next`) Key. 실패 후 재시도는 이 Key를
  /// 그대로 재사용한다 — 새로 만들지 않는다.
  String? _htpAdvanceIdempotencyKey;

  /// `steps/next`가 실패해 화면에 재시도 카드를 띄워야 하는 상태.
  Object? _htpAdvanceError;

  /// 오류 카드를 화면 안으로 끌어와 스크롤 없이 발견할 수 있게 하는 앵커.
  final GlobalKey _stageErrorAnchorKey = GlobalKey();

  /// 대화 생성이 실패해 질문을 시작하지 못한 상태.
  Object? _conversationStartError;

  /// 대화 생성 요청 하나의 identity와 Key.
  ///
  /// 백엔드가 Key와 요청 Body의 fingerprint를 함께 검사하므로, 분석 ID나 세션이
  /// 달라지면 Key도 새로 만들어야 `IDEMPOTENCY_KEY_REUSED`(409)를 피한다.
  String? _conversationStartIdempotencyKey;
  String? _conversationStartIdentity;
  int? _conversationStartAnalysisId;

  /// 대화 생성 요청 세대. 이전 analysis의 늦은 응답이 새 요청을 덮지 않게 한다.
  int _conversationStartGeneration = 0;

  /// 서버가 이미 종료됐다고 응답한 대화인지. 감정·완료 화면까지 전달한다.
  bool _conversationAlreadyEnded = false;

  /// 캔버스 입력이 막힌 상태인지 나타낸다.
  ///
  /// 대화 단계 세션으로 복귀했거나(S15P11B209-664) 이번 화면에서 그림 단계를
  /// 마친 경우(S15P11B209-680) 서버가 초안·획 저장을 받지 않으므로 그리기를 막고
  /// 대화만 진행한다.
  bool get _canvasLocked => widget.resumeConversation || _drawingStageFinished;

  /// 새 획 또는 복원된 Draft 배경이 있으면 완료 가능한 그림으로 본다.
  bool get _hasDrawingContent =>
      _completedStrokes.isNotEmpty || _draftRestoreController.draft != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final ttsRepository = widget.questionTtsRepository;
    final playerFactory = widget.questionAudioPlayerFactory;
    if (ttsRepository != null && playerFactory != null) {
      _questionTtsController = AiQuestionTtsController(
        ttsRepository,
        playerFactory(),
      );
    }
    _questionDisplayController = AiQuestionDisplayController()
      ..addListener(_handleQuestionDisplayChanged);
    _questionSelectionController = AiQuestionSelectionController()
      ..addListener(_handleQuestionSelectionChanged);
    _ownsSyncCoordinator = widget.syncCoordinator == null;
    _syncCoordinator =
        widget.syncCoordinator ??
        DrawingSyncCoordinator(
          sessionId: widget.sessionId,
          repository: widget.drawingRepository,
          policy: widget.syncPolicy,
          idempotencyKeyProvider:
              widget.idempotencyKeyProvider ?? _createIdempotencyKey,
        );
    _syncCoordinator.addListener(_handleSyncChanged);
    _ownsObjectDetectionController = widget.objectDetectionController == null;
    _objectDetectionController = widget.objectDetectionController;
    final sessionId = widget.sessionId;
    final drawingRepository = widget.drawingRepository;
    if (_objectDetectionController == null &&
        !widget.resumeConversation &&
        !widget.activityContext.isHtp &&
        sessionId != null &&
        drawingRepository != null) {
      // 그림일기만 입력 중 자동 저장과 객체 탐지를 연결
      _objectDetectionController = DrawingObjectDetectionController(
        saveDraft: _syncCoordinator.saveDraftNow,
        requestDetection: (request) =>
            drawingRepository.requestObjectDetection(sessionId, request),
      );
    }
    _objectDetectionController?.addListener(_handleObjectDetectionChanged);
    _ownsDraftRestoreController = widget.draftRestoreController == null;
    _draftRestoreController =
        widget.draftRestoreController ??
        DrawingDraftRestoreController(
          sessionId: widget.sessionId,
          repository: widget.drawingRepository,
          syncCoordinator: _syncCoordinator,
          imageProviderFactory: widget.draftImageProviderFactory,
        );
    _draftRestoreController.addListener(_handleDraftRestoreChanged);
    // 주입된 대화 컨텍스트(테스트·미리보기)는 즉시 구성하고, 실제 앱은 객체 탐지
    // 성공 후 대화를 생성해 실제 conversationId로 구성한다(S15P11B209-246).
    if (widget.conversationRepository != null &&
        widget.conversationId != null) {
      _setupConversationControllers(widget.conversationId!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.resumeConversation) {
        // HTP 대화 복귀는 완성 그림을 잠근 배경으로 보여주고 마지막 질문을 복원한다.
        unawaited(_resumeConversation());
        return;
      }
      _syncCoordinator.start(snapshotProvider: _captureCanvasSnapshot);
      if (widget.startFresh) {
        _draftRestoreController.startNewDrawing();
      } else {
        unawaited(
          _draftRestoreController.load(autoRestore: widget.autoRestoreDraft),
        );
        if (widget.autoRestoreDraft && !widget.activityContext.isHtp) {
          // 그림일기 이어하기는 캔버스 편집을 유지하면서 미응답 질문만 복원한다.
          unawaited(_restoreArtDiaryQuestion());
        }
      }
    });
  }

  /// 그림일기의 기존 대화가 있을 때 마지막 미응답 질문을 새로 생성하지 않고 복원한다.
  Future<void> _restoreArtDiaryQuestion() async {
    final sessionId = widget.sessionId;
    final drawingRepository = widget.drawingRepository;
    final activityRepository = widget.activityRepository;
    if (sessionId == null ||
        drawingRepository == null ||
        activityRepository == null ||
        widget.conversationRepository == null) {
      return;
    }
    try {
      final session = await drawingRepository.getSession(sessionId);
      final conversationId = session.conversationId;
      if (!mounted || conversationId == null) return;
      final messages = await activityRepository.getConversationMessages(
        conversationId,
      );
      if (!mounted) return;
      final turns = ActivityConversationTurn.group(messages);
      ActivityConversationTurn? pendingTurn;
      for (final turn in turns.reversed) {
        if (turn.question != null &&
            turn.hasNoAnswer &&
            !turn.question!.isSkipped) {
          pendingTurn = turn;
          break;
        }
      }
      final message = pendingTurn?.question;
      if (message == null) return;
      _setupConversationControllers(conversationId);
      _questionController?.restore(
        AiQuestion(
          messageId: message.messageId,
          conversationId: conversationId,
          sequence: message.sequence,
          text: message.rawText ?? '',
          options: [
            for (final option in message.options)
              AiQuestionOption(
                optionId: option.optionId,
                type: option.type,
                label: option.label,
                value: option.value,
                emoji: option.emoji,
              ),
          ],
          // 대화 내역 API에는 TTS 가능 여부가 없으므로 AI 질문은 음성 조회를 시도한다.
          ttsAvailable: true,
          createdAt:
              DateTime.tryParse(message.createdAt ?? '') ?? DateTime.now(),
        ),
      );
    } on Object {
      // 질문 복원 실패가 Draft 캔버스 복원과 이어 그리기를 막지 않게 한다.
    }
  }

  /// 진행 중 대화를 이어받아 질문을 다시 불러온다.
  ///
  /// 대화 생성 요청은 이미 대화가 있으면 `ACTIVE_CONVERSATION_EXISTS`(409)로
  /// 기존 `conversationId`를 돌려주므로 분석 ID 없이도 복귀할 수 있다.
  Future<void> _resumeConversation() async {
    await Future.wait([
      _restoreConversationBackground(),
      _restoreConversationQuestion(),
    ]);
  }

  Future<void> _restoreConversationBackground() async {
    final sessionId = widget.sessionId;
    final repository = widget.drawingRepository;
    if (sessionId == null || repository == null) return;
    try {
      final session = await repository.getSession(sessionId);
      final latestAsset = session.latestAsset;
      if (latestAsset == null) return;
      await _draftRestoreController.loadReadOnlyImage(latestAsset.fileUrl);
    } on Object {
      // 그림 조회 실패가 질문 복원까지 막지 않게 서로 독립적으로 처리한다.
    }
  }

  Future<void> _restoreConversationQuestion() async {
    await _ensureConversationStarted(null);
    if (!mounted) return;
    await _questionController?.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncCoordinator.removeListener(_handleSyncChanged);
    _draftRestoreController.removeListener(_handleDraftRestoreChanged);
    if (_ownsDraftRestoreController) _draftRestoreController.dispose();
    _objectDetectionController?.removeListener(_handleObjectDetectionChanged);
    if (_ownsObjectDetectionController) {
      _objectDetectionController?.dispose();
    }
    if (_ownsSyncCoordinator) _syncCoordinator.dispose();
    _questionController?.removeListener(_handleQuestionChanged);
    _questionController?.dispose();
    _questionDisplayController.removeListener(_handleQuestionDisplayChanged);
    _questionDisplayController.dispose();
    _questionSelectionController.removeListener(
      _handleQuestionSelectionChanged,
    );
    _questionSelectionController.dispose();
    _answerSubmissionController?.removeListener(_handleAnswerSubmissionChanged);
    _answerSubmissionController?.dispose();
    _questionSkipController?.removeListener(_handleQuestionSkipChanged);
    _questionSkipController?.dispose();
    _conversationEndController?.removeListener(_handleConversationEndChanged);
    _conversationEndController?.dispose();
    _questionTtsController?.dispose();
    _voiceRecordingController?.removeListener(_handleVoiceRecordingChanged);
    _voiceRecordingController?.dispose();
    _voiceAnswerUploadController?.removeListener(
      _handleVoiceAnswerUploadChanged,
    );
    _voiceAnswerUploadController?.dispose();
    _sttResultController?.removeListener(_handleSttResultChanged);
    _sttResultController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      if (!_canvasLocked) _syncCoordinator.resume();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _appInBackground = true;
      unawaited(_questionTtsController?.stop());
      if (_canvasLocked) return;
      _syncCoordinator.pause();
      if (_isCompleting || _syncCoordinator.isCompleting) return;
      _finishActiveStrokeForSave();
      final existing = _lifecycleSave;
      if (existing == null) {
        final saving = _syncCoordinator.flushAndSaveDraft();
        _lifecycleSave = saving;
        unawaited(
          saving.then<void>(
            (_) {
              if (identical(_lifecycleSave, saving)) {
                _lifecycleSave = null;
              }
            },
            onError: (Object _, StackTrace _) {
              // lifecycle callback은 저장을 시작할 뿐 완료를 보장할 수 없다.
              // 예상 밖 오류도 unhandled zone error로 확산시키지 않는다.
              if (identical(_lifecycleSave, saving)) {
                _lifecycleSave = null;
              }
            },
          ),
        );
      }
    }
  }

  void _handleSyncChanged() {
    if (mounted) setState(() {});
  }

  void _handleDraftRestoreChanged() {
    if (mounted) setState(() {});
  }

  void _handleObjectDetectionChanged() {
    // HTP는 주제별 그림 완료 응답의 분석 결과로만 대화를 시작
    if (widget.activityContext.isHtp) return;
    final detectionController = _objectDetectionController;
    final result = detectionController?.validResult;
    if (detectionController?.status != DrawingObjectDetectionStatus.succeeded ||
        result == null ||
        _conversationEndController?.completed == true) {
      return;
    }
    final questionController = _questionController;
    if (questionController == null) {
      // 아직 대화가 없으면 탐지 분석 ID로 대화를 생성한 뒤 질문을 요청한다.
      unawaited(
        _ensureConversationStarted(result.drawingAnalysisId).then((started) {
          if (started) {
            _questionController?.loadForAnalysis(result.drawingAnalysisId);
          }
        }),
      );
      return;
    }
    // 최신 탐지 결과의 분석 ID로 질문을 생성해 그림과 질문의 기준을 일치
    unawaited(questionController.loadForAnalysis(result.drawingAnalysisId));
  }

  /// 객체 탐지 분석 ID로 대화 세션을 생성하고 대화 컨트롤러를 구성한다.
  ///
  /// 명세 §12.2: `POST /drawing-sessions/{id}/conversations`로 대화를 만들고
  /// 반환된 conversationId로 이후 질문·답변 흐름을 연결한다(S15P11B209-246).
  Future<bool> _ensureConversationStarted(int? analysisId) async {
    if (_questionController != null) return true;
    final conversationRepository = widget.conversationRepository;
    final sessionId = widget.sessionId;
    if (conversationRepository == null || sessionId == null) return false;
    // 요청 Body를 그대로 식별자로 쓴다 — 백엔드가 해시하는 대상과 같다.
    final identity = 'session=$sessionId&analysis=${analysisId ?? ''}';
    // 같은 요청이 이미 진행 중이면 중복 발사하지 않는다. 다른 분석이 들어오면
    // 진행 중이더라도 그 요청을 폐기하고 새 요청으로 갈아탄다 — 그러지 않으면
    // 뒤늦게 도착한 이전 분석의 대화 ID가 최신 그림 위에 얹힌다.
    if (_conversationSetupStarted && _conversationStartIdentity == identity) {
      return false;
    }
    _conversationSetupStarted = true;
    _conversationStartAnalysisId = analysisId;
    if (_conversationStartIdentity != identity) {
      // 다른 분석·세션이면 이전 보류 요청을 무효화하고 Key도 새로 만든다.
      _conversationStartIdentity = identity;
      _conversationStartIdempotencyKey = null;
      _conversationStartGeneration += 1;
    }
    // 같은 identity 재시도는 같은 Key를 재사용한다 — 새 Key를 쓰면 첫 시도가
    // 서버에 도달했을 때 대화가 두 번 생길 수 있다.
    final key = _conversationStartIdempotencyKey ??=
        (widget.idempotencyKeyProvider ?? _createIdempotencyKey)();
    final generation = _conversationStartGeneration;
    try {
      final conversationId = await conversationRepository.startConversation(
        drawingSessionId: sessionId,
        analysisId: analysisId,
        idempotencyKey: key,
      );
      // 이전 analysis의 늦은 성공이 새 요청의 대화 ID를 덮어쓰면 안 된다.
      if (!mounted || generation != _conversationStartGeneration) return false;
      setState(() {
        _conversationStartError = null;
        _conversationStartIdentity = null;
        _conversationStartIdempotencyKey = null;
        _setupConversationControllers(conversationId);
      });
      return _questionController != null;
    } on Object catch (error) {
      if (generation != _conversationStartGeneration) return false;
      // 실패 시 다음 탐지 성공에서 재시도할 수 있도록 플래그를 되돌린다.
      _conversationSetupStarted = false;
      // 저장 전 거절이 확정된 실패는 보류 Key를 버려 새 요청을 허용한다.
      if (!shouldKeepRequestSnapshot(
        error,
        endpoint: ConversationRequestEndpoint.conversationStart,
      )) {
        _conversationStartIdentity = null;
        _conversationStartIdempotencyKey = null;
      }
      if (mounted) {
        setState(() => _conversationStartError = error);
        _revealStageError();
      }
      return false;
    }
  }

  /// 대화 생성 실패 뒤 같은 멱등성 키로 다시 대화를 열고 첫 질문을 요청한다.
  Future<void> _retryConversationStart() async {
    if (_conversationSetupStarted || _questionController != null) return;
    setState(() => _conversationStartError = null);
    final analysisId = _conversationStartAnalysisId;
    final started = await _ensureConversationStarted(analysisId);
    if (!started || !mounted) return;
    if (analysisId != null) {
      await _questionController?.loadForAnalysis(analysisId);
    } else {
      await _questionController?.load();
    }
  }

  /// 확정된 conversationId로 질문·답변·건너뛰기·종료·음성 컨트롤러를 구성한다.
  void _setupConversationControllers(int conversationId) {
    final conversationRepository = widget.conversationRepository;
    if (conversationRepository == null || _questionController != null) return;
    _conversationSetupStarted = true;
    _activeConversationId = conversationId;
    _questionController = AiQuestionController(
      conversationRepository,
      conversationId: conversationId,
      basisAnalysisId: widget.basisAnalysisId,
    )..addListener(_handleQuestionChanged);
    _answerSubmissionController = OptionAnswerSubmissionController(
      widget.conversationAnswerRepository ??
          const MockConversationAnswerRepository(),
      conversationId: conversationId,
      idempotencyKeyProvider:
          widget.idempotencyKeyProvider ?? _createIdempotencyKey,
    )..addListener(_handleAnswerSubmissionChanged);
    _questionSkipController = QuestionSkipController(
      widget.questionSkipRepository ?? const MockQuestionSkipRepository(),
      conversationId: conversationId,
      idempotencyKeyProvider:
          widget.idempotencyKeyProvider ?? _createIdempotencyKey,
    )..addListener(_handleQuestionSkipChanged);
    _conversationEndController = ConversationEndController(
      widget.conversationEndRepository ?? const MockConversationEndRepository(),
      conversationId: conversationId,
      idempotencyKeyProvider:
          widget.idempotencyKeyProvider ?? _createIdempotencyKey,
    )..addListener(_handleConversationEndChanged);
    _voiceRecordingController = VoiceRecordingController(
      widget.voiceRecorder ?? DeviceVoiceRecorder(),
      permissionService:
          widget.microphonePermissionService ??
          DeviceMicrophonePermissionService(),
      noSpeechTimeout: widget.voiceNoSpeechTimeout,
      beforeStart: () async {
        await _questionTtsController?.stop();
      },
    )..addListener(_handleVoiceRecordingChanged);
    if (widget.voiceAnswerRepository case final repository?) {
      _voiceAnswerUploadController = VoiceAnswerUploadController(
        repository,
        conversationId: conversationId,
        idempotencyKeyProvider:
            widget.idempotencyKeyProvider ?? _createIdempotencyKey,
      )..addListener(_handleVoiceAnswerUploadChanged);
    }
    if (widget.sttResultRepository case final repository?) {
      _sttResultController = SttResultController(
        repository,
        conversationId: conversationId,
      )..addListener(_handleSttResultChanged);
    }
  }

  void _handleQuestionChanged() {
    final questionController = _questionController;
    if (questionController?.status == AiQuestionStatus.conversationComplete) {
      // 이미 완료된 상태를 바꿀 필요가 없고 불필요한 네트워크 요청을 피하기
      // 위해 종료 API를 다시 부르지 않는다.
      if (questionController?.conversationAlreadyEnded == true) {
        _skipConversationEndAndContinue();
        return;
      }
      final reason = questionController?.completionReason;
      if (reason != null && !_automaticConversationEndStarted) {
        unawaited(_completeConversationAutomatically(reason));
      }
      return;
    }
    final question = _questionController?.question;
    if (!mounted ||
        _conversationEndController?.completed == true ||
        _questionController?.status != AiQuestionStatus.success ||
        question == null) {
      return;
    }
    _lastQuestionMessageId = question.messageId;
    // 하위 상태 UI의 빌드 중 알림과 겹치지 않도록 다음 프레임에 반영
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accepted = _questionDisplayController.receive(question);
      if (accepted) {
        // 선택지는 자동 녹음에서 음성이 감지되지 않았을 때만 표시한다.
        _questionSelectionController.beginQuestion(
          question,
          scheduleReveal: _voiceAnswerUploadController == null,
        );
        // 질문 ID를 함께 넘겨 이전 질문의 늦은 응답을 무효화한다.
        _answerSubmissionController?.beginQuestion(question.messageId);
        _questionSkipController?.beginQuestion(question.messageId);
        _voiceAnswerUploadController?.beginQuestion(question.messageId);
        if (_voiceAnswerUploadController == null) {
          unawaited(_questionTtsController?.playQuestion(question));
        } else {
          unawaited(_prepareVoiceAnswerForQuestion(question));
        }
      }
    });
  }

  // 질문 음성 재생이 끝나면 별도 버튼 없이 새 답변 녹음을 시작한다.
  Future<void> _prepareVoiceAnswerForQuestion(AiQuestion question) async {
    final recordingController = _voiceRecordingController;
    if (recordingController == null) return;

    await recordingController.beginQuestion();
    recordingController.prepareForAutomaticStart();
    try {
      // 오디오 완료 이벤트가 유실되어도 자동 녹음 시작이 막히지 않게 제한시간을 둔다.
      await _questionTtsController
          ?.playQuestion(question)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      await _questionTtsController?.stop();
      if (kDebugMode) {
        debugPrint('[VOICE_AUTO] tts_timeout messageId=${question.messageId}');
      }
    }
    if (!mounted ||
        _conversationEndController?.completed == true ||
        _questionDisplayController.visibleQuestion?.messageId !=
            question.messageId) {
      return;
    }
    final started = await recordingController.start();
    if (kDebugMode) {
      debugPrint(
        '[VOICE_AUTO] recording_start messageId=${question.messageId} '
        'started=$started status=${recordingController.status.name}',
      );
    }
  }

  void _handleQuestionDisplayChanged() {
    if (mounted) setState(() {});
  }

  void _handleQuestionSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _handleAnswerSubmissionChanged() {
    if (mounted) setState(() {});
  }

  void _handleQuestionSkipChanged() {
    if (mounted) setState(() {});
  }

  void _handleConversationEndChanged() {
    if (!mounted) return;
    setState(() {});
    // 대화까지 마쳤으면 감정 회고 단계로 넘어간다(명세 §23.1).
    //
    // 이번 세션에서 그림을 완료한 경우(_drawingStageFinished)뿐 아니라, 진행 중이던
    // 대화 세션을 이어받아 들어온 경우(resumeConversation)에도 이동해야 한다. 복귀
    // 모드에서는 캔버스와 완료 버튼이 잠겨 있어, 이동하지 않으면 대화 종료 후 앞으로
    // 나아갈 방법이 없어 교착된다.
    if ((_drawingStageFinished || widget.resumeConversation) &&
        _conversationEndController?.completed == true) {
      unawaited(_continueAfterConversation());
    }
  }

  void _handleVoiceRecordingChanged() {
    final controller = _voiceRecordingController;
    if (controller == null) return;
    if (controller.shouldShowOptions) {
      _questionSelectionController.revealOptions();
    } else if (controller.status == VoiceRecordingStatus.starting ||
        controller.status == VoiceRecordingStatus.recording) {
      _questionSelectionController.hideOptions();
    } else if (controller.status == VoiceRecordingStatus.completed) {
      _questionSelectionController.hideOptions();
      final question = _questionDisplayController.visibleQuestion;
      final recording = controller.recording;
      final uploadController = _voiceAnswerUploadController;
      if (question == null || recording == null || uploadController == null) {
        _questionDisplayController.dismiss();
      } else if (uploadController.status == VoiceAnswerUploadStatus.idle) {
        unawaited(
          uploadController.submit(
            questionMessageId: question.messageId,
            recording: recording,
          ),
        );
      }
    }
    if (mounted) setState(() {});
  }

  void _handleVoiceAnswerUploadChanged() {
    final uploadController = _voiceAnswerUploadController;
    if (uploadController?.status == VoiceAnswerUploadStatus.success) {
      _questionDisplayController.dismiss();
      final result = uploadController?.result;
      if (result != null) {
        unawaited(
          _sttResultController?.watch(
            messageId: result.messageId,
            sequence: result.sequence,
          ),
        );
      }
    } else if (uploadController?.status ==
            VoiceAnswerUploadStatus.consentRequired &&
        kDebugMode) {
      debugPrint('[VOICE_UPLOAD] rejected reason=VOICE_CONSENT_REQUIRED');
    }
    if (mounted) setState(() {});
  }

  void _handleSttResultChanged() {
    final controller = _sttResultController;
    final answerMessageId = controller?.messageId;
    if (controller?.status == SttResultStatus.success &&
        answerMessageId != null &&
        _lastFollowUpAnswerMessageId != answerMessageId) {
      _lastFollowUpAnswerMessageId = answerMessageId;
      unawaited(_requestFollowingQuestion(answerMessageId));
    }
    if (mounted) setState(() {});
  }

  void _retryVoiceAnswerUpload() {
    unawaited(_voiceAnswerUploadController?.retry());
  }

  Future<void> _selectQuestionOption(String optionId) async {
    final question = _questionDisplayController.visibleQuestion;
    final controller = _answerSubmissionController;
    if (question == null || controller == null) return;
    final pendingOptionId = controller.pendingOptionId;
    if (controller.isLockedToPendingAnswer &&
        pendingOptionId != null &&
        pendingOptionId != optionId) {
      // 저장 결과가 불확실한 동안 화면도 실제 재전송 가능한 pending 답변을
      // 가리켜야 한다. 새 선택은 표시하거나 전송하지 않는다.
      _questionSelectionController.select(question, pendingOptionId);
      return;
    }
    final valid = _questionSelectionController.select(question, optionId);
    if (!valid) return;
    await _questionTtsController?.stop();
    await _voiceRecordingController?.cancel();
    // BE 답변 계약이 선택 시점 스냅샷(type·value·label)을 요구해 객체째 전달
    final option = question.options.firstWhere(
      (candidate) => candidate.optionId == optionId,
    );
    final submitted = await controller.submit(
      questionMessageId: question.messageId,
      option: option,
    );
    if (submitted) {
      _questionDisplayController.dismiss();
      if (controller.conversationAlreadyEnded) {
        _skipConversationEndAndContinue();
        return;
      }
      await _requestFollowingQuestion(controller.answerMessageId);
    }
  }

  Future<void> _skipQuestion() async {
    final question = _questionDisplayController.visibleQuestion;
    final controller = _questionSkipController;
    if (question == null || controller == null) return;
    await _questionTtsController?.stop();
    await _voiceRecordingController?.cancel();
    final skipped = await controller.submit(
      questionMessageId: question.messageId,
    );
    if (skipped) {
      _questionDisplayController.dismiss();
      await _requestFollowingQuestion(null);
    }
  }

  /// 저장된 응답을 문맥으로 전달해 같은 그림의 다음 질문을 요청한다.
  Future<void> _requestFollowingQuestion(int? previousAnswerMessageId) async {
    if (!mounted ||
        _conversationEndController?.completed == true ||
        _automaticConversationEndStarted) {
      return;
    }
    await _questionController?.loadNext(
      previousAnswerMessageId: previousAnswerMessageId,
    );
  }

  /// 질문 제한 또는 질문 없음은 오류 화면 대신 정상 대화 종료로 처리한다.
  Future<void> _completeConversationAutomatically(
    ConversationCompletionReason reason,
  ) async {
    final controller = _conversationEndController;
    if (controller == null ||
        controller.completed ||
        _automaticConversationEndStarted) {
      return;
    }
    _automaticConversationEndStarted = true;
    await _questionTtsController?.stop();
    await _voiceRecordingController?.cancel();
    final ended = await controller.submit(
      lastQuestionMessageId: _lastQuestionMessageId,
      reason: reason,
    );
    if (ended) {
      _questionDisplayController.dismiss();
    } else {
      _automaticConversationEndStarted = false;
      if (mounted) {
        showAppMessage(
          context,
          message: '대화를 마무리하지 못했어요. 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    }
  }

  Future<void> _confirmAndEndConversation() async {
    final controller = _conversationEndController;
    if (controller == null || controller.completed) return;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '도다미와 대화를 그만할까요?',
      message: '대화를 끝내도 그림은 계속 그릴 수 있어요.',
      confirmLabel: '대화 그만하기',
      cancelLabel: '조금 더 이야기할래요',
      illustration: const Icon(
        Icons.chat_bubble_outline_rounded,
        size: 56,
        color: AppColors.tangerine,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _questionTtsController?.stop();
    await _voiceRecordingController?.cancel();
    final ended = await controller.submit(
      lastQuestionMessageId: _lastQuestionMessageId,
    );
    if (ended) _questionDisplayController.dismiss();
  }

  void _startStroke(PointerDownEvent event) {
    if (_activePointer != null ||
        _voiceRecordingController?.isRecording == true) {
      return;
    }
    _invalidatePendingCompletion();
    // 새 입력은 진행 중인 객체 탐지 결과를 현재 그림에서 제외
    _objectDetectionController?.onDrawingInputStarted();
    // 그림 입력이 시작되면 질문 오버레이 숨김
    _questionDisplayController.dismiss();
    setState(() {
      _activePointer = event.pointer;
      _activeStroke = DrawingStroke(
        points: [_pointFrom(event)],
        color: _color,
        thickness: _thickness,
        tool: _tool,
      );
    });
  }

  void _extendStroke(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _activeStroke == null) return;
    setState(() {
      _activeStroke = _activeStroke!.addPoint(_pointFrom(event));
    });
  }

  void _endStroke(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    final stroke = _activeStroke;
    final completed = event is PointerUpEvent && stroke != null;
    setState(() {
      if (completed) {
        _completedStrokes.add(stroke);
        _redoStrokes.clear();
      }
      _activeStroke = null;
      _activePointer = null;
    });
    final canvasSize = _canvasBoundaryKey.currentContext?.size;
    if (completed && canvasSize != null) {
      _syncCoordinator.recordStroke(stroke, canvasSize);
      _objectDetectionController?.onDrawingInputEnded();
    }
  }

  /// lifecycle·route 경계에서 pointer up을 더 이상 받을 수 없는 active stroke를
  /// 현재 점까지 완결한다. 이후 늦은 pointer up은 pointer id가 지워져 무시된다.
  void _finishActiveStrokeForSave() {
    final stroke = _activeStroke;
    if (stroke == null) return;
    final canvasSize = _canvasBoundaryKey.currentContext?.size;
    setState(() {
      _completedStrokes.add(stroke);
      _redoStrokes.clear();
      _activeStroke = null;
      _activePointer = null;
    });
    if (canvasSize != null) {
      _syncCoordinator.recordStroke(stroke, canvasSize);
      _objectDetectionController?.onDrawingInputEnded();
    }
  }

  void _undoLastStroke() {
    if (_activeStroke != null || _completedStrokes.isEmpty) return;
    _invalidatePendingCompletion();
    _objectDetectionController?.onDrawingInputStarted();
    // Rebuilding the vector action list also restores pixels removed from a
    // recovered Draft by the last local eraser stroke.
    setState(() => _redoStrokes.add(_completedStrokes.removeLast()));
    _syncCoordinator.recordUndo();
    _objectDetectionController?.onDrawingInputEnded();
  }

  void _redoLastStroke() {
    if (_activeStroke != null || _redoStrokes.isEmpty) return;
    _invalidatePendingCompletion();
    _objectDetectionController?.onDrawingInputStarted();
    setState(() => _completedStrokes.add(_redoStrokes.removeLast()));
    _syncCoordinator.recordRedo();
    _objectDetectionController?.onDrawingInputEnded();
  }

  DrawingPoint _pointFrom(PointerEvent event) => DrawingPoint(
    position: event.localPosition,
    elapsedMilliseconds: _syncCoordinator.elapsedMilliseconds,
    pressure: _supportedPressure(event),
  );

  double? _supportedPressure(PointerEvent event) {
    final stylus =
        event.kind == ui.PointerDeviceKind.stylus ||
        event.kind == ui.PointerDeviceKind.invertedStylus;
    if (!stylus || event.pressureMax <= event.pressureMin) return null;
    // TODO(DEVICE): Verify capability reporting on the target Galaxy Tab/S Pen.
    return event.pressure.clamp(0.0, 1.0);
  }

  Future<BinaryUploadDto?> _captureCanvasSnapshot() async {
    // 아직 journal에 완결 event로 기록되지 않은 active stroke를 Draft 이미지에만
    // 넣으면 lastEventSequence와 PNG가 어긋난다. lifecycle·route 경계는 먼저
    // [_finishActiveStrokeForSave]로 완결하고, 주기 autosave는 다음 tick을 기다린다.
    if (_activeStroke != null) return null;
    final boundary = _canvasBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    return BinaryUploadDto(
      bytes: bytes,
      fileName: 'drawing-draft.png',
      mimeType: 'image/png',
    );
  }

  Future<void> _confirmAndComplete() async {
    // 그림 단계는 한 번만 완료한다. 재요청은 서버가 거부한다.
    if (_canvasLocked ||
        _isCompleting ||
        _activeStroke != null ||
        !_hasDrawingContent) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '그림을 다 그렸나요?',
      message: '완성한 그림을 저장하고 다음으로 넘어갈까요?',
      confirmLabel: '다 그렸어요',
      cancelLabel: '조금 더 그릴래요',
      illustration: const Icon(
        Icons.draw_rounded,
        size: 56,
        color: AppColors.tangerine,
      ),
    );
    if (confirmed != true || !mounted) return;
    final sessionId = widget.sessionId;
    final repository = widget.drawingRepository;
    if (sessionId == null || repository == null) {
      showAppMessage(context, message: '아직 활동을 완료할 수 없어요. 잠시 후 다시 해 주세요.');
      return;
    }
    final conversationEndController = _conversationEndController;
    if (conversationEndController != null &&
        !conversationEndController.completed) {
      showAppMessage(
        context,
        message: '대화를 먼저 마친 뒤 그림 활동을 완료해 주세요.',
        type: AppMessageType.error,
      );
      return;
    }
    setState(() => _isCompleting = true);
    final completionBarrier = _syncCoordinator.beginCompletion();
    var completionPhase = _DrawingCompletePhase.canvasCapture;
    var snapshotWasNull = false;
    DrawingStageCompleteResponseDto? completionResponse;
    try {
      completionPhase = _DrawingCompletePhase.strokeFlush;
      await completionBarrier;
      if (!mounted) return;
      final batchesFlushed = await _syncCoordinator.flushStrokeBatches();
      if (!batchesFlushed) {
        throw StateError('Pending stroke batch could not be saved.');
      }
      completionPhase = _DrawingCompletePhase.canvasCapture;
      final snapshot =
          _pendingCompletionImage ??
          await (widget.completionSnapshotProvider ?? _captureCanvasSnapshot)();
      snapshotWasNull = snapshot == null;
      if (snapshot == null) throw StateError('Final snapshot unavailable');
      final metadata =
          _pendingCompletionMetadata ??
          DrawingCompleteMetadataDto(
            lastEventSequence: _syncCoordinator.journal.lastEventSequence,
            drawingDurationMs: _syncCoordinator.elapsedMilliseconds < 1
                ? 1
                : _syncCoordinator.elapsedMilliseconds,
            clientCompletedAt: DateTime.now().toUtc().toIso8601String(),
          );
      final idempotencyKey =
          _pendingCompletionKey ??
          widget.idempotencyKeyProvider?.call() ??
          _createIdempotencyKey();
      _pendingCompletionImage = snapshot;
      _pendingCompletionMetadata = metadata;
      _pendingCompletionKey = idempotencyKey;
      completionPhase = _DrawingCompletePhase.request;
      completionResponse = await repository.completeDrawingStage(
        sessionId,
        finalImage: snapshot,
        metadata: metadata,
        idempotencyKey: idempotencyKey,
      );
      // 서버가 `CONVERSING`으로 올려주면 대화 단계가 열린다. `nextAction`은 판단
      // 근거로 쓰지 않는다 — 명세 §10.8은 감정 선택을 가리키지만 정본 활동 흐름
      // §23.1은 대화(14~18) 뒤에 회고(19)를 두므로 단계로만 분기한다.
      completionPhase = _DrawingCompletePhase.contractValidation;
      if (completionResponse.currentStage != 'CONVERSING' &&
          completionResponse.currentStage != 'REFLECTION') {
        throw StateError('Unexpected drawing completion result');
      }
      if (kDebugMode) {
        debugPrint(
          '[DRAWING_COMPLETE] success '
          'currentStage=${completionResponse.currentStage} '
          'nextAction=${completionResponse.nextAction}',
        );
      }
      if (!mounted) return;
      _invalidatePendingCompletion();
      // 이 뒤로 캔버스 저장은 서버가 받지 않으므로 자동 저장을 멈춘다.
      _syncCoordinator.stop();
      setState(() => _drawingStageFinished = true);
      if (completionResponse.currentStage == 'REFLECTION') {
        await _continueAfterConversation();
        return;
      }
      await _startConversationAfterDrawing(
        completionResponse.analysis.analysisId,
      );
    } on Object catch (error) {
      _debugDrawingCompleteFailure(
        phase: completionPhase,
        error: error,
        snapshotWasNull: snapshotWasNull,
        response: completionResponse,
      );
      if (mounted) {
        showAppMessage(
          context,
          message: '그림을 완료하지 못했어요. 그림은 그대로 있으니 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (!_drawingStageFinished) {
        _syncCoordinator.cancelCompletion();
      }
      if (mounted) {
        if (!_drawingStageFinished && !_appInBackground) {
          _syncCoordinator.resume();
        }
        setState(() => _isCompleting = false);
      }
    }
  }

  /// 그림 단계 완료 직후 대화를 시작하고 첫 질문을 불러온다.
  ///
  /// HTP도 그림일기도 대화가 실제로 열린 뒤에만 질문을 요청한다.
  Future<void> _startConversationAfterDrawing(int analysisId) async {
    if (widget.conversationRepository == null) {
      if (!widget.activityContext.isHtp) {
        await _continueAfterConversation();
        return;
      }
      if (mounted) {
        showAppMessage(
          context,
          message: '대화를 시작하지 못했어요. 잠시 후 다시 들어와 주세요.',
          type: AppMessageType.error,
        );
      }
      return;
    }
    final started = await _ensureConversationStarted(analysisId);
    if (!mounted) return;
    final questionController = _questionController;
    if (!started || questionController == null) {
      if (!widget.activityContext.isHtp) {
        await _continueAfterConversation();
        return;
      }
      showAppMessage(
        context,
        message: '대화를 시작하지 못했어요. 잠시 후 다시 들어와 주세요.',
        type: AppMessageType.error,
      );
      return;
    }
    await questionController.loadForAnalysis(analysisId);
  }

  /// 대화가 끝난 뒤 활동·주제에 맞는 다음 화면으로 넘어간다.
  ///
  /// HTP HOUSE·TREE는 `steps/next`로 다음 주제 세션을 바로 연다. PERSON은
  /// `steps/next`를 여기서 부르지 않는다 — 백엔드가 Reflection을 PERSON 세션이
  /// 아직 `REFLECTION` 단계일 때만 받고 `steps/next`가 그 세션을 `COMPLETED`로
  /// 바꾸면 이후 Reflection 저장을 거절하므로, PERSON은 감정 선택 화면에서
  /// Reflection을 먼저 저장한 뒤 그 화면이 `steps/next`를 부른다.
  Future<void> _continueAfterConversation() async {
    final activityContext = widget.activityContext;
    final assessmentId = activityContext.htpAssessmentId;
    final repository = widget.drawingRepository;
    if (!activityContext.isHtp || assessmentId == null || repository == null) {
      _goToEmotionSelect();
      return;
    }
    if (repository is! HtpDrawingRepository) {
      _goToEmotionSelect();
      return;
    }
    if (activityContext.drawingSubject == 'PERSON') {
      _goToEmotionSelect();
      return;
    }
    final htpRepository = repository as HtpDrawingRepository;
    if (_movedToReflection || !mounted) return;
    _movedToReflection = true;
    try {
      // 주제별 대화 완료 후 다음 HTP 세션을 생성 — 지금 주제가 쓴 입력 방식을
      // 그대로 이어 쓴다(하드코딩된 CANVAS 아님).
      final idempotencyKey = _htpAdvanceIdempotencyKey ??=
          widget.idempotencyKeyProvider?.call() ?? _createIdempotencyKey();
      final result = await HtpResponseFlowController(htpRepository)
          .moveToNextStep(
            assessmentId,
            inputMethod: widget.inputMethod ?? 'CANVAS',
            idempotencyKey: idempotencyKey,
          );
      if (!mounted) return;
      final resolution = result.nextSession;
      if (resolution == null) {
        throw StateError('Next HTP drawing session is missing.');
      }
      await Navigator.of(context).pushReplacementNamed(
        AppRoutes.drawing(widget.childId),
        arguments: DrawingRouteArguments(
          sessionId: resolution.sessionId,
          repository: repository,
          completionSnapshotProvider: widget.completionSnapshotProvider,
          resumeConversation: !resolution.isDrawingStage,
          startFresh: true,
          activityContext: resolution.activityContext,
          inputMethod: resolution.inputMethod,
        ),
      );
    } on Object catch (error) {
      // 대화는 이미 끝나 다시 알림이 오지 않으므로, 토스트만 띄우면 화면에
      // 앞으로 나아갈 방법이 남지 않는다. 재시도 카드를 띄워 같은 Key로 다시
      // 부를 수 있게 한다.
      _movedToReflection = false;
      if (!mounted) return;
      setState(() => _htpAdvanceError = error);
      _revealStageError();
      showAppMessage(
        context,
        message: '다음 그림을 준비하지 못했어요. 다시 시도해 주세요.',
        type: AppMessageType.error,
      );
    }
  }

  /// 도구 패널 아래쪽에 생긴 오류 카드를 현재 화면 안으로 끌어온다.
  ///
  /// 좁은 화면에서는 카드가 스크롤 밖에 있어, 아이가 스스로 찾아 내려가야만
  /// 다음 단계로 갈 수 있는 상태가 된다. 다음 프레임에 카드가 배치된 뒤
  /// 스크롤을 맞추고, 스크린리더에는 카드 자체의 live region이 알린다.
  void _revealStageError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _stageErrorAnchorKey.currentContext;
      if (anchor == null) return;
      // 앵커를 viewport 위쪽에 붙여 바로 아래 카드 전체가 드러나게 한다.
      // 중첩 스크롤(바깥 세로 스크롤 + 도구 패널 스크롤)도 함께 맞춘다.
      unawaited(
        Scrollable.ensureVisible(
          anchor,
          duration: const Duration(milliseconds: 250),
        ),
      );
    });
  }

  /// `steps/next` 실패 뒤 같은 멱등성 키로 다시 다음 주제를 연다.
  ///
  /// `_movedToReflection`이 연타를 막고 `_htpAdvanceIdempotencyKey`를 그대로
  /// 재사용하므로 서버에 중복 전환이 생기지 않는다.
  Future<void> _retryHtpAdvance() async {
    if (_movedToReflection) return;
    setState(() => _htpAdvanceError = null);
    await _continueAfterConversation();
  }

  /// 서버가 이미 종료했다고 답한 대화를 종료 API 없이 다음 단계로 넘긴다.
  ///
  /// 종료 API는 이미 끝난 대화에도 저장된 응답을 돌려주지만, 상태를 바꾸지 않는
  /// 요청을 한 번 더 보낼 이유가 없어 생략한다. HTP HOUSE·TREE는
  /// [_continueAfterConversation]이 다음 주제를 열고, 일반 그림과 PERSON은 같은
  /// 함수가 감정 화면으로 넘기므로 두 경로 모두 여기서 처리된다.
  void _skipConversationEndAndContinue() {
    if (_automaticConversationEndStarted || !mounted) return;
    _automaticConversationEndStarted = true;
    // 감정·완료 화면이 종료 API를 다시 부르지 않도록 상태를 함께 넘긴다.
    _conversationAlreadyEnded = true;
    unawaited(_questionTtsController?.stop());
    _questionDisplayController.dismiss();
    unawaited(_continueAfterConversation());
  }

  /// 감정 회고 화면으로 한 번만 이동한다.
  void _goToEmotionSelect() {
    if (_movedToReflection || !mounted) return;
    final sessionId = widget.sessionId;
    final repository = widget.drawingRepository;
    if (sessionId == null || repository == null) return;
    _movedToReflection = true;
    unawaited(_questionTtsController?.stop());
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.emotionSelect(widget.childId),
      arguments: EmotionSelectRouteArguments(
        sessionId: sessionId,
        repository: repository,
        conversationId: _activeConversationId,
        // 서버가 이미 종료했다고 답한 대화도 끝난 것으로 넘겨 종료 API 재호출을 막는다.
        conversationAlreadyEnded:
            _conversationAlreadyEnded ||
            _conversationEndController?.completed == true,
        conversationEndRepository: widget.conversationEndRepository,
        conversationEndIdempotencyKey:
            _conversationEndController?.requestIdempotencyKey,
        conversationEndRequest: _conversationEndController?.requestSnapshot,
        lastQuestionMessageId: _lastQuestionMessageId,
        idempotencyKeyProvider: widget.idempotencyKeyProvider,
        activityContext: widget.activityContext,
        inputMethod: widget.inputMethod,
      ),
    );
  }

  void _invalidatePendingCompletion() {
    _pendingCompletionKey = null;
    _pendingCompletionImage = null;
    _pendingCompletionMetadata = null;
  }

  List<DrawingStroke> get _visibleStrokes {
    final strokes = [..._completedStrokes];
    if (_activeStroke case final stroke?) strokes.add(stroke);
    return List.unmodifiable(strokes);
  }

  Future<void> _stopTtsAndPop() async {
    if (_isLeaving || _isCompleting) return;
    setState(() => _isLeaving = true);
    try {
      await _questionTtsController?.stop();
      await _voiceRecordingController?.cancel();
      if (!_canvasLocked &&
          widget.sessionId != null &&
          widget.drawingRepository != null) {
        _syncCoordinator.pause();
        _finishActiveStrokeForSave();
        final saved = await _syncCoordinator.flushAndSaveDraft();
        if (!mounted) return;
        if (!saved) {
          final leaveAnyway = await showAppConfirmDialog(
            context: context,
            title: '그림을 저장하지 못했어요',
            message: '연결을 확인하고 다시 시도하거나, 저장하지 않고 나갈 수 있어요.',
            confirmLabel: '저장하지 않고 나가기',
            cancelLabel: '그림으로 돌아가기',
            illustration: const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: AppColors.tangerine,
            ),
          );
          if (leaveAnyway != true || !mounted) {
            if (!_appInBackground) _syncCoordinator.resume();
            return;
          }
        }
      }
      if (mounted) {
        Navigator.of(context).pop(DrawingRouteResult.backToActivityEntry);
      }
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_stopTtsAndPop());
    },
    child: Scaffold(
      backgroundColor: AppColors.childCanvas,
      appBar: AppTopBar(
        title: _activityTitle,
        onBack: () => unawaited(_stopTtsAndPop()),
        actions: [
          IconButton.filledTonal(
            key: const ValueKey('redo-action'),
            tooltip: _activeStroke != null
                ? '그리는 중에는 다시 실행할 수 없어요'
                : '취소한 그림 획 다시 실행',
            onPressed: _activeStroke == null && _redoStrokes.isNotEmpty
                ? _redoLastStroke
                : null,
            icon: const Icon(Icons.redo_rounded),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(AppSizes.iconButton),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: IconButton.filledTonal(
              key: const ValueKey('undo-action'),
              tooltip: _activeStroke != null
                  ? '그리는 중에는 실행 취소할 수 없어요'
                  : '마지막 그림 획 실행 취소',
              onPressed: _activeStroke == null && _completedStrokes.isNotEmpty
                  ? _undoLastStroke
                  : null,
              icon: const Icon(Icons.undo_rounded),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(AppSizes.iconButton),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final restoreStatus = _draftRestoreController.status;
            final autoRestoreInProgress =
                widget.autoRestoreDraft &&
                (restoreStatus == DrawingDraftRestoreStatus.loading ||
                    restoreStatus == DrawingDraftRestoreStatus.found ||
                    restoreStatus == DrawingDraftRestoreStatus.loadingImage);
            final canvas = _CanvasPanel(
              repaintBoundaryKey: _canvasBoundaryKey,
              strokes: _visibleStrokes,
              onPointerDown: _startStroke,
              onPointerMove: _extendStroke,
              onPointerUp: _endStroke,
              backgroundImage: _draftRestoreController.backgroundImage,
              inputEnabled:
                  !_canvasLocked &&
                  !_isCompleting &&
                  !_isLeaving &&
                  _draftRestoreController.canDraw,
              showRestoreOverlay:
                  !_canvasLocked && !_draftRestoreController.canDraw,
              autoRestoreInProgress: autoRestoreInProgress,
              onBackgroundLoaded: _draftRestoreController.markImageLoaded,
              onBackgroundError: _draftRestoreController.markImageFailed,
              restoreStatus: restoreStatus,
              restoreRetryable: _draftRestoreController.canRetry,
              onContinue: _draftRestoreController.continueDrawing,
              onStartNew: _draftRestoreController.startNewDrawing,
              onRetryQuery: () => unawaited(_draftRestoreController.load()),
              onRetryImage: _draftRestoreController.retryImage,
              question: _questionDisplayController.visibleQuestion,
              showQuestion:
                  _questionDisplayController.isVisible &&
                  _activePointer == null &&
                  (_canvasLocked || _draftRestoreController.canDraw),
              selectedQuestionOptionId:
                  _questionSelectionController.selectedOptionId,
              onQuestionOptionSelected: (optionId) {
                unawaited(_selectQuestionOption(optionId));
              },
              answerSubmissionStatus:
                  _answerSubmissionController?.status ??
                  OptionAnswerSubmissionStatus.idle,
              questionSkipStatus:
                  _questionSkipController?.status ?? QuestionSkipStatus.idle,
              conversationEndStatus:
                  _conversationEndController?.status ??
                  ConversationEndStatus.idle,
              showQuestionResponseActions:
                  _questionSelectionController.optionsVisible,
              onQuestionSkip: () {
                unawaited(_skipQuestion());
              },
              onConversationEnd: () {
                unawaited(_confirmAndEndConversation());
              },
              voiceRecordingController: _voiceRecordingController,
              voiceAnswerUploadStatus:
                  _voiceAnswerUploadController?.status ??
                  VoiceAnswerUploadStatus.idle,
              onRetryVoiceAnswerUpload: _retryVoiceAnswerUpload,
              // 실패했지만 다시 시도해도 같은 결과인 조작은 잠근다.
              answerRetryable:
                  _answerSubmissionController?.status !=
                      OptionAnswerSubmissionStatus.failure ||
                  _answerSubmissionController?.canRetry == true,
              answerOptionsEnabled:
                  _answerSubmissionController?.canSelectOption ?? true,
              skipRetryable:
                  _questionSkipController?.status !=
                      QuestionSkipStatus.failure ||
                  _questionSkipController?.canRetry == true,
              endRetryable:
                  _conversationEndController?.status !=
                      ConversationEndStatus.failure ||
                  _conversationEndController?.canRetry == true,
              voiceRetryable: _voiceAnswerUploadController?.canRetry ?? false,
              sttResultController: _sttResultController,
            );
            final sidePanel = _DrawingSidePanel(
              selectedTool: _tool,
              selectedColor: _color,
              selectedThickness: _thickness,
              onToolChanged: (tool) => setState(() => _tool = tool),
              onColorChanged: (color) => setState(() => _color = color),
              onThicknessChanged: (value) => setState(() => _thickness = value),
              canComplete:
                  !_canvasLocked &&
                  !_isCompleting &&
                  _activeStroke == null &&
                  _hasDrawingContent,
              isCompleting: _isCompleting,
              onComplete: () => unawaited(_confirmAndComplete()),
              saveStatus: _syncCoordinator.saveStatus,
              canRetrySave: _syncCoordinator.canRetrySave,
              onRetrySave: () => unawaited(_syncCoordinator.retry()),
              questionController: _questionController,
              conversationStartError: _conversationStartError,
              htpAdvanceError: _htpAdvanceError,
              onRetryConversationStart: () =>
                  unawaited(_retryConversationStart()),
              onRetryHtpAdvance: () => unawaited(_retryHtpAdvance()),
              stageErrorAnchorKey: _stageErrorAnchorKey,
            );
            final screenSize = MediaQuery.sizeOf(context);
            final useCompactLandscape =
                screenSize.width >= 640 && screenSize.height <= 520;
            final useTabletLayout =
                !useCompactLandscape && screenSize.width >= 900;
            if (useCompactLandscape || useTabletLayout) {
              final padding = useCompactLandscape
                  ? AppSpacing.sm
                  : AppSpacing.lg;
              final panelWidth = useCompactLandscape ? 240.0 : 320.0;
              return Padding(
                key: ValueKey(
                  useCompactLandscape
                      ? 'drawing-layout-compact-landscape'
                      : 'drawing-layout-tablet',
                ),
                padding: EdgeInsets.all(padding),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: canvas),
                    SizedBox(
                      width: useCompactLandscape
                          ? AppSpacing.sm
                          : AppSpacing.lg,
                    ),
                    SizedBox(width: panelWidth, child: sidePanel),
                  ],
                ),
              );
            }
            final canvasHeight = constraints.maxWidth >= 720
                ? min(520.0, max(420.0, constraints.maxHeight * 0.55))
                : 420.0;
            return SingleChildScrollView(
              key: const ValueKey('drawing-layout-stacked'),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  SizedBox(height: canvasHeight, child: canvas),
                  const SizedBox(height: AppSpacing.md),
                  sidePanel,
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _CanvasPanel extends StatelessWidget {
  const _CanvasPanel({
    required this.repaintBoundaryKey,
    required this.strokes,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.backgroundImage,
    required this.inputEnabled,
    required this.showRestoreOverlay,
    required this.autoRestoreInProgress,
    required this.onBackgroundLoaded,
    required this.onBackgroundError,
    required this.restoreStatus,
    required this.restoreRetryable,
    required this.onContinue,
    required this.onStartNew,
    required this.onRetryQuery,
    required this.onRetryImage,
    required this.question,
    required this.showQuestion,
    required this.selectedQuestionOptionId,
    required this.onQuestionOptionSelected,
    required this.answerSubmissionStatus,
    required this.questionSkipStatus,
    required this.conversationEndStatus,
    required this.showQuestionResponseActions,
    required this.onQuestionSkip,
    required this.onConversationEnd,
    required this.voiceRecordingController,
    required this.voiceAnswerUploadStatus,
    required this.onRetryVoiceAnswerUpload,
    required this.answerRetryable,
    required this.answerOptionsEnabled,
    required this.skipRetryable,
    required this.endRetryable,
    required this.voiceRetryable,
    required this.sttResultController,
  });

  final GlobalKey repaintBoundaryKey;
  final List<DrawingStroke> strokes;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerMoveEvent> onPointerMove;
  final ValueChanged<PointerEvent> onPointerUp;
  final ImageProvider<Object>? backgroundImage;
  final bool inputEnabled;

  /// 초안 복원 안내를 덮어 띄울지 여부다.
  ///
  /// 대화 복귀 모드이거나 그림 단계가 끝난 뒤에는 띄우지 않는다.
  final bool showRestoreOverlay;
  final bool autoRestoreInProgress;
  final VoidCallback onBackgroundLoaded;
  final VoidCallback onBackgroundError;
  final DrawingDraftRestoreStatus restoreStatus;
  final bool restoreRetryable;
  final VoidCallback onContinue;
  final VoidCallback onStartNew;
  final VoidCallback onRetryQuery;
  final VoidCallback onRetryImage;
  final AiQuestion? question;
  final bool showQuestion;
  final String? selectedQuestionOptionId;
  final ValueChanged<String> onQuestionOptionSelected;
  final OptionAnswerSubmissionStatus answerSubmissionStatus;
  final QuestionSkipStatus questionSkipStatus;
  final ConversationEndStatus conversationEndStatus;
  final bool showQuestionResponseActions;
  final VoidCallback onQuestionSkip;
  final VoidCallback onConversationEnd;
  final VoiceRecordingController? voiceRecordingController;
  final VoiceAnswerUploadStatus voiceAnswerUploadStatus;
  final VoidCallback onRetryVoiceAnswerUpload;

  /// 실패한 조작을 같은 버튼으로 다시 시도해도 되는지(Overlay로 그대로 전달).
  final bool answerRetryable;
  final bool answerOptionsEnabled;
  final bool skipRetryable;
  final bool endRetryable;
  final bool voiceRetryable;
  final SttResultController? sttResultController;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.outlineStrong, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final sttMaxHeight = (constraints.maxHeight - AppSpacing.md * 2)
            .clamp(96.0, 180.0)
            .toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              key: repaintBoundaryKey,
              child: DrawingCanvas(
                strokes: strokes,
                onPointerDown: onPointerDown,
                onPointerMove: onPointerMove,
                onPointerUp: onPointerUp,
                backgroundImage: backgroundImage,
                inputEnabled: inputEnabled,
                onBackgroundLoaded: onBackgroundLoaded,
                onBackgroundError: onBackgroundError,
              ),
            ),
            AiQuestionBubbleOverlay(
              question: question,
              visible: showQuestion,
              selectedOptionId: selectedQuestionOptionId,
              onOptionSelected: onQuestionOptionSelected,
              showResponseActions: showQuestionResponseActions,
              submissionStatus: answerSubmissionStatus,
              skipStatus: questionSkipStatus,
              onSkip: onQuestionSkip,
              endStatus: conversationEndStatus,
              onEnd: onConversationEnd,
              voiceRecordingController: voiceRecordingController,
              voiceAnswerUploadStatus: voiceAnswerUploadStatus,
              onRetryVoiceAnswerUpload: onRetryVoiceAnswerUpload,
              answerRetryable: answerRetryable,
              answerOptionsEnabled: answerOptionsEnabled,
              skipRetryable: skipRetryable,
              endRetryable: endRetryable,
              voiceRetryable: voiceRetryable,
            ),
            if (sttResultController case final controller?)
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: SttResultPanel(
                    controller: controller,
                    maxHeight: sttMaxHeight,
                  ),
                ),
              ),
            if (showRestoreOverlay)
              _DraftRestoreOverlay(
                status: restoreStatus,
                canRetry: restoreRetryable,
                autoRestoreInProgress: autoRestoreInProgress,
                onContinue: onContinue,
                onStartNew: onStartNew,
                onRetryQuery: onRetryQuery,
                onRetryImage: onRetryImage,
              ),
          ],
        );
      },
    ),
  );
}

class _DraftRestoreOverlay extends StatelessWidget {
  const _DraftRestoreOverlay({
    required this.status,
    required this.canRetry,
    required this.autoRestoreInProgress,
    required this.onContinue,
    required this.onStartNew,
    required this.onRetryQuery,
    required this.onRetryImage,
  });

  final DrawingDraftRestoreStatus status;
  final bool canRetry;
  final bool autoRestoreInProgress;
  final VoidCallback onContinue;
  final VoidCallback onStartNew;
  final VoidCallback onRetryQuery;
  final VoidCallback onRetryImage;

  @override
  Widget build(BuildContext context) {
    final loading =
        status == DrawingDraftRestoreStatus.loading ||
        status == DrawingDraftRestoreStatus.loadingImage ||
        (autoRestoreInProgress && status == DrawingDraftRestoreStatus.found);
    final imageFailure = status == DrawingDraftRestoreStatus.imageFailed;
    final queryFailure = status == DrawingDraftRestoreStatus.queryFailed;
    final title = switch (status) {
      DrawingDraftRestoreStatus.found => '그리던 그림이 있어요',
      DrawingDraftRestoreStatus.imageFailed => '그림을 불러오지 못했어요',
      DrawingDraftRestoreStatus.queryFailed => '저장된 그림을 확인하지 못했어요',
      DrawingDraftRestoreStatus.loadingImage => '그림을 불러오고 있어요',
      _ => '그리던 그림을 확인하고 있어요',
    };
    final description = status == DrawingDraftRestoreStatus.found
        ? '이어서 그릴까요?'
        : loading
        ? '잠시만 기다려 주세요.'
        : '다시 시도하거나 새 그림으로 시작할 수 있어요.';

    return ColoredBox(
      color: const Color(0x66000000),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (loading) ...[
                        Image.asset(
                          'assets/characters/dodam_resume_loading.png',
                          key: const ValueKey(
                            'draft-restore-loading-character',
                          ),
                          width: 150,
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(description, textAlign: TextAlign.center),
                      if (!loading) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                key: const ValueKey('draft-start-new'),
                                label: '새로 시작하기',
                                onPressed: onStartNew,
                              ),
                            ),
                            if ((!imageFailure && !queryFailure) ||
                                canRetry) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: AppButton(
                                  key: const ValueKey('draft-primary-action'),
                                  label: imageFailure || queryFailure
                                      ? '다시 시도'
                                      : '이어서 그리기',
                                  variant: AppButtonVariant.child,
                                  onPressed: imageFailure
                                      ? onRetryImage
                                      : queryFailure
                                      ? onRetryQuery
                                      : onContinue,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawingSidePanel extends StatelessWidget {
  const _DrawingSidePanel({
    required this.selectedTool,
    required this.selectedColor,
    required this.selectedThickness,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onThicknessChanged,
    required this.canComplete,
    required this.isCompleting,
    required this.onComplete,
    required this.saveStatus,
    required this.canRetrySave,
    required this.onRetrySave,
    required this.onRetryConversationStart,
    required this.onRetryHtpAdvance,
    required this.stageErrorAnchorKey,
    this.questionController,
    this.conversationStartError,
    this.htpAdvanceError,
  });

  final DrawingTool selectedTool;
  final Color selectedColor;
  final double selectedThickness;
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onThicknessChanged;
  final bool canComplete;
  final bool isCompleting;
  final VoidCallback onComplete;
  final DrawingSaveStatus saveStatus;
  final bool canRetrySave;
  final VoidCallback onRetrySave;
  final AiQuestionController? questionController;

  /// 대화 생성 실패 원인. `null`이 아니면 준비 안내 대신 재시도 카드를 띄운다.
  final Object? conversationStartError;

  /// `steps/next` 실패 원인. `null`이 아니면 재시도 카드를 함께 띄운다.
  final Object? htpAdvanceError;

  final VoidCallback onRetryConversationStart;
  final VoidCallback onRetryHtpAdvance;

  /// 오류 카드를 화면 안으로 스크롤하기 위한 앵커.
  final GlobalKey stageErrorAnchorKey;

  static const _colors = <(String, Color)>[
    ('검정', AppColors.drawingInk),
    ('빨강', AppColors.drawingRed),
    ('파랑', AppColors.drawingBlue),
    ('노랑', AppColors.drawingYellow),
  ];
  static const _thicknesses = <(String, double)>[
    ('얇게', _DrawingScreenState._thin),
    ('보통', _DrawingScreenState._regular),
    ('굵게', _DrawingScreenState._thick),
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: SingleChildScrollView(
      key: const ValueKey('drawing-tool-panel-scroll'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.tangerineSoft,
                child: Icon(
                  Icons.emoji_nature_rounded,
                  color: AppColors.tangerine,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '자유롭게 그려 보자!',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ToolHeading(icon: Icons.edit_rounded, label: '도구'),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _ToolChoice(
                  key: const ValueKey('drawing-tool-pen'),
                  label: '펜',
                  icon: Icons.edit_rounded,
                  selected: selectedTool == DrawingTool.pen,
                  onTap: () => onToolChanged(DrawingTool.pen),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ToolChoice(
                  key: const ValueKey('drawing-tool-eraser'),
                  label: '지우개',
                  icon: Icons.auto_fix_normal_rounded,
                  selected: selectedTool == DrawingTool.eraser,
                  onTap: () => onToolChanged(DrawingTool.eraser),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ToolHeading(icon: Icons.palette_outlined, label: '색상'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (name, color) in _colors)
                _ColorChoice(
                  name: name,
                  color: color,
                  selected: selectedColor == color,
                  onTap: () => onColorChanged(color),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ToolHeading(icon: Icons.line_weight_rounded, label: '굵기'),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.center,
              children: [
                for (final (label, value) in _thicknesses)
                  _ThicknessChoice(
                    key: ValueKey('drawing-thickness-$label'),
                    label: label,
                    selected: selectedThickness == value,
                    onTap: () => onThicknessChanged(value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 오류 카드가 붙는 자리. 실패 시 이 지점을 화면 안으로 스크롤한다.
          SizedBox.shrink(key: stageErrorAnchorKey),
          if (questionController case final controller?)
            AiQuestionLoadPanel(controller: controller, loadOnMount: false)
          else if (conversationStartError != null)
            _AiStageRetryCard(
              key: const ValueKey('conversation-start-error'),
              title: '대화를 시작하지 못했어요',
              error: conversationStartError,
              onRetry: onRetryConversationStart,
              retryKey: const ValueKey('conversation-start-retry'),
              endpoint: ConversationRequestEndpoint.conversationStart,
            )
          else
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text(
                '대화를 준비하고 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 16),
              ),
            ),
          if (htpAdvanceError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _AiStageRetryCard(
              key: const ValueKey('htp-advance-error'),
              title: '다음 그림을 준비하지 못했어요',
              error: htpAdvanceError,
              onRetry: onRetryHtpAdvance,
              retryKey: const ValueKey('htp-advance-retry'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _SaveStatusIndicator(
            status: saveStatus,
            canRetry: canRetrySave,
            onRetry: onRetrySave,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('drawing-complete'),
            label: '다 그렸어요!',
            variant: AppButtonVariant.child,
            isLoading: isCompleting,
            onPressed: canComplete ? onComplete : null,
          ),
          const SizedBox(
            key: ValueKey('drawing-complete-bottom-space'),
            height: AppSpacing.md,
          ),
        ],
      ),
    ),
  );
}

/// 대화 시작·다음 주제 전환처럼 화면 안에서 되짚을 수 있는 단계 실패 카드.
///
/// 아이 화면이므로 원인 문구는 공통 `childFriendly` 표현만 쓰고 HTTP status나
/// errorCode는 절대 노출하지 않는다. 같은 요청을 반복해도 결과가 같은 실패
/// (401·403·404·검증 오류)에는 재시도 버튼을 만들지 않는다.
class _AiStageRetryCard extends StatelessWidget {
  const _AiStageRetryCard({
    required this.title,
    required this.error,
    required this.onRetry,
    required this.retryKey,
    this.endpoint,
    super.key,
  });

  final String title;
  final Object? error;
  final VoidCallback onRetry;
  final Key retryKey;
  final ConversationRequestEndpoint? endpoint;

  @override
  Widget build(BuildContext context) {
    final presentation = ApiFailurePresentation.of(error, childFriendly: true);
    final canRetry = endpoint == null
        ? presentation.canRetry
        : canRetryConversationRequest(error, endpoint: endpoint!);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            label: '$title. ${presentation.message}',
            child: ExcludeSemantics(
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: AppColors.error,
                    size: 32,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    presentation.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
          ),
          if (canRetry)
            TextButton(
              key: retryKey,
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded),
                  SizedBox(width: AppSpacing.xs),
                  Flexible(child: Text('다시 시도')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SaveStatusIndicator extends StatelessWidget {
  const _SaveStatusIndicator({
    required this.status,
    required this.canRetry,
    required this.onRetry,
  });

  final DrawingSaveStatus status;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      DrawingSaveStatus.localOnly => (
        Icons.edit_note_rounded,
        '그림을 안전하게 담고 있어요',
        AppColors.inkMuted,
      ),
      DrawingSaveStatus.saving => (
        Icons.cloud_upload_outlined,
        '저장 중...',
        AppColors.lavender,
      ),
      DrawingSaveStatus.saved => (
        Icons.cloud_done_outlined,
        '저장됨',
        AppColors.success,
      ),
      DrawingSaveStatus.failed => (
        Icons.cloud_off_outlined,
        '저장하지 못했어요',
        AppColors.error,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          if (status == DrawingSaveStatus.failed && canRetry)
            IconButton(
              key: const ValueKey('save-retry'),
              tooltip: '저장 다시 시도',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(AppSizes.iconButton),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThicknessChoice extends StatelessWidget {
  const _ThicknessChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label 굵기',
    child: Tooltip(
      message: '$label 선 굵기',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTouchTarget,
            minHeight: AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.leafSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.leaf : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.line_weight_rounded,
                size: 18,
                color: selected ? AppColors.leaf : AppColors.inkMuted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.ink : AppColors.inkMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.leaf,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ToolHeading extends StatelessWidget {
  const _ToolHeading({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppColors.inkMuted, size: 20),
      const SizedBox(width: AppSpacing.xs),
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class _ToolChoice extends StatelessWidget {
  const _ToolChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label 도구',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(
          minHeight: AppSizes.minTouchTarget,
          minWidth: AppSizes.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.leafSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.leaf : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? AppColors.leaf : AppColors.inkMuted),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.ink : AppColors.inkMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppColors.leaf,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$name 색상',
    selected: selected,
    button: true,
    child: InkWell(
      key: ValueKey('color-$name'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.leaf : AppColors.outline,
            width: selected ? 4 : 2,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                color: color.computeLuminance() > 0.55
                    ? AppColors.ink
                    : Colors.white,
              )
            : null,
      ),
    ),
  );
}

final class EmotionSelectRouteArguments {
  const EmotionSelectRouteArguments({
    required this.sessionId,
    required this.repository,
    required this.conversationId,
    required this.conversationAlreadyEnded,
    required this.conversationEndRepository,
    required this.conversationEndIdempotencyKey,
    required this.conversationEndRequest,
    required this.lastQuestionMessageId,
    required this.idempotencyKeyProvider,
    required this.activityContext,
    this.inputMethod,
  });

  final int? sessionId;
  final DrawingRepository? repository;
  final int? conversationId, lastQuestionMessageId;
  final bool conversationAlreadyEnded;
  final ConversationEndRepository? conversationEndRepository;
  final String? conversationEndIdempotencyKey;
  final ConversationEndRequest? conversationEndRequest;
  final String Function()? idempotencyKeyProvider;
  final DrawingActivityContextDto activityContext;
  final String? inputMethod;
}

class EmotionSelectScreen extends StatefulWidget {
  const EmotionSelectScreen({
    required this.childId,
    this.sessionId,
    this.drawingRepository,
    this.conversationId,
    this.conversationAlreadyEnded = false,
    this.conversationEndRepository,
    this.conversationEndIdempotencyKey,
    this.conversationEndRequest,
    this.lastQuestionMessageId,
    this.idempotencyKeyProvider,
    this.activityCompletionController,
    this.activityContext = const DrawingActivityContextDto.general(),
    this.inputMethod,
    super.key,
  });

  final String childId;
  final int? sessionId;
  final DrawingRepository? drawingRepository;
  final int? conversationId, lastQuestionMessageId;
  final bool conversationAlreadyEnded;
  final ConversationEndRepository? conversationEndRepository;
  final String? conversationEndIdempotencyKey;
  final ConversationEndRequest? conversationEndRequest;
  final String Function()? idempotencyKeyProvider;
  final DrawingActivityCompletionController? activityCompletionController;
  final DrawingActivityContextDto activityContext;

  /// 이 PERSON 세션이 실제로 쓰는 입력 방식. `steps/next` 호출에 그대로 넘긴다
  /// (백엔드는 PERSON 전환에서 이 값을 상태 전이에 쓰지 않지만, 재생 검증에서
  /// PERSON은 예외로 건너뛰므로 값 자체는 임의로 바뀌어도 안전하다 — 그래도
  /// 세션 실제 값을 보내는 것이 원칙에 맞다).
  final String? inputMethod;

  @override
  State<EmotionSelectScreen> createState() => _EmotionSelectScreenState();
}

class _EmotionSelectScreenState extends State<EmotionSelectScreen> {
  static const _emotions = <(DrawingEmotionType, String, IconData)>[
    (DrawingEmotionType.happy, '기쁨', Icons.sentiment_very_satisfied_rounded),
    (DrawingEmotionType.sad, '슬픔', Icons.sentiment_dissatisfied_rounded),
    (DrawingEmotionType.angry, '화남', Icons.mood_bad_rounded),
    (DrawingEmotionType.scared, '무서움', Icons.visibility_off_rounded),
    (DrawingEmotionType.calm, '편안함', Icons.sentiment_satisfied_rounded),
    (DrawingEmotionType.unknown, '모르겠어', Icons.help_outline_rounded),
  ];

  final Set<DrawingEmotionType> _selectedEmotions = {};
  final TextEditingController _titleController = TextEditingController();
  DrawingActivityCompletionController? _activityCompletionController;
  late final bool _ownsActivityCompletionController;
  bool _isSubmitting = false;

  /// PERSON `steps/next` Key. 재시도는 이 Key를 재사용한다 — 새로 만들지 않는다.
  String? _htpPersonStepKey;

  /// `steps/next`가 이미 성공했다면 그 결과를 들고 있어 재시도 때 다시 부르지
  /// 않는다(`allStepsCompleted=false` 응답이어도 마찬가지 — 그 결과 자체를
  /// 캐시해 재호출을 막는다).
  HtpResponseFlowResult? _htpPersonAdvanceResult;

  /// PERSON `complete` Key. `steps/next` 성공 후 `complete`만 재시도할 때
  /// 재사용한다.
  String? _htpCompleteKey;

  bool get _reflectionInputLocked =>
      _activityCompletionController?.reflectionInputLocked == true;

  @override
  void initState() {
    super.initState();
    _ownsActivityCompletionController =
        widget.activityCompletionController == null;
    _activityCompletionController = widget.activityCompletionController;
    final sessionId = widget.sessionId;
    final repository = widget.drawingRepository;
    if (_activityCompletionController == null &&
        sessionId != null &&
        repository != null) {
      _activityCompletionController = DrawingActivityCompletionController(
        drawingRepository: repository,
        sessionId: sessionId,
        conversationId: widget.conversationId,
        conversationAlreadyEnded: widget.conversationAlreadyEnded,
        conversationEndRepository: widget.conversationEndRepository,
        idempotencyKeyProvider:
            widget.idempotencyKeyProvider ?? _createIdempotencyKey,
        previousConversationEndIdempotencyKey:
            widget.conversationEndIdempotencyKey,
        previousConversationEndRequest: widget.conversationEndRequest,
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    if (_ownsActivityCompletionController) {
      _activityCompletionController?.dispose();
    }
    super.dispose();
  }

  void _toggleEmotion(DrawingEmotionType emotion) {
    setState(() {
      if (_selectedEmotions.remove(emotion)) return;
      if (emotion == DrawingEmotionType.unknown) {
        _selectedEmotions
          ..clear()
          ..add(emotion);
      } else {
        _selectedEmotions
          ..remove(DrawingEmotionType.unknown)
          ..add(emotion);
      }
    });
  }

  Future<void> _submitReflection({required bool skipped}) async {
    if (_isSubmitting) return;
    final sessionId = widget.sessionId;
    final repository = widget.drawingRepository;
    final completionController = _activityCompletionController;
    if (sessionId == null || repository == null) {
      showAppMessage(context, message: '아직 마음을 저장할 수 없어요. 잠시 후 다시 해 주세요.');
      return;
    }
    if (!widget.activityContext.isHtp && completionController == null) {
      showAppMessage(context, message: '아직 마음을 저장할 수 없어요. 잠시 후 다시 해 주세요.');
      return;
    }
    if (!skipped && _selectedEmotions.isEmpty) return;
    setState(() => _isSubmitting = true);
    final rawTitle = _titleController.text;
    final reflection = SaveDrawingReflectionRequestDto(
      title: rawTitle.isEmpty ? null : rawTitle,
      selectedEmotions: skipped
          ? const []
          : List.unmodifiable(_selectedEmotions),
      expressedEmotionText: null,
      skipped: skipped,
    );
    try {
      final assessmentId = widget.activityContext.htpAssessmentId;
      if (widget.activityContext.isHtp && assessmentId != null) {
        if (repository is! HtpDrawingRepository) {
          throw UnsupportedError('HTP activity is unavailable.');
        }
        final htpRepository = repository as HtpDrawingRepository;
        var advanced = _htpPersonAdvanceResult;
        if (advanced == null) {
          // steps/next가 아직 성공하지 않았다 — PERSON 세션이 REFLECTION
          // 단계일 때만 Reflection을 저장할 수 있으므로 steps/next보다
          // 먼저 호출한다(PUT이라 재시도해도 안전하다).
          await htpRepository.saveHtpReflection(assessmentId, reflection);
          if (!mounted) return;
          advanced = await HtpResponseFlowController(htpRepository)
              .moveToNextStep(
                assessmentId,
                inputMethod: widget.inputMethod ?? 'CANVAS',
                idempotencyKey: _htpPersonStepKey ??=
                    widget.idempotencyKeyProvider?.call() ??
                    _createIdempotencyKey(),
              );
          if (!mounted) return;
          _htpPersonAdvanceResult = advanced;
        }
        if (!advanced.allStepsCompleted) {
          // PERSON은 항상 allStepsCompleted=true를 반환해야 한다. 캐시된
          // 결과를 그대로 두어 재시도가 steps/next를 다시 부르거나 새 Key를
          // 만들지 않게 한다.
          throw StateError('HTP assessment did not complete as expected.');
        }
        await htpRepository.completeHtpAssessment(
          assessmentId,
          idempotencyKey: _htpCompleteKey ??=
              widget.idempotencyKeyProvider?.call() ?? _createIdempotencyKey(),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.activityComplete(widget.childId),
          arguments: ActivityCompleteRouteArguments(
            sessionId: sessionId,
            repository: repository,
          ),
        );
        return;
      }
      final completed = await completionController!.submit(
        reflection: reflection,
        lastQuestionMessageId: widget.lastQuestionMessageId,
      );
      if (!completed) {
        throw completionController.error ??
            StateError('Drawing activity completion failed.');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.activityComplete(widget.childId),
        arguments: ActivityCompleteRouteArguments(
          sessionId: sessionId,
          repository: repository,
        ),
      );
    } on Object {
      if (mounted) {
        final reflectionFailed =
            completionController?.failedStep ==
            DrawingActivityCompletionStatus.savingReflection;
        showAppMessage(
          context,
          message: reflectionFailed
              ? '마음을 저장하지 못했어요. 고른 내용은 그대로 있으니 다시 해 주세요.'
              : '활동을 완료하지 못했어요. 고른 내용은 그대로 있으니 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reflectionInputLocked = _reflectionInputLocked;
    final retrySkipped =
        _activityCompletionController?.reflectionWasSkipped == true;
    return Scaffold(
      backgroundColor: AppColors.childCanvas,
      appBar: AppTopBar(
        title: '내 마음 고르기',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            key: const ValueKey('emotion-screen-scroll'),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _EmotionGuideCard(),
                    const SizedBox(height: AppSpacing.lg),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: constraints.maxWidth >= 800 ? 3 : 2,
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      childAspectRatio: constraints.maxWidth >= 800 ? 2.5 : 2,
                      children: [
                        for (final (emotion, label, icon) in _emotions)
                          AppChoiceCard(
                            key: ValueKey('emotion-$label'),
                            label: label,
                            isSelected: _selectedEmotions.contains(emotion),
                            childFriendly: true,
                            leading: Icon(icon, color: AppColors.tangerine),
                            onTap: _isSubmitting || reflectionInputLocked
                                ? null
                                : () => _toggleEmotion(emotion),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      key: const ValueKey('drawing-title'),
                      controller: _titleController,
                      label: '그림 제목 (선택)',
                      hintText: '그림에 이름을 붙여볼까요?',
                      textInputAction: TextInputAction.done,
                      enabled: !reflectionInputLocked,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (reflectionInputLocked) ...[
                      const Text(
                        '저장 결과를 확인할 때까지 같은 내용으로 다시 시도해 주세요.',
                        key: ValueKey('reflection-input-locked-message'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (widget.sessionId == null ||
                        widget.drawingRepository == null) ...[
                      const Text(
                        '아직 마음을 저장할 수 없어요. 잠시 후 다시 해 주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            key: const ValueKey('emotion-skip'),
                            label: reflectionInputLocked && retrySkipped
                                ? '다시 시도'
                                : '건너뛰기',
                            variant: AppButtonVariant.secondary,
                            isLoading: _isSubmitting,
                            onPressed:
                                _isSubmitting ||
                                    (reflectionInputLocked && !retrySkipped)
                                ? null
                                : () => unawaited(
                                    _submitReflection(skipped: true),
                                  ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: AppButton(
                            key: const ValueKey('emotion-submit'),
                            label: reflectionInputLocked && !retrySkipped
                                ? '다시 시도'
                                : '다 했어요!',
                            variant: AppButtonVariant.child,
                            isLoading: _isSubmitting,
                            onPressed:
                                _isSubmitting ||
                                    (reflectionInputLocked && retrySkipped) ||
                                    (!reflectionInputLocked &&
                                        _selectedEmotions.isEmpty)
                                ? null
                                : () => unawaited(
                                    _submitReflection(skipped: false),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmotionGuideCard extends StatelessWidget {
  const _EmotionGuideCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: const Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: AppColors.tangerineSoft,
          child: Icon(
            Icons.emoji_nature_rounded,
            color: AppColors.tangerine,
            size: 32,
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '그림을 그리며 어떤 마음이었나요?',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: AppSpacing.xxs),
              Text(
                '내 마음과 닮은 카드를 직접 골라 보세요.',
                style: TextStyle(color: AppColors.inkMuted, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class ActivityCompleteRouteArguments {
  const ActivityCompleteRouteArguments({
    required this.sessionId,
    required this.repository,
  });

  final int sessionId;
  final DrawingRepository repository;
}

class ActivityCompleteScreen extends StatefulWidget {
  const ActivityCompleteScreen({
    required this.childId,
    this.sessionId,
    this.drawingRepository,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 30,
    super.key,
  });

  final String childId;
  final int? sessionId;
  final DrawingRepository? drawingRepository;
  final Duration pollInterval;
  final int maxPollAttempts;

  @override
  State<ActivityCompleteScreen> createState() => _ActivityCompleteScreenState();
}

class _ActivityCompleteScreenState extends State<ActivityCompleteScreen> {
  ActivityCompletionController? _completionController;

  bool get _legacyCompleted =>
      widget.sessionId == null || widget.drawingRepository == null;

  @override
  void initState() {
    super.initState();
    final sessionId = widget.sessionId;
    final repository = widget.drawingRepository;
    if (sessionId == null || repository == null) return;
    _completionController = ActivityCompletionController.forStatus(
      repository,
      sessionId: sessionId,
      pollInterval: widget.pollInterval,
      maxPollAttempts: widget.maxPollAttempts,
    )..addListener(_handleCompletionStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_completionController?.pollUntilTerminal());
    });
  }

  @override
  void dispose() {
    _completionController
      ?..removeListener(_handleCompletionStatusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleCompletionStatusChanged() {
    if (mounted) setState(() {});
  }

  void _retryStatusCheck() {
    unawaited(_completionController?.pollUntilTerminal());
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: AppColors.childCanvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            key: const ValueKey('activity-complete-scroll'),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - AppSpacing.xl * 2,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: _buildStatusContent(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildStatusContent(BuildContext context) {
    final status = _completionController?.status;
    if (_legacyCompleted || status == ActivityCompletionStatus.completed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 56,
            backgroundColor: AppColors.tangerineSoft,
            child: Icon(
              Icons.celebration_rounded,
              color: AppColors.tangerine,
              size: 60,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            '그림 활동을 모두 마쳤어요!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '이제 보호자에게 기기를 건네주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMuted,
              fontSize: 20,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            key: const ValueKey('guardian-handoff'),
            label: '보호자에게 건넸어요',
            variant: AppButtonVariant.child,
            leading: const Icon(Icons.family_restroom_rounded),
            onPressed: () => _confirmGuardianTransition(context),
          ),
        ],
      );
    }

    if (status == ActivityCompletionStatus.pollingFailure) {
      return _CompletionStatusMessage(
        icon: Icons.wifi_off_rounded,
        title: '완료 상태를 확인하지 못했어요',
        description: '활동은 접수되어 있어요. 연결을 확인하고 다시 시도해 주세요.',
        button: AppButton(
          key: const ValueKey('activity-completion-retry'),
          label: '다시 확인',
          variant: AppButtonVariant.child,
          onPressed: _retryStatusCheck,
        ),
      );
    }

    if (status == ActivityCompletionStatus.terminalFailure) {
      return const _CompletionStatusMessage(
        icon: Icons.error_outline_rounded,
        title: '활동을 마무리하지 못했어요',
        description: '보호자에게 알려 다시 확인해 주세요.',
      );
    }

    return const _CompletionStatusMessage(
      key: ValueKey('activity-completion-progress'),
      icon: Icons.hourglass_top_rounded,
      title: '활동을 마무리하고 있어요',
      description: '분석과 리포트를 준비하고 있어요. 잠시만 기다려 주세요.',
      showProgress: true,
    );
  }

  Future<void> _confirmGuardianTransition(BuildContext context) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '보호자 화면으로 이동할까요?',
      message: '보호자가 기기를 받았다면 확인을 눌러 주세요.',
      confirmLabel: '확인',
      cancelLabel: '취소',
      illustration: const Icon(
        Icons.family_restroom_rounded,
        color: AppColors.leaf,
        size: 56,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    AppRouter.goGuardianHome(context);
  }
}

class _CompletionStatusMessage extends StatelessWidget {
  const _CompletionStatusMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.button,
    this.showProgress = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? button;
  final bool showProgress;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: AppColors.tangerine, size: 64),
      const SizedBox(height: AppSpacing.lg),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        description,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.inkMuted,
          fontSize: 18,
          height: 1.45,
        ),
      ),
      if (showProgress) ...[
        const SizedBox(height: AppSpacing.lg),
        const CircularProgressIndicator(),
      ],
      if (button case final action?) ...[
        const SizedBox(height: AppSpacing.xl),
        action,
      ],
    ],
  );
}
