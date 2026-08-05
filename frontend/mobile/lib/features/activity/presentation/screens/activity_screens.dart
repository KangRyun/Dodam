import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/network/api_failure_presentation.dart';
import '../../../../design_system/design_system.dart';
import '../../../child/domain/repositories/child_repository.dart';
import '../../../drawing/application/activity_completion_controller.dart';
import '../../../drawing/application/canvas_tutorial_controller.dart';
import '../../../drawing/application/drawing_object_detection_controller.dart';
import '../../../drawing/application/drawing_activity_completion_controller.dart';
import '../../../drawing/application/drawing_document_controller.dart';
import '../../../drawing/application/drawing_pressure_policy.dart';
import '../../../drawing/application/drawing_session_start_controller.dart';
import '../../../drawing/application/drawing_sync_coordinator.dart';
import '../../../drawing/application/drawing_draft_restore_controller.dart';
import '../../../drawing/application/drawing_fill_engine.dart';
import '../../../drawing/application/htp_response_flow_controller.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../../drawing/domain/repositories/drawing_repository.dart';
import '../../../drawing/presentation/models/drawing_stroke.dart';
import '../../../drawing/presentation/models/drawing_canvas_action.dart';
import '../../../drawing/presentation/models/drawing_tool_state.dart';
import '../../../drawing/presentation/widgets/drawing_color_palette.dart';
import '../../../drawing/presentation/widgets/drawing_complete_cta.dart';
import '../../../drawing/presentation/widgets/drawing_canvas_viewport.dart';
import '../../../drawing/presentation/widgets/drawing_crayon_frame.dart';
import '../../../drawing/presentation/widgets/drawing_cursor_overlay.dart';
import '../../../drawing/presentation/widgets/drawing_toolbar.dart';
import '../../../drawing/presentation/widgets/drawing_canvas.dart';
import '../../../drawing/presentation/widgets/canvas_tool_tutorial_overlay.dart';
import '../../../drawing/presentation/widgets/canvas_tutorial_target_registry.dart';
import '../../../conversation/conversation.dart';
import '../../../child_mode/domain/dodam_costume.dart';
import '../../data/dto/activity_dtos.dart';
import '../../domain/models/activity_conversation_turn.dart';
import '../../domain/repositories/activity_repository.dart';
import '../widgets/emotion_selection_widgets.dart';
import '../widgets/htp_emotion_preview_gallery.dart';

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

/// 질문 음성 재생이 끝난 뒤 아동의 응답을 기다리는 기본 시간이다.
const aiQuestionNoResponseTimeout = Duration(seconds: 10);

/// Backend 대화 생성 계약의 생략 시 기본 질문 상한과 같은 값이다.
const defaultConversationMaxQuestionCount = 10;

/// 아이가 그만하겠다고 말했을 때 AI 가 되묻는 선택지의 식별자다 (S15P11B209-938).
///
/// AI 서버가 정하는 값이며(ai/question_service.py), 응답 계약에서는 option code 로 실려
/// 오다가 BE 를 지나며 optionId 가 된다. 화면은 이 둘만 종료 신호로 다루고 나머지 칩은
/// 평범한 답변으로 취급한다 — 값이 바뀌면 양쪽을 함께 고쳐야 한다.
const _endTalkOptionId = 'CHIP_END_TALK';
const _endActivityOptionId = 'CHIP_END_ACTIVITY';

/// 앱이 실제 종료로 옮길 수 있는 confirmedStopTarget 값 (S15P11B209-951).
const _confirmedStopTargets = {confirmedStopConversation, confirmedStopActivity};

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    required this.childId,
    this.sessionId,
    this.drawingRepository,
    this.syncPolicy = const DrawingSyncPolicy(),
    this.syncCoordinator,
    this.documentController,
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
    this.questionOptionRevealDelay = const Duration(milliseconds: 2500),
    this.noResponseTimeout = aiQuestionNoResponseTimeout,
    this.maxQuestionCount = defaultConversationMaxQuestionCount,
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
    this.companion = DodamCostume.base,
    this.childRepository,
    this.canvasTutorialController,
    super.key,
  }) : assert(maxQuestionCount > 0 && maxQuestionCount <= 10);

  final String childId;
  final int? sessionId;

  /// 이 세션이 실제로 쓰는 입력 방식(`CANVAS`|`UPLOAD`). HTP 주제 전환에서 다음
  /// 세션에 그대로 이어 쓰기 위해 들고 다닌다.
  final String? inputMethod;
  final DodamCostume companion;
  final ChildRepository? childRepository;
  final CanvasTutorialController? canvasTutorialController;
  final DrawingRepository? drawingRepository;
  final DrawingSyncPolicy syncPolicy;
  final DrawingSyncCoordinator? syncCoordinator;

  /// 캔버스 문서(획·채우기·지우기 이력)를 들고 있는 컨트롤러다.
  ///
  /// 주지 않으면 화면이 직접 만들어 쓰고 dispose 까지 책임진다. 테스트는 문서 상태를
  /// 직접 들여다보기 위해 주입한다.
  final DrawingDocumentController? documentController;
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
  final Duration questionOptionRevealDelay;
  final Duration noResponseTimeout;
  final int maxQuestionCount;
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

  late final DrawingDocumentController _documentController;
  bool _ownsDocumentController = false;

  /// 화면에 보이는 완결된 획이다. 문서 컨트롤러가 획·채우기·지우기를 한 이력으로
  /// 관리하므로 이 화면은 목록을 따로 들고 있지 않는다.
  List<DrawingStroke> get _completedStrokes =>
      _documentController.visibleStrokes;
  DrawingStroke? _activeStroke;

  /// 툴바에 늘 떠 있는 기본 8색이다. 상세 팔레트를 열지 않아도 바로 고를 수 있다.
  static const _quickColors = <Color>[
    AppColors.canvasSwatchRed,
    AppColors.canvasSwatchOrange,
    AppColors.canvasSwatchYellow,
    AppColors.canvasSwatchGreen,
    AppColors.canvasSwatchTeal,
    AppColors.canvasSwatchBlue,
    AppColors.canvasSwatchPurple,
    AppColors.canvasSwatchCharcoal,
  ];

  /// 태블릿에서 상세 팔레트 팝오버를 팔레트 버튼 옆에 붙이기 위한 기준점이다.
  final LayerLink _paletteAnchorLink = LayerLink();

  late final DrawingCursorController _cursorController;

  /// 현재 선택된 도구·색·굵기다. 크레용 캔버스는 도구를 펜/지우개 두 갈래가 아니라
  /// 크레용·연필·붓·채우기·지우개로 나누므로 한 상태로 묶어 다룬다.
  DrawingToolState _toolState = const DrawingToolState(
    color: AppColors.canvasSwatchCharcoal,
    width: _regular,
  );
  final List<Color> _recentColors = [AppColors.canvasSwatchCharcoal];

  DrawingTool get _tool => _toolState.wireTool ?? DrawingTool.pen;
  Color get _color => _toolState.color;
  double get _thickness => _toolState.width;
  int? _activePointer;

  /// 채우기·획 지우개·전체 지우기처럼 그림 이미지를 통째로 바꾸는 중인지다.
  /// 이 동안에는 입력을 막아 캡처와 그림이 어긋나지 않게 한다.
  bool _isApplyingRasterMutation = false;

  /// 캡처가 끝나 업로드만 남았을 때 참이 된다. 업로드를 기다리는 동안에도
  /// 아이가 계속 그릴 수 있어야 한다.
  bool _rasterMutationAllowsDrawing = false;
  bool _isStrokeEraseGestureActive = false;
  bool _strokeEraseFallbackActive = false;

  /// 오래 걸리는 채우기 계산이 끝났을 때 그 사이 다른 변경이 있었는지 가린다.
  int _snapshotMutationGeneration = 0;
  final DrawingFillEngine _fillEngine = const ScanlineDrawingFillEngine();

  static const _noDocumentChange = DrawingDocumentChange(
    changed: false,
    wireEffect: DrawingWireEffect.none,
  );
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
  late final DodamCostume _companionSnapshot;
  Future<bool>? _lifecycleSave;
  String? _pendingCompletionKey;
  BinaryUploadDto? _pendingCompletionImage;
  DrawingCompleteMetadataDto? _pendingCompletionMetadata;
  BinaryUploadDto? _completedDrawingImage;
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
  Timer? _noResponseTimer;
  int _noResponseGeneration = 0;
  bool _noResponseRequestInFlight = false;
  bool _awaitingNoResponseQuestion = false;
  AiQuestion? _noResponseRequestSourceQuestion;
  int? _noResponseTtsReadyQuestionMessageId;
  final Set<int> _knownQuestionMessageIds = <int>{};
  final Set<int> _noResponseHandledQuestionMessageIds = <int>{};

  /// 그림 단계 완료(`drawing-complete`)가 접수된 뒤 켜진다.
  ///
  /// 이 뒤로 세션은 `CONVERSING`이므로 캔버스 저장은 막히고 대화만 진행한다.
  bool _drawingStageFinished = false;

  /// 캔버스 왼쪽 위에 띄우는 안내다. 무엇을 그리는 시간인지 아이가 언제든
  /// 확인할 수 있어야 한다. HTP 는 집·나무·사람을 순서대로 그리므로 몇 번째인지
  /// 함께 알려 준다.
  String get _activityTitle {
    final activity = widget.activityContext;
    if (!activity.isHtp) return '그림일기';
    final subject = switch (activity.drawingSubject) {
      'HOUSE' => '집 그리기',
      'TREE' => '나무 그리기',
      'PERSON' => '사람 그리기',
      _ => 'HTP 그림',
    };
    return '${activity.stepOrder ?? 1}/$_htpStepCount단계 · $subject';
  }

  /// HTP 는 집·나무·사람 세 단계다.
  static const _htpStepCount = 3;

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

  /// AI 질문이 화면에 떠 있는 동안에는 그림보다 대화에만 집중한다.
  ///
  /// 진행 중인 획은 끝까지 확정한 뒤 잠근다. 말풍선이 실제로 표시되는 조건과
  /// 동일하게 유지해야 보이지 않는 오버레이가 입력을 막지 않는다.
  bool get _isConversationFocusMode =>
      _questionDisplayController.isVisible &&
      _activePointer == null &&
      (_canvasLocked || _draftRestoreController.canDraw);

  /// 새 획 또는 복원된 Draft 배경이 있으면 완료 가능한 그림으로 본다.
  bool get _hasDrawingContent =>
      _completedStrokes.isNotEmpty || _draftRestoreController.draft != null;

  CanvasTutorialController? _canvasTutorialController;
  late final bool _ownsCanvasTutorialController;

  /// 도구 안내가 가리킬 실제 위젯 자리다. 툴바와 완료 버튼이 여기에 key 를 심고
  /// 오버레이가 그 key 로 화면 위 위치를 읽는다.
  final CanvasTutorialTargetRegistry _tutorialTargets =
      CanvasTutorialTargetRegistry();

  /// 안내받은 도구를 실제로 한 번 써 봤는지 기억한다.
  final CanvasTutorialPracticeTracker _tutorialPractice =
      CanvasTutorialPracticeTracker();

  /// 안내가 화면에 떠 있는지. 툴바 제한을 잠시 풀지 판단하는 데 쓴다.
  bool _isTutorialVisible = false;

  /// 사람·나무·집 그림에서 안내를 위해 도구·색상을 잠시 열어 둔 상태다.
  ///
  /// HTP 검사는 연필·검정으로만 그린다. 그런데 아이가 처음 만나는 캔버스가 HTP 이면
  /// 색과 다른 도구를 한 번도 못 보고 지나간다. 안내 동안에는 툴바를 그림일기와
  /// 똑같이 열어 눌러 보게 하고, 안내가 끝나면 다시 연필·검정으로 되돌린다.
  /// 안내 중에는 캔버스 입력이 막혀 있어 이 사이에 색이 있는 자국이 남지는 않는다.
  bool get _htpToolTrial => widget.activityContext.isHtp && _isTutorialVisible;

  @override
  void initState() {
    super.initState();
    if (widget.activityContext.isHtp) {
      _toolState = const DrawingToolState(
        instrument: DrawingInstrument.pencil,
        color: AppColors.canvasSwatchCharcoal,
        width: _regular,
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _ownsDocumentController = widget.documentController == null;
    _documentController =
        widget.documentController ?? DrawingDocumentController();
    _documentController.addListener(_handleDocumentChanged);
    _cursorController = DrawingCursorController(
      DrawingCursorState(
        visible: false,
        documentPosition: Offset.zero,
        instrument: _toolState.instrument,
        eraserMode: _toolState.eraserMode,
        documentWidth: _toolState.width,
        deviceKind: ui.PointerDeviceKind.touch,
      ),
    );
    _companionSnapshot = widget.companion;
    final parsedChildId = int.tryParse(widget.childId);
    final tutorialApplicable =
        !widget.resumeConversation &&
        widget.inputMethod?.trim().toUpperCase() != 'UPLOAD';
    _ownsCanvasTutorialController =
        tutorialApplicable &&
        widget.canvasTutorialController == null &&
        widget.childRepository != null &&
        parsedChildId != null;
    _canvasTutorialController = tutorialApplicable
        ? widget.canvasTutorialController
        : null;
    final childRepository = widget.childRepository;
    if (tutorialApplicable &&
        _canvasTutorialController == null &&
        childRepository != null &&
        parsedChildId != null) {
      _canvasTutorialController = CanvasTutorialController(
        childId: parsedChildId,
        loadProgress: childRepository.getTutorialProgress,
        saveProgress: childRepository.updateTutorialProgress,
      );
    }
    _canvasTutorialController?.addListener(_handleTutorialChanged);
    unawaited(_canvasTutorialController?.load());
    final ttsRepository = widget.questionTtsRepository;
    final playerFactory = widget.questionAudioPlayerFactory;
    if (ttsRepository != null && playerFactory != null) {
      _questionTtsController = AiQuestionTtsController(
        ttsRepository,
        playerFactory(),
        request: QuestionTtsRequest(voice: _companionSnapshot.ttsVoice),
      );
    }
    _questionDisplayController = AiQuestionDisplayController()
      ..addListener(_handleQuestionDisplayChanged);
    _questionSelectionController = AiQuestionSelectionController(
      revealDelay: widget.questionOptionRevealDelay,
    )..addListener(_handleQuestionSelectionChanged);
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
      _rememberExistingQuestions(messages);
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
    await _restoreExistingQuestionCount();
    if (!mounted) return;
    await _questionController?.load();
  }

  Future<void> _restoreExistingQuestionCount() async {
    final repository = widget.activityRepository;
    final conversationId = _activeConversationId;
    if (repository == null || conversationId == null) return;
    try {
      final messages = await repository.getConversationMessages(conversationId);
      if (mounted) _rememberExistingQuestions(messages);
    } on Object {
      // 질문 수 복원 실패가 기존 대화 복귀 자체를 막지 않게 한다. 서버 상한은
      // next-question 저장 시점에 다시 검증된다.
    }
  }

  /// 문서가 바뀌면 화면을 다시 그린다. 채우기·지우기처럼 이 화면 바깥에서 일어난
  /// 변경도 같은 경로로 반영된다.
  void _handleDocumentChanged() {
    if (mounted) setState(() {});
  }

  /// 안내가 열리고 닫히는 것에 맞춰 툴바 제한을 풀고 다시 건다.
  void _handleTutorialChanged() {
    if (!mounted) return;
    final visible = _canvasTutorialController?.isVisible ?? false;
    final closed = _isTutorialVisible && !visible;
    setState(() {
      _isTutorialVisible = visible;
      // 체험이 끝나면 고른 색·도구를 검사 조건으로 되돌린다. 그대로 두면 아이가
      // 팔레트 없이 빨간 크레용으로 검사 그림을 그리게 된다.
      if (closed && widget.activityContext.isHtp) {
        _toolState = DrawingToolState(
          instrument: DrawingInstrument.pencil,
          eraserMode: _toolState.eraserMode,
          color: AppColors.canvasSwatchCharcoal,
          width: _toolState.width,
        );
      }
    });
    if (closed) _refreshVisibleCursor();
  }

  /// 화면 크기로 캔버스 레이아웃 종류를 정한다. 툴바 배치와 프레임 여백이 이 값에
  /// 따라 달라진다.
  DrawingCanvasDeviceClass _deviceClassFor(Size size) {
    if (size.width >= 900 && size.height > 520) {
      return DrawingCanvasDeviceClass.tablet;
    }
    if (size.width >= 640 && size.height <= 520) {
      return DrawingCanvasDeviceClass.mobileLandscape;
    }
    return DrawingCanvasDeviceClass.mobilePortrait;
  }

  /// 커서에 보여 줄 도구 상태다. 지울 획이 없어 영역 지우개로 넘어간 동안에는
  /// 실제로 하는 일과 같게 영역 지우개 커서를 보여 준다.
  DrawingToolState get _cursorToolState => _strokeEraseFallbackActive
      ? DrawingToolState(
          instrument: DrawingInstrument.eraser,
          eraserMode: DrawingEraserMode.area,
          color: _toolState.color,
          width: _toolState.width,
        )
      : _toolState;

  /// 커서가 보이는 중이면 바뀐 도구·굵기를 즉시 반영한다.
  void _refreshVisibleCursor() {
    final cursor = _cursorController.value;
    if (!cursor.visible) return;
    _cursorController.update(
      documentPosition: cursor.documentPosition,
      toolState: _cursorToolState,
      deviceKind: cursor.deviceKind,
    );
  }

  void _setInstrument(DrawingInstrument instrument) {
    if (widget.activityContext.isHtp &&
        !_htpToolTrial &&
        instrument != DrawingInstrument.pencil &&
        instrument != DrawingInstrument.eraser) {
      return;
    }
    _tutorialPractice.mark(
      instrument == DrawingInstrument.eraser
          ? CanvasTutorialTargetId.eraser
          : CanvasTutorialTargetId.tools,
    );
    setState(() {
      _toolState = DrawingToolState(
        instrument: instrument,
        eraserMode: _toolState.eraserMode,
        color: _toolState.color,
        width: _toolState.width,
      );
    });
    _syncCoordinator.recordToolChange(_toolState.wireToolCode);
    _refreshVisibleCursor();
  }

  void _setColor(Color color) {
    final nextColor = widget.activityContext.isHtp && !_htpToolTrial
        ? AppColors.canvasSwatchCharcoal
        : color;
    _tutorialPractice.mark(CanvasTutorialTargetId.colors);
    setState(() {
      _toolState = DrawingToolState(
        instrument: _toolState.instrument,
        eraserMode: _toolState.eraserMode,
        color: nextColor,
        width: _toolState.width,
      );
      _recentColors.removeWhere(
        (recent) => recent.toARGB32() == nextColor.toARGB32(),
      );
      _recentColors.insert(0, nextColor);
      if (_recentColors.length > 10) {
        _recentColors.removeRange(10, _recentColors.length);
      }
    });
    // 팔레트를 끄는 동안 매 프레임 호출된다. journal이 마지막 값 하나로 합친다.
    _syncCoordinator.recordColorChange(color);
    _refreshVisibleCursor();
  }

  /// 마우스·스타일러스가 캔버스 위를 지나면 현재 도구와 굵기를 커서로 보여 준다.
  void _handleCanvasHover(PointerHoverEvent event) {
    if (_isConversationFocusMode) {
      _cursorController.hide();
      return;
    }
    _cursorController.update(
      documentPosition: event.localPosition,
      toolState: _cursorToolState,
      deviceKind: event.kind,
    );
  }

  void _handleCanvasExit(PointerEvent event) => _cursorController.hide();

  void _setEraserMode(DrawingEraserMode mode) {
    setState(() {
      _toolState = DrawingToolState(
        instrument: DrawingInstrument.eraser,
        eraserMode: mode,
        color: _toolState.color,
        width: _toolState.width,
      );
    });
    _syncCoordinator.recordToolChange(_toolState.wireToolCode);
    _refreshVisibleCursor();
  }

  void _handleEraserMenuAction(DrawingEraserMenuAction action) {
    _tutorialPractice.mark(CanvasTutorialTargetId.eraser);
    switch (action) {
      case DrawingEraserMenuAction.selectStroke:
        _setEraserMode(DrawingEraserMode.stroke);
      case DrawingEraserMenuAction.selectArea:
        _setEraserMode(DrawingEraserMode.area);
      case DrawingEraserMenuAction.clearAll:
        unawaited(_confirmClearAll());
    }
  }

  /// 전체 지우기는 되돌릴 수 없어 아이에게 큰 변화라 한 번 확인한다.
  Future<void> _confirmClearAll() async {
    if (_isApplyingRasterMutation) return;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '그림을 모두 지울까요?',
      message: '지운 그림은 되돌릴 수 없어요.',
      confirmLabel: '모두 지우기',
      cancelLabel: '계속 그리기',
      isDanger: true,
    );
    if (confirmed != true || !mounted) return;
    await _runSnapshotMutation((_) async {
      // 복원된 그림만 남아 있어도 지울 것이 있는 상태다.
      final hadRestoredPixels = _draftRestoreController.backgroundImage != null;
      final localChange = _documentController.clearAll();
      if (!localChange.changed && !hadRestoredPixels) return _noDocumentChange;
      if (hadRestoredPixels) _draftRestoreController.startNewDrawing();
      _syncCoordinator.recordCanvasClear();
      return const DrawingDocumentChange(
        changed: true,
        wireEffect: DrawingWireEffect.none,
      );
    }, revisionAlreadyRecorded: true);
  }

  /// 상세 색상 팔레트를 연다. 태블릿은 팔레트 버튼 옆 팝오버, 모바일은 바텀 시트다.
  Future<void> _openColorPalette(DrawingCanvasDeviceClass deviceClass) async {
    if (widget.activityContext.isHtp && !_htpToolTrial) return;
    var value = HSVColor.fromColor(_toolState.color);
    final previousColor = _toolState.color;

    Widget palette(BuildContext paletteContext, StateSetter setPaletteState) =>
        DrawingColorPalette(
          value: value,
          previousColor: previousColor,
          recentColors: _recentColors,
          onChanged: (next) => setPaletteState(() => value = next),
          onCancel: () => Navigator.of(paletteContext).pop(),
          onConfirm: () => Navigator.of(paletteContext).pop(value.toColor()),
        );

    if (deviceClass == DrawingCanvasDeviceClass.tablet) {
      final selectedColor = await showGeneralDialog<Color>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '색상 팔레트 닫기',
        barrierColor: Colors.black26,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (routeContext, _, _) => Stack(
          children: [
            CompositedTransformFollower(
              link: _paletteAnchorLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, AppSpacing.sm),
              child: Material(
                key: const ValueKey('drawing-tablet-palette-popover'),
                elevation: 12,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: 380,
                  child: StatefulBuilder(
                    builder: (context, setPaletteState) =>
                        palette(context, setPaletteState),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      if (selectedColor != null && mounted) _setColor(selectedColor);
      return;
    }

    final selectedColor = await showModalBottomSheet<Color>(
      context: context,
      isDismissible: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ConstrainedBox(
        key: const ValueKey('drawing-mobile-palette-sheet'),
        constraints: const BoxConstraints(maxWidth: 480),
        child: StatefulBuilder(
          builder: (context, setPaletteState) =>
              palette(context, setPaletteState),
        ),
      ),
    );
    if (selectedColor != null && mounted) _setColor(selectedColor);
  }

  void _setThickness(double thickness) {
    _tutorialPractice.mark(CanvasTutorialTargetId.thickness);
    setState(() {
      _toolState = DrawingToolState(
        instrument: _toolState.instrument,
        eraserMode: _toolState.eraserMode,
        color: _toolState.color,
        width: thickness,
      );
    });
    // 슬라이더를 끄는 동안 매 프레임 호출된다. journal이 마지막 값 하나로 합친다.
    _syncCoordinator.recordThicknessChange(thickness);
    _refreshVisibleCursor();
  }

  void _rememberExistingQuestions(
    Iterable<ActivityConversationMessageDto> messages,
  ) {
    for (final message in messages) {
      if (message.isQuestion) _knownQuestionMessageIds.add(message.messageId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelNoResponseTimer();
    _documentController.removeListener(_handleDocumentChanged);
    if (_ownsDocumentController) _documentController.dispose();
    _cursorController.dispose();
    _canvasTutorialController?.removeListener(_handleTutorialChanged);
    if (_ownsCanvasTutorialController) _canvasTutorialController?.dispose();
    _tutorialPractice.dispose();
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
  void didChangeMetrics() {
    _finishActiveStrokeForLayoutChange();
    super.didChangeMetrics();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      if (!_canvasLocked) _syncCoordinator.resume();
      _resumeNoResponseTimer();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _appInBackground = true;
      _invalidateNoResponseRequest();
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
        maxQuestionCount: widget.maxQuestionCount,
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
      _cancelNoResponseTimer();
      _noResponseRequestInFlight = false;
      _awaitingNoResponseQuestion = false;
      _noResponseRequestSourceQuestion = null;
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
    if (questionController?.status != AiQuestionStatus.success) {
      _cancelNoResponseTimer();
      if (questionController?.status != AiQuestionStatus.loading) {
        _noResponseRequestInFlight = false;
      }
      if (mounted) setState(() {});
      return;
    }
    final question = _questionController?.question;
    if (!mounted ||
        _appInBackground ||
        _conversationEndController?.completed == true ||
        question == null) {
      return;
    }
    _knownQuestionMessageIds.add(question.messageId);
    _noResponseTtsReadyQuestionMessageId = null;
    if (_awaitingNoResponseQuestion) {
      _noResponseHandledQuestionMessageIds.add(question.messageId);
      _awaitingNoResponseQuestion = false;
      _noResponseRequestInFlight = false;
      _noResponseRequestSourceQuestion = null;
    }
    _lastQuestionMessageId = question.messageId;
    // 아이가 되묻기에 **말로** 그만하겠다고 확인했으면 이 메시지는 질문이 아니라 맺음말이다
    // (S15P11B209-951). 화면에 띄워 답을 기다리지 않고 곧바로 끝낸다. 맺음말 자체는 서버가
    // 대화 기록의 마지막 AI 메시지로 저장해 두므로 리포트에는 남는다.
    // 모르는 값은 평범한 질문으로 다룬다. 서버가 새 종료 대상을 먼저 배포하더라도 구버전
    // 앱이 질문을 삼켜 대화가 멈추는 것보다 그대로 이어지는 편이 낫다.
    final stopTarget = question.confirmedStopTarget;
    if (stopTarget != null && _confirmedStopTargets.contains(stopTarget)) {
      unawaited(_handleConfirmedStopTarget(stopTarget));
      return;
    }
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
          unawaited(_prepareNoResponseTimerAfterTts(question));
        } else {
          unawaited(_prepareVoiceAnswerForQuestion(question));
        }
      }
    });
  }

  /// 말로 확인한 그만하기를 실제 종료로 옮긴다 (S15P11B209-951).
  ///
  /// 칩 선택(938)과 **같은 경로**를 탄다. 대화 종료는 아이가 방금 확인했으므로 다시 묻지
  /// 않고, 그림 활동 완료는 기존 '다 그렸어요!' 확인·회고 흐름을 그대로 태운다 — 새 경로를
  /// 만들면 회고 저장 단계를 건너뛴다.
  ///
  /// 호출부가 [_confirmedStopTargets]로 걸러 아는 값만 넘긴다.
  Future<void> _handleConfirmedStopTarget(String target) async {
    switch (target) {
      case confirmedStopConversation:
        await _completeConversationAutomatically(
          ConversationCompletionReason.childRequest,
        );
      case confirmedStopActivity:
        await _confirmAndComplete();
    }
  }

  Future<void> _prepareNoResponseTimerAfterTts(AiQuestion question) async {
    await _questionTtsController?.playQuestion(question);
    if (!_isVisibleCurrentQuestion(question)) return;
    _markNoResponseTtsReady(question);
  }

  void _markNoResponseTtsReady(AiQuestion question) {
    _noResponseTtsReadyQuestionMessageId = question.messageId;
    _scheduleNoResponseTimerIfReady(question);
  }

  void _scheduleNoResponseTimerIfReady(AiQuestion question) {
    if (_noResponseTtsReadyQuestionMessageId != question.messageId ||
        !_questionSelectionController.optionsVisible) {
      return;
    }
    _scheduleNoResponseTimer(question);
  }

  bool _isVisibleCurrentQuestion(AiQuestion question) =>
      mounted &&
      !_appInBackground &&
      _conversationEndController?.completed != true &&
      _questionDisplayController.isVisible &&
      _questionDisplayController.visibleQuestion?.messageId ==
          question.messageId &&
      _questionController?.question?.messageId == question.messageId;

  bool _canScheduleNoResponse(AiQuestion question) =>
      _isVisibleCurrentQuestion(question) &&
      !_noResponseRequestInFlight &&
      !_noResponseHandledQuestionMessageIds.contains(question.messageId) &&
      _knownQuestionMessageIds.length < widget.maxQuestionCount;

  void _scheduleNoResponseTimer(AiQuestion question) {
    _cancelNoResponseTimer();
    if (!_canScheduleNoResponse(question)) return;
    final generation = _noResponseGeneration;
    _noResponseTimer = Timer(widget.noResponseTimeout, () {
      if (generation != _noResponseGeneration) return;
      _noResponseTimer = null;
      unawaited(_requestQuestionAfterNoResponse(question));
    });
  }

  void _cancelNoResponseTimer() {
    _noResponseTimer?.cancel();
    _noResponseTimer = null;
    _noResponseGeneration += 1;
  }

  void _invalidateNoResponseRequest() {
    _cancelNoResponseTimer();
    if (!_noResponseRequestInFlight && !_awaitingNoResponseQuestion) return;
    final sourceQuestion = _noResponseRequestSourceQuestion;
    _noResponseRequestInFlight = false;
    _awaitingNoResponseQuestion = false;
    _noResponseRequestSourceQuestion = null;
    if (mounted &&
        sourceQuestion != null &&
        _questionController?.isLoading == true) {
      // restore()의 generation 증가를 이용해 이미 전송된 요청의 늦은 결과가
      // 사용자 입력이나 lifecycle 전환 뒤 화면을 덮어쓰지 못하게 한다.
      _questionController?.restore(sourceQuestion);
    }
  }

  void _resumeNoResponseTimer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _appInBackground) return;
      final loaded = _questionController?.question;
      final visible = _questionDisplayController.visibleQuestion;
      if (_questionController?.status == AiQuestionStatus.success &&
          loaded != null &&
          (!_questionDisplayController.isVisible ||
              loaded.messageId != visible?.messageId)) {
        _handleQuestionChanged();
        return;
      }
      if (visible != null && _questionDisplayController.isVisible) {
        if (_noResponseTtsReadyQuestionMessageId == visible.messageId) {
          _scheduleNoResponseTimerIfReady(visible);
        } else {
          unawaited(_prepareNoResponseTimerAfterTts(visible));
        }
      }
    });
  }

  Future<void> _requestQuestionAfterNoResponse(AiQuestion question) async {
    if (!_canScheduleNoResponse(question)) return;
    _noResponseRequestInFlight = true;
    _awaitingNoResponseQuestion = true;
    _noResponseRequestSourceQuestion = question;
    _noResponseHandledQuestionMessageIds.add(question.messageId);
    await _questionTtsController?.stop();
    await _voiceRecordingController?.cancel();
    if (!mounted ||
        _appInBackground ||
        !_noResponseRequestInFlight ||
        _noResponseRequestSourceQuestion?.messageId != question.messageId) {
      return;
    }
    await _questionController?.loadNext();
    if (mounted && _questionController?.status != AiQuestionStatus.loading) {
      _noResponseRequestInFlight = false;
    }
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
    _markNoResponseTtsReady(question);
    final started = await recordingController.start();
    if (kDebugMode) {
      debugPrint(
        '[VOICE_AUTO] recording_start messageId=${question.messageId} '
        'started=$started status=${recordingController.status.name}',
      );
    }
  }

  void _handleQuestionDisplayChanged() {
    if (_isConversationFocusMode) _cursorController.hide();
    if (mounted) setState(() {});
  }

  void _handleQuestionSelectionChanged() {
    final question = _questionDisplayController.visibleQuestion;
    if (question != null && _questionSelectionController.optionsVisible) {
      _scheduleNoResponseTimerIfReady(question);
    }
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
      _invalidateNoResponseRequest();
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
        VoiceAnswerUploadStatus.consentRequired) {
      // 음성 답변이 거절됐으면 아이에게 남은 수단은 선택지뿐이다. 여기서 띄우지 않으면
      // "골라서 답해도 돼" 안내만 보이고 고를 것이 없다.
      _questionSelectionController.revealOptions();
      if (kDebugMode) {
        debugPrint('[VOICE_UPLOAD] rejected reason=VOICE_CONSENT_REQUIRED');
      }
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
    // STT가 실패(무음·저신뢰)했거나 지연되면 아이는 답을 보내지 못한 상태다. 질문을 다시
    // 보여주고 선택지를 띄워 대화를 이어가게 한다 — 그러지 않으면 화면이 멈춘 것처럼 된다.
    if (controller?.status == SttResultStatus.failure ||
        controller?.status == SttResultStatus.delayed) {
      _revealOptionsForPendingQuestion();
    }
    if (mounted) setState(() {});
  }

  /// 답변 수단을 잃은 질문에 선택지를 다시 띄운다.
  ///
  /// 업로드 성공 시 [_questionDisplayController]를 dismiss했으므로 다시 보이게 해야 한다.
  /// 같은 messageId는 [AiQuestionDisplayController.receive]가 두 번 받지 않으니 표시
  /// 플래그만 되살린다.
  void _revealOptionsForPendingQuestion() {
    final question = _questionDisplayController.visibleQuestion;
    if (question == null || question.options.isEmpty) return;
    _questionDisplayController.restore();
    _questionSelectionController.revealOptions();
  }

  void _retryVoiceAnswerUpload() {
    unawaited(_voiceAnswerUploadController?.retry());
  }

  Future<void> _selectQuestionOption(String optionId) async {
    final question = _questionDisplayController.visibleQuestion;
    final controller = _answerSubmissionController;
    if (question == null || controller == null) return;
    _invalidateNoResponseRequest();
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
      // 아이가 그만하겠다고 고른 칩이면 다음 질문을 요청하지 않는다(S15P11B209-938).
      // AI 는 무엇을 그만할지 되묻기만 하고, 실제로 끝내는 것은 여기서 한다.
      if (await _handleStopIntentOption(optionId)) return;
      await _requestFollowingQuestion(controller.answerMessageId);
    }
  }

  /// AI 되묻기(S15P11B209-938)에 아이가 답한 칩을 실제 종료로 옮긴다.
  ///
  /// 두 종료는 무게가 다르다. 대화 종료는 그림을 계속 그릴 수 있어 가볍지만, 그림 활동
  /// 완료는 회고 저장과 다음 단계로 이어져 되돌릴 수 없다. 그래서 대화 종료는 바로
  /// 처리하고(아이가 방금 골랐으므로 다시 묻지 않는다), 활동 완료는 기존 '다 그렸어요!'
  /// 확인·회고 흐름을 그대로 태운다 — 새 경로를 만들면 회고 저장 단계를 건너뛴다.
  ///
  /// @return 종료를 처리해 다음 질문 요청을 건너뛰어야 하면 true
  Future<bool> _handleStopIntentOption(String optionId) async {
    switch (optionId) {
      case _endTalkOptionId:
        await _completeConversationAutomatically(
          ConversationCompletionReason.childRequest,
        );
        return true;
      case _endActivityOptionId:
        await _confirmAndComplete();
        return true;
      default:
        return false;
    }
  }

  Future<void> _skipQuestion() async {
    final question = _questionDisplayController.visibleQuestion;
    final controller = _questionSkipController;
    if (question == null || controller == null) return;
    _invalidateNoResponseRequest();
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
    _invalidateNoResponseRequest();
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
    _invalidateNoResponseRequest();
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
    _invalidateNoResponseRequest();
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
    if (_isConversationFocusMode ||
        _activePointer != null ||
        _voiceRecordingController?.isRecording == true) {
      _cursorController.hide();
      return;
    }
    // 스냅샷을 만드는 중에는 새 입력을 받지 않는다. 업로드가 시작된 뒤에는
    // 아이가 기다리지 않도록 다시 그릴 수 있게 풀어 준다.
    if (_isApplyingRasterMutation && !_rasterMutationAllowsDrawing) {
      _cursorController.hide();
      return;
    }
    _updateCursor(event);
    switch (_toolState.instrument) {
      case DrawingInstrument.crayon:
      case DrawingInstrument.pencil:
      case DrawingInstrument.brush:
        _beginSupportedStroke(event, DrawingTool.pen);
      case DrawingInstrument.eraser
          when _toolState.eraserMode == DrawingEraserMode.area:
        _beginSupportedStroke(event, DrawingTool.eraser);
      case DrawingInstrument.eraser:
        if (_isApplyingRasterMutation) return;
        _beginStrokeEraseGesture(event);
      case DrawingInstrument.fill:
        if (_isApplyingRasterMutation) return;
        unawaited(_applyFill(event.localPosition));
    }
  }

  void _beginSupportedStroke(PointerDownEvent event, DrawingTool tool) {
    _beginDrawingInput();
    setState(() {
      _activePointer = event.pointer;
      _activeStroke = DrawingStroke(
        points: [_pointFrom(event)],
        color: _toolState.color,
        thickness: _toolState.width,
        tool: tool,
        brushProfile: _toolState.brushProfile,
      );
    });
  }

  /// 획 지우개는 지운 결과를 event 로 표현할 수 없어 스냅샷으로만 남는다.
  /// 제스처 한 번이 undo 한 번이 되도록 컨트롤러에 묶음을 열어 둔다.
  void _beginStrokeEraseGesture(PointerDownEvent event) {
    setState(() {
      _isApplyingRasterMutation = true;
      _rasterMutationAllowsDrawing = false;
      _isStrokeEraseGestureActive = true;
      _strokeEraseFallbackActive = false;
      _activePointer = event.pointer;
      _activeStroke = null;
    });
    _beginDrawingInput();
    _documentController.beginStrokeEraseGesture();
    try {
      _eraseStrokeOrStartFallback(event);
    } on Object {
      _cancelStrokeEraseGesture();
      rethrow;
    }
  }

  /// 지울 획이 없고 복원된 그림만 남아 있으면 그 위를 영역 지우개로 문지른다.
  void _eraseStrokeOrStartFallback(PointerEvent event) {
    if (_strokeEraseFallbackActive) {
      setState(() {
        _activeStroke = _activeStroke!.addPoint(_pointFrom(event));
      });
      _updateCursor(event);
      return;
    }
    final removed = _documentController.eraseStrokeAt(
      event.localPosition,
      radius: _toolState.width / 2,
    );
    if (removed || _draftRestoreController.backgroundImage == null) return;
    setState(() {
      _strokeEraseFallbackActive = true;
      _activeStroke = DrawingStroke(
        points: [_pointFrom(event)],
        color: _toolState.color,
        thickness: _toolState.width,
        tool: DrawingTool.eraser,
      );
    });
    _updateCursor(event);
  }

  void _extendStroke(PointerMoveEvent event) {
    if (_activePointer != event.pointer) {
      _cursorController.hide();
      return;
    }
    _updateCursor(event);
    if (_isStrokeEraseGestureActive && !_rasterMutationAllowsDrawing) {
      try {
        _eraseStrokeOrStartFallback(event);
      } on Object {
        _cancelStrokeEraseGesture();
        rethrow;
      }
      return;
    }
    if (_activeStroke == null) return;
    setState(() {
      _activeStroke = _activeStroke!.addPoint(_pointFrom(event));
    });
  }

  void _endStroke(PointerEvent event) {
    if (_activePointer != event.pointer) {
      _cursorController.hide();
      return;
    }
    if (_isStrokeEraseGestureActive && !_rasterMutationAllowsDrawing) {
      unawaited(_finishStrokeEraseGesture(event));
      return;
    }
    final stroke = _activeStroke;
    final completed = event is PointerUpEvent && stroke != null;
    setState(() {
      if (completed) {
        _documentController.addStroke(stroke);
      }
      _activeStroke = null;
      _activePointer = null;
    });
    if (completed) {
      _syncCoordinator.recordStroke(stroke, _documentSize);
      _endDrawingInput();
    }
    if (event is PointerCancelEvent ||
        event.kind == ui.PointerDeviceKind.touch) {
      _cursorController.hide();
    } else {
      _updateCursor(event);
    }
  }

  Future<void> _finishStrokeEraseGesture(PointerEvent event) async {
    var change = const DrawingDocumentChange(
      changed: false,
      wireEffect: DrawingWireEffect.none,
    );
    try {
      if (event is PointerCancelEvent) {
        _documentController.cancelStrokeEraseGesture();
      } else {
        change = _documentController.endStrokeEraseGesture(
          fallbackStroke: _strokeEraseFallbackActive ? _activeStroke : null,
        );
        if (change.wireStroke case final wireStroke?) {
          _syncCoordinator.recordStroke(wireStroke, _documentSize);
        }
      }
      if (mounted) {
        setState(() {
          _activeStroke = null;
          _activePointer = null;
        });
      } else {
        _activeStroke = null;
        _activePointer = null;
      }
      if (change.changed) {
        await _persistRasterChange(
          change,
          revisionAlreadyRecorded: change.wireStroke != null,
          // 획 지우개 제스처는 이벤트를 남기지 않지만 문서에서는 되돌릴 수 있는
          // 변경 하나다. journal이 이를 모르면 뒤이은 UNDO가 이벤트로 나가지 않는다.
          undoableSnapshotChange: true,
        );
      }
    } on Object {
      _documentController.cancelStrokeEraseGesture();
      rethrow;
    } finally {
      _releaseStrokeEraseGesture(event);
    }
  }

  void _cancelStrokeEraseGesture() {
    _documentController.cancelStrokeEraseGesture();
    _activeStroke = null;
    _activePointer = null;
    _releaseStrokeEraseGesture(null);
  }

  void _releaseStrokeEraseGesture(PointerEvent? event) {
    if (!_isStrokeEraseGestureActive) return;
    _endDrawingInput();
    if (!mounted) {
      _isStrokeEraseGestureActive = false;
      _strokeEraseFallbackActive = false;
      _isApplyingRasterMutation = false;
      _rasterMutationAllowsDrawing = false;
      return;
    }
    setState(() {
      _isStrokeEraseGestureActive = false;
      _strokeEraseFallbackActive = false;
      _isApplyingRasterMutation = false;
      _rasterMutationAllowsDrawing = false;
    });
    if (event == null ||
        event is PointerCancelEvent ||
        event.kind == ui.PointerDeviceKind.touch) {
      _cursorController.hide();
    } else {
      _updateCursor(event);
    }
  }

  /// 문서 밖으로 나간 포인터는 커서를 숨긴다.
  ///
  /// 터치도 그리는 동안에는 커서를 보여 준다. 손을 떼고 나면 [_endStroke] 가
  /// 숨기므로 손가락이 없는데 커서만 남는 일은 없다.
  void _updateCursor(PointerEvent event) {
    if (_isConversationFocusMode) {
      _cursorController.hide();
      return;
    }
    final documentBounds = Offset.zero & _documentSize;
    if (!documentBounds.contains(event.localPosition)) {
      _cursorController.hide();
      return;
    }
    _cursorController.update(
      documentPosition: event.localPosition,
      toolState: _cursorToolState,
      deviceKind: event.kind,
    );
  }

  void _beginDrawingInput() {
    _invalidatePendingCompletion();
    _invalidateNoResponseRequest();
    // 새 입력은 진행 중인 객체 탐지 결과를 현재 그림에서 제외
    _objectDetectionController?.onDrawingInputStarted();
    // 그림 입력이 시작되면 질문 오버레이 숨김
    _questionDisplayController.dismiss();
  }

  void _endDrawingInput() => _objectDetectionController?.onDrawingInputEnded();

  Future<ui.Image> _captureRawDocumentImage() async {
    final boundary = _canvasBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError('Drawing document is not ready to capture.');
    }
    return boundary.toImage(pixelRatio: 1);
  }

  /// 찍은 자리와 이어진 같은 색 영역을 현재 색으로 채운다.
  Future<void> _applyFill(Offset documentPoint) async {
    await _runSnapshotMutation(revisionAlreadyRecorded: true, (
      mutationGeneration,
    ) async {
      final source = await _captureRawDocumentImage();
      try {
        final patch = await _fillEngine.createPatch(
          source: source,
          seed: documentPoint,
          replacement: _toolState.color,
        );
        if (patch == null) return _noDocumentChange;
        var transferred = false;
        try {
          // 채우기를 계산하는 사이에 화면이 사라졌거나 다른 변경이 끼어들었으면
          // 낡은 결과를 문서에 넣지 않는다.
          if (!mounted || mutationGeneration != _snapshotMutationGeneration) {
            return _noDocumentChange;
          }
          final change = _documentController.addFill(
            patch: patch.image,
            documentSize: patch.documentSize,
          );
          transferred = true;
          // 채우기는 획이 아니라 이미지를 통째로 바꾸지만, 아이가 "여기를 이 색으로
          // 칠했다"는 행동 자체는 관찰 대상이다. 찍은 자리와 고른 색을 함께 남긴다.
          _syncCoordinator.recordFill(
            color: _toolState.color,
            documentPoint: documentPoint,
            canvasSize: _documentSize,
          );
          return change;
        } finally {
          if (!transferred) patch.image.dispose();
        }
      } finally {
        source.dispose();
      }
    });
  }

  /// 콜백은 자신이 시작될 때의 세대를 받는다. 오래 걸리는 계산이 끝났을 때
  /// [_snapshotMutationGeneration] 이 달라졌으면 그 사이 문서가 바뀐 것이다.
  Future<void> _runSnapshotMutation(
    Future<DrawingDocumentChange> Function(int mutationGeneration) mutate, {
    bool revisionAlreadyRecorded = false,
  }) async {
    if (_isApplyingRasterMutation) return;
    final mutationGeneration = ++_snapshotMutationGeneration;
    setState(() {
      _isApplyingRasterMutation = true;
      _rasterMutationAllowsDrawing = false;
    });
    _beginDrawingInput();
    try {
      final change = await mutate(mutationGeneration);
      await _persistRasterChange(
        change,
        revisionAlreadyRecorded: revisionAlreadyRecorded,
      );
    } finally {
      _endDrawingInput();
      if (mounted) {
        setState(() {
          _isApplyingRasterMutation = false;
          _rasterMutationAllowsDrawing = false;
        });
      } else {
        _isApplyingRasterMutation = false;
        _rasterMutationAllowsDrawing = false;
      }
    }
  }

  /// event 를 만들지 않는 변경을 초안으로 곧바로 올린다.
  ///
  /// 한 프레임을 기다려 바뀐 그림이 실제로 그려진 뒤에 캡처해야 서버에 옛 그림이
  /// 올라가지 않는다. 캡처가 끝나면 업로드를 기다리지 않고 다시 그릴 수 있다.
  Future<void> _persistRasterChange(
    DrawingDocumentChange change, {
    bool revisionAlreadyRecorded = false,
    bool undoableSnapshotChange = false,
  }) async {
    if (!change.changed || !mounted) return;
    _invalidatePendingCompletion();
    if (!revisionAlreadyRecorded) {
      _syncCoordinator.recordSnapshotChange(undoable: undoableSnapshotChange);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _rasterMutationAllowsDrawing = true);
    await _syncCoordinator.saveDraftNow();
  }

  /// 화면 크기·방향이 바뀌면 진행 중인 입력은 좌표 기준이 달라져 이어 갈 수 없다.
  ///
  /// 그리던 획은 현재 점까지 완결하고, 아직 확정되지 않은 획 지우기는 되돌린다.
  void _finishActiveStrokeForLayoutChange() {
    if (_isStrokeEraseGestureActive && !_rasterMutationAllowsDrawing) {
      _cancelStrokeEraseGesture();
      return;
    }
    if (_activeStroke == null) return;
    _finishActiveStrokeForSave();
    _cursorController.hide();
  }

  /// lifecycle·route 경계에서 pointer up을 더 이상 받을 수 없는 active stroke를
  /// 현재 점까지 완결한다. 이후 늦은 pointer up은 pointer id가 지워져 무시된다.
  void _finishActiveStrokeForSave() {
    final stroke = _activeStroke;
    if (stroke == null) return;
    final canvasSize = _canvasBoundaryKey.currentContext?.size;
    setState(() {
      _documentController.addStroke(stroke);
      _activeStroke = null;
      _activePointer = null;
    });
    if (canvasSize != null) {
      _syncCoordinator.recordStroke(stroke, _documentSize);
      _objectDetectionController?.onDrawingInputEnded();
    }
  }

  void _undoLastStroke() {
    if (_activeStroke != null || !_documentController.canUndo) return;
    _invalidatePendingCompletion();
    _objectDetectionController?.onDrawingInputStarted();
    // Rebuilding the vector action list also restores pixels removed from a
    // recovered Draft by the last local eraser stroke.
    setState(_documentController.undo);
    _syncCoordinator.recordUndo();
    _objectDetectionController?.onDrawingInputEnded();
  }

  void _redoLastStroke() {
    if (_activeStroke != null || !_documentController.canRedo) return;
    _invalidatePendingCompletion();
    _objectDetectionController?.onDrawingInputStarted();
    setState(_documentController.redo);
    _syncCoordinator.recordRedo();
    _objectDetectionController?.onDrawingInputEnded();
  }

  DrawingPoint _pointFrom(PointerEvent event) => DrawingPoint(
    position: event.localPosition,
    elapsedMilliseconds: _syncCoordinator.elapsedMilliseconds,
    // 측정 정책은 테스트와 같은 단일 구현을 공유한다(S15P11B209-481).
    pressure: DrawingPressurePolicy.resolve(
      kind: event.kind,
      pressure: event.pressure,
      pressureMin: event.pressureMin,
      pressureMax: event.pressureMax,
    ),
  );

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
      // drawing-complete에 보낸 최종 합성 PNG 객체를 그대로 보관해 감정 화면에
      // 전달한다. 다시 캡처하거나 재인코딩하지 않는다.
      _completedDrawingImage = snapshot;
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
      await _openNextHtpSubject(resolution, repository);
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

  /// `steps/next`로 만들어진 다음 주제 세션을 그 세션에 맞는 화면으로 연다.
  ///
  /// 입력 방식을 보지 않고 캔버스를 열면 사진으로 시작한 HTP가 집만 촬영되고
  /// 나무·사람은 캔버스로 열린다(S15P11B209-834). 어느 화면인지는
  /// [DrawingSessionResolution.target] 한 곳에서만 판정한다.
  ///
  /// 사진 세션은 이 화면이 직접 열지 않고 상위 활동 진입 화면에 올려보낸다 —
  /// 여기서 열면 그 화면의 결과를 기다리는 곳이 없어 업로드 후 흐름이 끊긴다.
  Future<void> _openNextHtpSubject(
    DrawingSessionResolution resolution,
    DrawingRepository repository,
  ) async {
    if (resolution.target == DrawingResolutionTarget.photoInput) {
      Navigator.of(context).pop(DrawingRouteResult.advanceTo(resolution));
      return;
    }
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.drawing(widget.childId),
      arguments: DrawingRouteArguments(
        sessionId: resolution.sessionId,
        repository: repository,
        completionSnapshotProvider: widget.completionSnapshotProvider,
        resumeConversation:
            resolution.target == DrawingResolutionTarget.conversation,
        startFresh: true,
        activityContext: resolution.activityContext,
        inputMethod: resolution.inputMethod,
        companion: _companionSnapshot,
      ),
    );
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
    _invalidateNoResponseRequest();
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
    _invalidateNoResponseRequest();
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
        completedDrawingImage: _completedDrawingImage,
      ),
    );
  }

  void _invalidatePendingCompletion() {
    _pendingCompletionKey = null;
    _pendingCompletionImage = null;
    _pendingCompletionMetadata = null;
  }

  /// 지금 그리고 있는 종이의 크기다.
  ///
  /// 종이는 기기·방향마다 크기가 달라서 획 좌표를 이 크기로 나눠 저장한다.
  /// 아직 배치 전이라 크기를 모를 때만 기준 크기를 쓴다.
  Size get _documentSize =>
      _canvasBoundaryKey.currentContext?.size ??
      DrawingCanvasGeometry.documentSize;

  /// 아직 확정되지 않아 transient 층에만 그려야 하는 획이다. 확정된 획은
  /// [DrawingDocumentController.actions] 로 이미 한 번 그려진다.
  List<DrawingStroke> get _transientStrokes =>
      List.unmodifiable([?_activeStroke]);

  Future<void> _stopTtsAndPop() async {
    if (_isLeaving || _isCompleting) return;
    _invalidateNoResponseRequest();
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
        Navigator.of(
          context,
        ).pop(const DrawingRouteResult.backToActivityEntry());
      }
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  /// 다 그렸다고 알리는 오른쪽 아래 버튼이다.
  ///
  /// 질문 말풍선도 같은 자리에 뜬다. 겹치면 이 버튼이 답변·녹음 버튼을 덮으므로
  /// 말풍선이 보이는 동안에는 만들지 않는다. 질문에 답하는 동안에는 캔버스가
  /// 잠겨 그림도 더 그릴 수 없어, 지금 완료할 이유도 없다.
  Widget? _buildCompleteCta(BuildContext context) {
    if (_isConversationFocusMode) return null;
    final cta = CanvasTutorialTargetReporter(
      // 완료 안내는 툴바가 아니라 이 버튼을 가리킨다. Scaffold 가 이 자리를
      // 바꿀 때 옛 버튼과 새 버튼을 잠시 함께 두므로 GlobalKey 는 쓸 수 없다.
      registry: _tutorialTargets,
      id: CanvasTutorialTargetId.complete,
      child: Padding(
        padding: const EdgeInsets.only(
          right: AppSpacing.sm,
          bottom: AppSpacing.sm,
        ),
        child: DrawingCompleteCta(
          enabled:
              !_canvasLocked && _activeStroke == null && _hasDrawingContent,
          isCompleting: _isCompleting,
          compact:
              _deviceClassFor(MediaQuery.sizeOf(context)) !=
              DrawingCanvasDeviceClass.tablet,
          onPressed: () => unawaited(_confirmAndComplete()),
        ),
      ),
    );
    final tutorialController = _canvasTutorialController;
    if (tutorialController == null) return cta;
    // 완료 버튼은 Scaffold 가 body 위에 얹으므로 안내 오버레이가 덮지 못한다.
    // 안내를 보다가 눌러 활동이 끝나 버리지 않도록 여기서 직접 잠근다.
    return AnimatedBuilder(
      animation: tutorialController,
      builder: (context, child) =>
          AbsorbPointer(absorbing: tutorialController.isVisible, child: child),
      child: cta,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_stopTtsAndPop());
    },
    child: Scaffold(
      backgroundColor: AppColors.canvasBackdrop,
      // 다 그렸다고 알리는 버튼은 Scaffold 자리를 쓴다. 직접 Stack 아래쪽에
      // 두면 저장 실패 SnackBar 가 그대로 버튼을 덮어 다시 누를 수 없다.
      floatingActionButton: _buildCompleteCta(context),
      body: Stack(
        children: [
          // 크레용 툴바가 화면 맨 위에 오므로 상태 표시줄 아래로 내려야 한다.
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final screenSize = MediaQuery.sizeOf(context);
                final deviceClass = _deviceClassFor(screenSize);
                final restoreStatus = _draftRestoreController.status;
                final autoRestoreInProgress =
                    widget.autoRestoreDraft &&
                    (restoreStatus == DrawingDraftRestoreStatus.loading ||
                        restoreStatus == DrawingDraftRestoreStatus.found ||
                        restoreStatus ==
                            DrawingDraftRestoreStatus.loadingImage);
                final canvas = _CanvasPanel(
                  repaintBoundaryKey: _canvasBoundaryKey,
                  actions: _documentController.actions,
                  cursorController: _cursorController,
                  onPointerHover: _handleCanvasHover,
                  onPointerExit: _handleCanvasExit,
                  // 확정된 획은 actions 로 한 번만 그린다. 여기에 _visibleStrokes
                  // 를 넘기면 같은 획이 transient 층에도 겹쳐 두 번 그려진다.
                  strokes: _transientStrokes,
                  onPointerDown: _startStroke,
                  onPointerMove: _extendStroke,
                  onPointerUp: _endStroke,
                  backgroundImage: _draftRestoreController.backgroundImage,
                  inputEnabled:
                      !_canvasLocked &&
                      !_isConversationFocusMode &&
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
                  sttResultController: _sttResultController,
                );
                // 말풍선은 종이가 아니라 화면 전체를 기준으로 놓는다. 종이 안에
                // 두면 툴바·활동명이 커질 때마다 종이가 줄어들어 답변 버튼이
                // 화면 밖으로 밀려난다.
                final questionBubble = AiQuestionBubbleOverlay(
                  companion: _companionSnapshot,
                  compact: deviceClass != DrawingCanvasDeviceClass.tablet,
                  question: _questionDisplayController.visibleQuestion,
                  visible: _isConversationFocusMode,
                  selectedOptionId:
                      _questionSelectionController.selectedOptionId,
                  onOptionSelected: (optionId) {
                    unawaited(_selectQuestionOption(optionId));
                  },
                  showResponseActions:
                      _questionSelectionController.optionsVisible,
                  submissionStatus:
                      _answerSubmissionController?.status ??
                      OptionAnswerSubmissionStatus.idle,
                  skipStatus:
                      _questionSkipController?.status ??
                      QuestionSkipStatus.idle,
                  onSkip: () {
                    unawaited(_skipQuestion());
                  },
                  endStatus:
                      _conversationEndController?.status ??
                      ConversationEndStatus.idle,
                  onEnd: () {
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
                  voiceRetryable:
                      _voiceAnswerUploadController?.canRetry ?? false,
                );
                final sidePanel = _DrawingSidePanel(
                  // 도구·색·굵기·완료는 상단 크레용 툴바가 맡는다.
                  showToolControls: false,
                  selectedTool: _tool,
                  selectedColor: _color,
                  selectedThickness: _thickness,
                  onToolChanged: (tool) {
                    setState(() {
                      _toolState = DrawingToolState(
                        instrument: tool == DrawingTool.eraser
                            ? DrawingInstrument.eraser
                            : DrawingInstrument.crayon,
                        eraserMode: DrawingEraserMode.area,
                        color: _toolState.color,
                        width: _toolState.width,
                      );
                    });
                    _syncCoordinator.recordToolChange(_toolState.wireToolCode);
                  },
                  onColorChanged: _setColor,
                  onThicknessChanged: _setThickness,
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
                // 캔버스 위 말풍선이 질문을 보여 주는 동안에는 사이드 패널을
                // 띄우지 않는다. 같은 질문을 두 번 보여 줄 뿐 아니라, 패널이
                // 말풍선의 녹음·답변 버튼을 덮어 탭이 닿지 않는다.
                final questionBubbleVisible = _isConversationFocusMode;
                // 말풍선이 지금 질문을 그대로 보여 주고 있을 때만 패널을 접는다.
                // 말풍선이 이전 질문에 머물러 있으면 새 질문을 볼 곳이 없어진다.
                final bubbleShowsCurrentQuestion =
                    questionBubbleVisible &&
                    _questionDisplayController.visibleQuestion?.messageId ==
                        _questionController?.question?.messageId;
                // 컨트롤러만 있고 아직 보여 줄 질문도 오류도 없으면 패널을 띄우지
                // 않는다. 빈 상자가 캔버스 위에 떠 있게 된다.
                final hasQuestionToShow =
                    _questionController?.question != null ||
                    _questionController?.error != null ||
                    _questionDisplayController.visibleQuestion != null;
                // 대화가 끝나면 패널이 보여 줄 것이 없다. 마지막 질문이 남아
                // 있다고 그대로 두면 빈 흰 상자가 캔버스를 가린다.
                final conversationOver =
                    _questionController?.status ==
                    AiQuestionStatus.conversationComplete;
                final hasStageChrome =
                    (hasQuestionToShow &&
                        !bubbleShowsCurrentQuestion &&
                        !conversationOver) ||
                    _conversationStartError != null ||
                    _htpAdvanceError != null;
                final toolbar = DrawingToolbar(
                  // 안내 중에는 HTP 도 도구·색상을 열어 눌러 보게 한다.
                  pencilOnly: widget.activityContext.isHtp && !_htpToolTrial,
                  tutorialTargets: _tutorialTargets,
                  toolState: _toolState,
                  quickColors: _quickColors,
                  paletteAnchorLink: _paletteAnchorLink,
                  onBack: () => unawaited(_stopTtsAndPop()),
                  canUndo: _activeStroke == null && _documentController.canUndo,
                  canRedo: _activeStroke == null && _documentController.canRedo,
                  saveStatus: _syncCoordinator.saveStatus,
                  onUndo: _undoLastStroke,
                  onRedo: _redoLastStroke,
                  onRetrySave: () => unawaited(_syncCoordinator.retry()),
                  onInstrumentChanged: _setInstrument,
                  onEraserMenuAction: _handleEraserMenuAction,
                  onColorChanged: _setColor,
                  onWidthChanged: _setThickness,
                  onOpenPalette: () =>
                      unawaited(_openColorPalette(deviceClass)),
                );
                final frameInset = switch (deviceClass) {
                  DrawingCanvasDeviceClass.mobilePortrait => AppSpacing.sm,
                  DrawingCanvasDeviceClass.mobileLandscape => AppSpacing.xs,
                  DrawingCanvasDeviceClass.tablet => AppSpacing.md,
                };
                final layoutKey = switch (deviceClass) {
                  DrawingCanvasDeviceClass.mobilePortrait =>
                    'drawing-shell-mobile-portrait',
                  DrawingCanvasDeviceClass.mobileLandscape =>
                    'drawing-shell-mobile-landscape',
                  DrawingCanvasDeviceClass.tablet => 'drawing-shell-tablet',
                };
                return Column(
                  key: ValueKey(layoutKey),
                  children: [
                    // 무엇을 그리는 시간인지 화면 맨 위에 글씨로 둔다. 캔버스
                    // 위에 창처럼 띄우면 그림을 가린다.
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        frameInset + AppSpacing.sm,
                        AppSpacing.xs,
                        frameInset + AppSpacing.sm,
                        AppSpacing.xxs,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _activityTitle,
                          key: const ValueKey('drawing-activity-title'),
                          // 큰 글자 설정에서 여러 줄로 접히면 안내 한 줄이
                          // 화면 높이의 3분의 1을 먹는다. 종이와 답변 버튼이
                          // 밀려나므로 한 줄로 자른다.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.canvasInk,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    AbsorbPointer(
                      key: const ValueKey('drawing-conversation-input-lock'),
                      absorbing: _isConversationFocusMode,
                      child: toolbar,
                    ),
                    Expanded(
                      // 말풍선이 종이 위로 넘쳐 그려질 수 있어야 한다.
                      child: LayoutBuilder(
                        builder: (context, stageConstraints) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: EdgeInsets.all(frameInset),
                                child: DrawingCrayonFrame(
                                  deviceClass: deviceClass,
                                  child: canvas,
                                ),
                              ),
                            ),
                            // 말풍선은 종이보다 커질 수 있다. 종이 안에 가두면
                            // 활동명·툴바가 커질 때마다 종이가 줄어들어 답변
                            // 버튼이 화면 밖으로 밀려난다. 아래를 종이에 붙인
                            // 채 위로만 넘겨 화면 높이까지 쓴다.
                            Positioned.fill(
                              child: OverflowBox(
                                alignment: Alignment.bottomRight,
                                maxHeight: max(
                                  1,
                                  constraints.maxHeight - frameInset,
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [questionBubble],
                                ),
                              ),
                            ),
                            // 도구 사용법 다시 보기. 툴바(위)·쓰다미(오른쪽 아래)와
                            // 겹치지 않으면서 손이 닿기 쉬운 왼쪽 아래에 둔다.
                            if (_canvasTutorialController
                                case final tutorialController?)
                              Positioned(
                                left: frameInset + AppSpacing.md,
                                bottom: frameInset + AppSpacing.md,
                                child: AbsorbPointer(
                                  absorbing: _isConversationFocusMode,
                                  child: AnimatedBuilder(
                                    animation: tutorialController,
                                    builder: (context, _) =>
                                        IconButton.filledTonal(
                                          key: const ValueKey(
                                            'canvas-tutorial-help',
                                          ),
                                          tooltip: '그림 도구 다시 보기',
                                          onPressed: tutorialController.isBusy
                                              ? null
                                              : tutorialController.replay,
                                          icon: const Icon(
                                            Icons.help_outline_rounded,
                                          ),
                                          style: IconButton.styleFrom(
                                            minimumSize: const Size.square(
                                              AppSizes.iconButton,
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            // 보여줄 질문·오류가 있을 때만 띄운다. 빈 상자를 겹쳐 두면
                            // 그 아래 캔버스와 복원 안내가 탭을 받지 못한다.
                            if (hasStageChrome &&
                                stageConstraints.maxWidth > frameInset * 2)
                              Positioned(
                                top: frameInset + AppSpacing.sm,
                                right: frameInset + AppSpacing.sm,
                                child: ConstrainedBox(
                                  key: const ValueKey('drawing-stage-chrome'),
                                  // 종이 영역을 기준으로 잡는다. 화면 높이로 잡으면
                                  // 활동명·툴바만큼 아래에서 시작하는 만큼 그대로
                                  // 화면 밖으로 넘어가, 안내 카드의 재시도 버튼이
                                  // 손에 닿지 않는다.
                                  constraints: BoxConstraints(
                                    maxWidth: min(
                                      360,
                                      stageConstraints.maxWidth -
                                          frameInset * 2,
                                    ),
                                    maxHeight: max(
                                      96,
                                      stageConstraints.maxHeight -
                                          (frameInset + AppSpacing.sm) * 2,
                                    ),
                                  ),
                                  child: sidePanel,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // AI 질문이 떠 있으면 대화가 먼저다. 안내를 함께 띄우면 말풍선의
          // 답변·녹음 버튼을 덮는다. 컨트롤러 상태는 그대로 두므로 질문이
          // 끝나면 같은 단계로 돌아오고 서버 진행도도 움직이지 않는다.
          if (_canvasTutorialController case final tutorialController?
              when !_isConversationFocusMode)
            CanvasToolTutorialOverlay(
              tutorialController,
              targets: _tutorialTargets,
              practice: _tutorialPractice,
              htpTrial: widget.activityContext.isHtp,
            ),
        ],
      ),
    ),
  );
}

class _CanvasPanel extends StatelessWidget {
  const _CanvasPanel({
    required this.repaintBoundaryKey,
    required this.actions,
    required this.cursorController,
    required this.onPointerHover,
    required this.onPointerExit,
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
    required this.sttResultController,
  });

  final GlobalKey repaintBoundaryKey;

  /// 채우기·지우기까지 포함한 문서 변경 이력이다. 획만으로는 캔버스를 다시 그릴 수 없다.
  final List<DrawingCanvasAction> actions;
  final DrawingCursorController cursorController;
  final ValueChanged<PointerHoverEvent> onPointerHover;
  final ValueChanged<PointerEvent> onPointerExit;
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
            DrawingCanvasViewport(
              repaintBoundaryKey: repaintBoundaryKey,
              canvas: DrawingCanvas(
                strokes: strokes,
                actions: actions,
                onPointerDown: onPointerDown,
                onPointerMove: onPointerMove,
                onPointerUp: onPointerUp,
                onPointerHover: onPointerHover,
                onPointerExit: onPointerExit,
                backgroundImage: backgroundImage,
                inputEnabled: inputEnabled,
                onBackgroundLoaded: onBackgroundLoaded,
                onBackgroundError: onBackgroundError,
              ),
              overlayBuilder: (context, metrics) =>
                  ValueListenableBuilder<DrawingCursorState>(
                    valueListenable: cursorController,
                    builder: (context, state, child) =>
                        DrawingCursorOverlay(state: state, metrics: metrics),
                  ),
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
    this.showToolControls = true,
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

  /// 도구·색상·굵기와 완료 버튼을 이 패널에서 그릴지 여부다. 크레용 셸에서는 이것들이
  /// 상단 툴바로 올라가므로 `false`로 두고 질문·오류 카드만 담는다.
  final bool showToolControls;

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
    // 도구를 담지 않을 때는 안내 카드만 띄운다. 흰 판을 함께 깔면 보여 줄 것이
    // 한 줄뿐이어도 종이를 넓게 가린다.
    decoration: showToolControls
        ? BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          )
        : null,
    child: SingleChildScrollView(
      key: const ValueKey('drawing-tool-panel-scroll'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: showToolControls
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.end,
        children: [
          // 도구를 툴바로 옮긴 뒤에는 이 머리말이 가리키는 것이 없다. 질문·오류만
          // 담은 패널 위에 남겨 두면 빈 인사말만 캔버스에 떠 있게 된다.
          if (showToolControls)
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
          if (showToolControls) ...[
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
          ],
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
          if (showToolControls) ...[
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
    this.completedDrawingImage,
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
  final BinaryUploadDto? completedDrawingImage;
}

enum _ReflectionSubmissionKind { emotion, skip }

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
    this.activityRepository,
    this.activityContext = const DrawingActivityContextDto.general(),
    this.inputMethod,
    this.completedDrawingImage,
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
  final ActivityRepository? activityRepository;
  final DrawingActivityContextDto activityContext;
  final BinaryUploadDto? completedDrawingImage;

  /// 이 PERSON 세션이 실제로 쓰는 입력 방식. `steps/next` 호출에 그대로 넘긴다
  /// (백엔드는 PERSON 전환에서 이 값을 상태 전이에 쓰지 않지만, 재생 검증에서
  /// PERSON은 예외로 건너뛰므로 값 자체는 임의로 바뀌어도 안전하다 — 그래도
  /// 세션 실제 값을 보내는 것이 원칙에 맞다).
  final String? inputMethod;

  @override
  State<EmotionSelectScreen> createState() => _EmotionSelectScreenState();
}

class _EmotionSelectScreenState extends State<EmotionSelectScreen> {
  final TextEditingController _titleController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _firstEmotionFocusNode = FocusNode();
  final FocusNode _skipFocusNode = FocusNode();
  final GlobalKey _emotionGridKey = GlobalKey();
  final GlobalKey _confirmationPanelKey = GlobalKey();
  DrawingActivityCompletionController? _activityCompletionController;
  late final bool _ownsActivityCompletionController;
  DrawingEmotionType? _selectedEmotion;
  SaveDrawingReflectionRequestDto? _htpReflectionRequest;
  ApiFailurePresentation? _submissionFailure;
  _ReflectionSubmissionKind? _activeSubmissionKind;
  _ReflectionSubmissionKind? _failedSubmissionKind;
  bool _isSubmitting = false;
  bool _skipConfirmationOpen = false;

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
      _activityCompletionController?.reflectionInputLocked == true ||
      _htpReflectionRequest != null;

  bool get _permanentlyFailed =>
      _submissionFailure != null && !_submissionFailure!.canRetry;

  _ReflectionSubmissionKind? get _lockedSubmissionKind {
    if (_activityCompletionController?.reflectionInputLocked == true) {
      return _activityCompletionController!.reflectionWasSkipped
          ? _ReflectionSubmissionKind.skip
          : _ReflectionSubmissionKind.emotion;
    }
    final htpRequest = _htpReflectionRequest;
    if (htpRequest != null) {
      return htpRequest.skipped
          ? _ReflectionSubmissionKind.skip
          : _ReflectionSubmissionKind.emotion;
    }
    return null;
  }

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
    _scrollController.dispose();
    _firstEmotionFocusNode.dispose();
    _skipFocusNode.dispose();
    if (_ownsActivityCompletionController) {
      _activityCompletionController?.dispose();
    }
    super.dispose();
  }

  void _selectEmotion(DrawingEmotionType emotion) {
    if (_isSubmitting || _reflectionInputLocked || _permanentlyFailed) return;
    setState(() {
      _selectedEmotion = emotion;
      _submissionFailure = null;
      _failedSubmissionKind = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_revealConfirmationPanel());
    });
  }

  Future<void> _revealConfirmationPanel() async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || _selectedEmotion == null) return;
    final panelContext = _confirmationPanelKey.currentContext;
    if (panelContext == null || !panelContext.mounted) return;
    await Scrollable.ensureVisible(
      panelContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 1,
    );
  }

  Future<void> _showSkipConfirmation() async {
    final lockedKind = _lockedSubmissionKind;
    if (_isSubmitting ||
        _skipConfirmationOpen ||
        _permanentlyFailed ||
        (lockedKind != null && lockedKind != _ReflectionSubmissionKind.skip)) {
      return;
    }
    setState(() => _skipConfirmationOpen = true);
    final confirmed = await showEmotionSkipConfirmation(context);
    if (!mounted) return;
    setState(() => _skipConfirmationOpen = false);
    if (confirmed == true) {
      await _submitReflection(skipped: true);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    _skipFocusNode.requestFocus();
  }

  Future<void> _submitReflection({bool skipped = false}) async {
    if (_isSubmitting || _skipConfirmationOpen) return;
    final submissionKind = skipped
        ? _ReflectionSubmissionKind.skip
        : _ReflectionSubmissionKind.emotion;
    final lockedKind = _lockedSubmissionKind;
    if (lockedKind != null && lockedKind != submissionKind) return;
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
    final selectedEmotion = _selectedEmotion;
    if ((!skipped && selectedEmotion == null) || _permanentlyFailed) return;
    setState(() {
      _isSubmitting = true;
      _activeSubmissionKind = submissionKind;
      _submissionFailure = null;
      _failedSubmissionKind = null;
    });
    final rawTitle = _titleController.text;
    var reflection = SaveDrawingReflectionRequestDto(
      title: rawTitle.isEmpty ? null : rawTitle,
      selectedEmotions: skipped ? const [] : [selectedEmotion!],
      expressedEmotionText: null,
      skipped: skipped,
    );
    try {
      final assessmentId = widget.activityContext.htpAssessmentId;
      if (widget.activityContext.isHtp && assessmentId != null) {
        if (repository is! HtpDrawingRepository) {
          throw UnsupportedError('HTP activity is unavailable.');
        }
        reflection = _htpReflectionRequest ??= reflection;
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
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          _submissionFailure = ApiFailurePresentation.of(
            failure,
            childFriendly: true,
          );
          _failedSubmissionKind = submissionKind;
        });
        if (submissionKind == _ReflectionSubmissionKind.emotion) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_revealConfirmationPanel());
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _activeSubmissionKind = null;
        });
      }
    }
  }

  Widget _buildEmotionControls({
    required EmotionChoicePresentation? selectedPresentation,
    required _ReflectionSubmissionKind? lockedSubmissionKind,
    required ApiFailurePresentation? emotionFailure,
    required ApiFailurePresentation? skipFailure,
    required bool inputDisabled,
    required bool hasSaveContract,
    required bool reflectionInputLocked,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        key: _emotionGridKey,
        builder: (context, gridConstraints) {
          final columns = switch (gridConstraints.maxWidth) {
            >= 880 => 5,
            >= 560 => 3,
            _ => 2,
          };
          const gap = AppSpacing.sm;
          final cardWidth =
              (gridConstraints.maxWidth - gap * (columns - 1)) / columns;
          return FocusTraversalGroup(
            child: Wrap(
              spacing: gap,
              runSpacing: AppSpacing.md,
              children: [
                for (
                  var index = 0;
                  index < emotionChoicePresentations.length;
                  index += 1
                )
                  SizedBox(
                    width: cardWidth,
                    child: EmotionChoiceCard(
                      key: ValueKey(
                        'emotion-${emotionChoicePresentations[index].label}',
                      ),
                      presentation: emotionChoicePresentations[index],
                      isSelected:
                          _selectedEmotion ==
                          emotionChoicePresentations[index].emotion,
                      isDimmed:
                          _selectedEmotion != null &&
                          _selectedEmotion !=
                              emotionChoicePresentations[index].emotion,
                      focusNode: index == 0 ? _firstEmotionFocusNode : null,
                      onTap: inputDisabled
                          ? null
                          : () => _selectEmotion(
                              emotionChoicePresentations[index].emotion,
                            ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: selectedPresentation == null
            ? const SizedBox.shrink()
            : Padding(
                key: _confirmationPanelKey,
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: EmotionConfirmationPanel(
                  presentation: selectedPresentation,
                  isSubmitting: _isSubmitting,
                  canConfirm:
                      hasSaveContract &&
                      !_isSubmitting &&
                      !_skipConfirmationOpen &&
                      !_permanentlyFailed &&
                      (lockedSubmissionKind == null ||
                          lockedSubmissionKind ==
                              _ReflectionSubmissionKind.emotion),
                  failure: emotionFailure,
                  onConfirm: () => unawaited(_submitReflection()),
                ),
              ),
      ),
      if (!hasSaveContract && selectedPresentation != null) ...[
        const SizedBox(height: AppSpacing.md),
        const Text(
          '아직 마음을 저장할 수 없어요. 잠시 후 다시 해 주세요.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySm,
        ),
      ],
      if (reflectionInputLocked) ...[
        const SizedBox(height: AppSpacing.md),
        const Text(
          '저장 결과를 확인할 때까지 같은 마음으로 다시 시도해 주세요.',
          key: ValueKey('reflection-input-locked-message'),
          textAlign: TextAlign.center,
          style: AppTypography.bodySm,
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: Alignment.center,
        child: EmotionSkipButton(
          key: const ValueKey('emotion-skip'),
          focusNode: _skipFocusNode,
          isLoading:
              _isSubmitting &&
              _activeSubmissionKind == _ReflectionSubmissionKind.skip,
          onPressed:
              _isSubmitting ||
                  _skipConfirmationOpen ||
                  _permanentlyFailed ||
                  (lockedSubmissionKind != null &&
                      lockedSubmissionKind != _ReflectionSubmissionKind.skip)
              ? null
              : () => unawaited(_showSkipConfirmation()),
        ),
      ),
      if (skipFailure case final failure?) ...[
        const SizedBox(height: AppSpacing.sm),
        EmotionSkipFailureMessage(failure: failure),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final reflectionInputLocked = _reflectionInputLocked;
    final selectedPresentation = _selectedEmotion == null
        ? null
        : emotionPresentationOf(_selectedEmotion!);
    final lockedSubmissionKind = _lockedSubmissionKind;
    final emotionFailure =
        _failedSubmissionKind == _ReflectionSubmissionKind.emotion
        ? _submissionFailure
        : null;
    final skipFailure = _failedSubmissionKind == _ReflectionSubmissionKind.skip
        ? _submissionFailure
        : null;
    final inputDisabled =
        _isSubmitting ||
        _skipConfirmationOpen ||
        reflectionInputLocked ||
        _permanentlyFailed;
    final hasSaveContract =
        widget.sessionId != null && widget.drawingRepository != null;
    return Scaffold(
      backgroundColor:
          selectedPresentation?.canvasBackground ?? AppColors.childCanvas,
      appBar: AppTopBar(
        title: '내 마음 고르기',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedContainer(
          key: const ValueKey('emotion-background'),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          color:
              selectedPresentation?.canvasBackground ?? AppColors.childCanvas,
          child: LayoutBuilder(
            builder: (context, viewportConstraints) {
              final outerPadding = viewportConstraints.maxWidth < 480
                  ? AppSpacing.sm
                  : AppSpacing.lg;
              return SingleChildScrollView(
                key: const ValueKey('emotion-screen-scroll'),
                controller: _scrollController,
                padding: EdgeInsets.all(outerPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Container(
                      padding: EdgeInsets.all(
                        viewportConstraints.maxWidth < 480
                            ? AppSpacing.md
                            : AppSpacing.lg,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F785528),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const EmotionSelectionHeader(),
                          const SizedBox(height: AppSpacing.lg),
                          AppTextField(
                            key: const ValueKey('drawing-title'),
                            controller: _titleController,
                            label: '그림 제목 (선택)',
                            hintText: '그림에 이름을 붙여볼까요?',
                            textInputAction: TextInputAction.done,
                            enabled: !inputDisabled,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          LayoutBuilder(
                            builder: (context, contentConstraints) {
                              final assessmentId =
                                  widget.activityContext.htpAssessmentId;
                              final Widget previewWidget;
                              if (widget.activityContext.isHtp &&
                                  assessmentId != null) {
                                // HTP: 집·나무·사람 3개 그림을 가로로 나란히 보여준다.
                                previewWidget = HtpEmotionPreviewGallery(
                                  childId: widget.childId,
                                  assessmentId: assessmentId,
                                  repository: widget.activityRepository,
                                );
                              } else {
                                // 그림일기: 그림이 1개이므로 HTP 카드 한 칸과 비슷한
                                // 크기로 중앙에 정렬한다(S15P11B209-919).
                                final previewWidth =
                                    (contentConstraints.maxWidth * 0.32)
                                        .clamp(220.0, 380.0)
                                        .toDouble();
                                previewWidget = Center(
                                  child: SizedBox(
                                    width: previewWidth,
                                    child: CompletedDrawingPreview(
                                      completedDrawingImage:
                                          widget.completedDrawingImage,
                                      height: (previewWidth * 0.75)
                                          .clamp(160.0, 300.0)
                                          .toDouble(),
                                    ),
                                  ),
                                );
                              }
                              final controls = _buildEmotionControls(
                                selectedPresentation: selectedPresentation,
                                lockedSubmissionKind: lockedSubmissionKind,
                                emotionFailure: emotionFailure,
                                skipFailure: skipFailure,
                                inputDisabled: inputDisabled,
                                hasSaveContract: hasSaveContract,
                                reflectionInputLocked: reflectionInputLocked,
                              );
                              // 그림일기·HTP 모두 동일 레이아웃: 그림(위) + 감정(아래).
                              return Column(
                                key: const ValueKey('emotion-compact-layout'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  previewWidget,
                                  const SizedBox(height: AppSpacing.lg),
                                  controls,
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
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

  /// 이 화면을 떠나기로 확정했는지. 한 번 서면 되돌리지 않는다 — 늦게 도착한
  /// 상태 조회 결과가 떠나는 화면을 다시 그리거나 polling을 되살리면 안 된다.
  bool _isLeaving = false;

  /// 보호자 전환 확인 Dialog가 열려 있는지. 이동을 확정한 것은 아니므로
  /// 취소하면 되돌리고, 그 사이에 다른 이탈이 겹치는 것만 막는다.
  bool _guardianDialogOpen = false;

  bool get _legacyCompleted =>
      widget.sessionId == null || widget.drawingRepository == null;

  /// 서버가 세션을 최종 실패로 확정한 상태. 이 상태에서만 이탈을 허용한다.
  ///
  /// polling 중·성공 처리 중에는 기존 이탈 방지 정책을 그대로 유지한다 —
  /// 아이가 실수로 빠져나가면 완료 안내를 다시 볼 방법이 없다.
  bool get _isTerminalFailure =>
      !_legacyCompleted &&
      _completionController?.status == ActivityCompletionStatus.terminalFailure;

  /// 이탈 동작을 시작해도 되는지. 이미 떠나기로 했거나 확인 Dialog가 열려 있으면
  /// 두 번째 입력은 조용히 무시한다(연속 탭·back 중복 실행 방지).
  bool get _canStartLeaving => mounted && !_isLeaving && !_guardianDialogOpen;

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
    // 떠나기로 확정한 뒤 도착한 결과는 버린다. dispose 전이라도 화면을 다시
    // 그리면 사용자가 이미 벗어난 상태 안내가 한 프레임 깜빡인다.
    if (mounted && !_isLeaving) setState(() {});
  }

  void _retryStatusCheck() {
    if (_isLeaving) return;
    unawaited(_completionController?.pollUntilTerminal());
  }

  /// 최종 실패 화면에서 아동 홈으로 돌아간다.
  ///
  /// 실패 화면 이전 단계(감정 선택·회고)는 이미 성공해 되돌아갈 곳이 아니고,
  /// 재진입 복구로 들어온 경우에는 이전 route가 아예 없을 수도 있다. 그래서
  /// `pop`하지 않고 아동 홈으로 스택을 다시 세운다 — 홈 route가 아동 문맥을
  /// 확인하므로 문맥이 없으면 라우터가 안전한 화면으로 흘려보낸다.
  void _leaveToChildHome() {
    if (!_canStartLeaving) return;
    setState(() => _isLeaving = true);
    AppNavigation.resetTo(context, AppRoutes.childModeHome(widget.childId));
  }

  /// 완료 화면에서 같은 아이로 새 그림 활동을 시작한다(S15P11B209-777).
  ///
  /// 새 세션 생성·활동 선택은 아동 홈의 진입 흐름이 담당하므로, 여기서
  /// 세션을 직접 만들지 않고 아동 홈으로 스택을 다시 세운다 — 아이는 홈에서
  /// 곧바로 다음 그림을 시작할 수 있다. 이미 접수된 이번 활동의 분석·리포트는
  /// 서버에 남아 보호자가 나중에 확인할 수 있다.
  void _drawAgain() {
    if (!_canStartLeaving) return;
    setState(() => _isLeaving = true);
    AppNavigation.resetTo(context, AppRoutes.childModeHome(widget.childId));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // 계속 직접 처리한다. polling·성공 상태에서는 기존처럼 back을 삼키고,
    // 최종 실패에서만 아동 홈으로 보낸다.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _isTerminalFailure) _leaveToChildHome();
    },
    child: Scaffold(
      backgroundColor: AppColors.childCanvas,
      appBar: _isTerminalFailure
          ? AppTopBar(
              key: const ValueKey('activity-completion-failure-appbar'),
              title: '활동 마무리',
              onBack: _leaveToChildHome,
            )
          : null,
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
            '더 그리고 싶으면 또 그려도 돼요.\n다 했으면 보호자에게 기기를 건네주세요.',
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
            key: const ValueKey('activity-complete-draw-again'),
            label: '또 그리기',
            variant: AppButtonVariant.child,
            leading: const Icon(Icons.brush_rounded),
            onPressed: _drawAgain,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('guardian-handoff'),
            label: '보호자에게 건넸어요',
            variant: AppButtonVariant.secondary,
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
      // 실패 안내만 두면 아이가 이 화면에서 나갈 수 없다(S15P11B209-820).
      // 안내 문구는 그대로 두고 다음 행동만 덧붙인다.
      return _CompletionStatusMessage(
        icon: Icons.error_outline_rounded,
        title: '활동을 마무리하지 못했어요',
        description: '보호자에게 알려 다시 확인해 주세요.',
        button: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              key: const ValueKey('activity-completion-child-home'),
              label: '아동 홈으로 돌아가기',
              variant: AppButtonVariant.child,
              leading: const Icon(Icons.home_rounded),
              onPressed: _leaveToChildHome,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const ValueKey('activity-completion-guardian-home'),
              label: '보호자 화면으로 돌아가기',
              variant: AppButtonVariant.secondary,
              leading: const Icon(Icons.family_restroom_rounded),
              onPressed: () => _confirmGuardianTransition(context),
            ),
          ],
        ),
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
    // 확인 Dialog가 열려 있는 동안에는 아동 홈 이탈·두 번째 Dialog를 막는다.
    if (!_canStartLeaving) return;
    _guardianDialogOpen = true;
    final bool? confirmed;
    try {
      confirmed = await showAppConfirmDialog(
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
    } finally {
      // 취소·바깥 탭으로 닫혔으면 실패 화면에 그대로 남아야 하므로 되돌린다.
      _guardianDialogOpen = false;
    }
    if (confirmed != true || !context.mounted || _isLeaving) return;
    setState(() => _isLeaving = true);
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
