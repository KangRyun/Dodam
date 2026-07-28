import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../drawing/application/activity_completion_controller.dart';
import '../../../drawing/application/drawing_object_detection_controller.dart';
import '../../../drawing/application/drawing_activity_completion_controller.dart';
import '../../../drawing/application/drawing_sync_coordinator.dart';
import '../../../drawing/application/drawing_draft_restore_controller.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../../drawing/domain/repositories/drawing_repository.dart';
import '../../../drawing/presentation/models/drawing_stroke.dart';
import '../../../drawing/presentation/widgets/drawing_canvas.dart';
import '../../../conversation/conversation.dart';

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
    this.voiceAnswerRepository,
    this.sttResultRepository,
    this.conversationId,
    this.basisAnalysisId,
    super.key,
  });

  final String childId;
  final int? sessionId;
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
  final VoiceAnswerRepository? voiceAnswerRepository;
  final SttResultRepository? sttResultRepository;
  final int? conversationId;
  final int? basisAnalysisId;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  static const _thin = 4.0;
  static const _regular = 8.0;
  static const _thick = 14.0;

  final List<DrawingStroke> _completedStrokes = [];
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
  String? _pendingCompletionKey;
  BinaryUploadDto? _pendingCompletionImage;
  DrawingCompleteMetadataDto? _pendingCompletionMetadata;
  AiQuestionController? _questionController;
  late final AiQuestionDisplayController _questionDisplayController;
  late final AiQuestionSelectionController _questionSelectionController;
  OptionAnswerSubmissionController? _answerSubmissionController;
  QuestionSkipController? _questionSkipController;
  ConversationEndController? _conversationEndController;
  VoiceRecordingController? _voiceRecordingController;
  VoiceAnswerUploadController? _voiceAnswerUploadController;
  SttResultController? _sttResultController;
  bool _conversationSetupStarted = false;
  int? _activeConversationId;
  int? _lastQuestionMessageId;

  @override
  void initState() {
    super.initState();
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
        );
    _syncCoordinator.addListener(_handleSyncChanged);
    _ownsObjectDetectionController = widget.objectDetectionController == null;
    _objectDetectionController = widget.objectDetectionController;
    final sessionId = widget.sessionId;
    final drawingRepository = widget.drawingRepository;
    if (_objectDetectionController == null &&
        sessionId != null &&
        drawingRepository != null) {
      // 그림판은 입력 시점만 전달하고 탐지 상태와 최신 결과 검증은 별도 관리
      _objectDetectionController = DrawingObjectDetectionController(
        saveDraft: _syncCoordinator.saveDraftNow,
        requestDetection: (drawingAssetId) =>
            drawingRepository.requestObjectDetection(
              sessionId,
              ObjectDetectionRequestDto(drawingAssetId: drawingAssetId),
            ),
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
      if (mounted) {
        _syncCoordinator.start(snapshotProvider: _captureCanvasSnapshot);
        unawaited(_draftRestoreController.load());
      }
    });
  }

  @override
  void dispose() {
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

  void _handleSyncChanged() {
    if (mounted) setState(() {});
  }

  void _handleDraftRestoreChanged() {
    if (mounted) setState(() {});
  }

  void _handleObjectDetectionChanged() {
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
        _ensureConversationStarted(result.drawingAnalysisId).then(
          (_) => _questionController?.loadForAnalysis(result.drawingAnalysisId),
        ),
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
  Future<void> _ensureConversationStarted(int analysisId) async {
    if (_conversationSetupStarted) return;
    final conversationRepository = widget.conversationRepository;
    final sessionId = widget.sessionId;
    if (conversationRepository == null || sessionId == null) return;
    _conversationSetupStarted = true;
    try {
      final conversationId = await conversationRepository.startConversation(
        drawingSessionId: sessionId,
        analysisId: analysisId,
        idempotencyKey:
            (widget.idempotencyKeyProvider ?? _createIdempotencyKey)(),
      );
      if (!mounted) return;
      setState(() => _setupConversationControllers(conversationId));
    } on Object {
      // 실패 시 다음 탐지 성공에서 재시도할 수 있도록 플래그를 되돌린다.
      _conversationSetupStarted = false;
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
      DeviceVoiceRecorder(),
      permissionService: DeviceMicrophonePermissionService(),
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
        _questionSelectionController.beginQuestion(
          question,
          scheduleReveal: false,
        );
        _answerSubmissionController?.beginQuestion();
        _questionSkipController?.beginQuestion();
        _voiceAnswerUploadController?.beginQuestion();
        // 질문이 표시되면 선택지보다 먼저 음성 답변 수집 시작
        unawaited(_voiceRecordingController?.start());
      }
    });
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
    if (mounted) setState(() {});
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
    }
    if (mounted) setState(() {});
  }

  void _handleSttResultChanged() {
    if (mounted) setState(() {});
  }

  void _retryVoiceAnswerUpload() {
    unawaited(_voiceAnswerUploadController?.retry());
  }

  Future<void> _selectQuestionOption(String optionId) async {
    final question = _questionDisplayController.visibleQuestion;
    if (question == null) return;
    final valid = _questionSelectionController.select(question, optionId);
    final controller = _answerSubmissionController;
    if (!valid || controller == null) return;
    await _voiceRecordingController?.cancel();
    // BE 답변 계약이 선택 시점 스냅샷(type·value·label)을 요구해 객체째 전달
    final option = question.options.firstWhere(
      (candidate) => candidate.optionId == optionId,
    );
    final submitted = await controller.submit(
      questionMessageId: question.messageId,
      option: option,
    );
    if (submitted) _questionDisplayController.dismiss();
  }

  Future<void> _skipQuestion() async {
    final question = _questionDisplayController.visibleQuestion;
    final controller = _questionSkipController;
    if (question == null || controller == null) return;
    await _voiceRecordingController?.cancel();
    final skipped = await controller.submit(
      questionMessageId: question.messageId,
    );
    if (skipped) _questionDisplayController.dismiss();
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

  void _undoLastStroke() {
    if (_activeStroke != null || _completedStrokes.isEmpty) return;
    _invalidatePendingCompletion();
    _objectDetectionController?.onDrawingInputStarted();
    // Rebuilding the vector action list also restores pixels removed from a
    // recovered Draft by the last local eraser stroke.
    setState(() => _completedStrokes.removeLast());
    _syncCoordinator.recordUndo();
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
    final boundary = _canvasBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    if (bytes.length > 10 * 1024 * 1024) return null;
    return BinaryUploadDto(
      bytes: bytes,
      fileName: 'drawing-draft.png',
      mimeType: 'image/png',
    );
  }

  Future<void> _confirmAndComplete() async {
    if (_isCompleting || _activeStroke != null || _completedStrokes.isEmpty) {
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
    try {
      // TODO(API): Define the authoritative pending-batch/Draft flush order
      // before coordinating a forced flush here.
      final snapshot =
          _pendingCompletionImage ??
          await (widget.completionSnapshotProvider ?? _captureCanvasSnapshot)();
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
      final response = await repository.completeDrawingStage(
        sessionId,
        finalImage: snapshot,
        metadata: metadata,
        idempotencyKey: idempotencyKey,
      );
      if (response.currentStage != 'CONVERSING' ||
          response.nextAction != 'SELECT_EMOTION') {
        throw StateError('Unexpected drawing completion result');
      }
      if (!mounted) return;
      _invalidatePendingCompletion();
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.emotionSelect(widget.childId),
        arguments: EmotionSelectRouteArguments(
          sessionId: sessionId,
          repository: repository,
          conversationId: _activeConversationId,
          conversationAlreadyEnded:
              _conversationEndController?.completed == true,
          conversationEndRepository: widget.conversationEndRepository,
          conversationEndIdempotencyKey:
              _conversationEndController?.requestIdempotencyKey,
          conversationEndRequest: _conversationEndController?.requestSnapshot,
          lastQuestionMessageId: _lastQuestionMessageId,
          idempotencyKeyProvider: widget.idempotencyKeyProvider,
        ),
      );
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '그림을 완료하지 못했어요. 그림은 그대로 있으니 다시 시도해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.childCanvas,
    appBar: AppTopBar(
      title: '그림 활동',
      onBack: () => Navigator.of(context).pop(),
      actions: [
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
          final canvas = _CanvasPanel(
            repaintBoundaryKey: _canvasBoundaryKey,
            strokes: _visibleStrokes,
            onPointerDown: _startStroke,
            onPointerMove: _extendStroke,
            onPointerUp: _endStroke,
            backgroundImage: _draftRestoreController.backgroundImage,
            inputEnabled: _draftRestoreController.canDraw,
            onBackgroundLoaded: _draftRestoreController.markImageLoaded,
            onBackgroundError: _draftRestoreController.markImageFailed,
            restoreStatus: _draftRestoreController.status,
            onContinue: _draftRestoreController.continueDrawing,
            onStartNew: _draftRestoreController.startNewDrawing,
            onRetryQuery: () => unawaited(_draftRestoreController.load()),
            onRetryImage: _draftRestoreController.retryImage,
            question: _questionDisplayController.visibleQuestion,
            showQuestion:
                _questionDisplayController.isVisible &&
                _activePointer == null &&
                _draftRestoreController.canDraw,
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
                !_isCompleting &&
                _activeStroke == null &&
                _completedStrokes.isNotEmpty,
            isCompleting: _isCompleting,
            onComplete: () => unawaited(_confirmAndComplete()),
            saveStatus: _syncCoordinator.saveStatus,
            onRetrySave: () => unawaited(_syncCoordinator.retry()),
            questionController: _questionController,
          );
          final screenSize = MediaQuery.sizeOf(context);
          final useCompactLandscape =
              screenSize.width >= 640 && screenSize.height <= 520;
          final useTabletLayout =
              !useCompactLandscape && screenSize.width >= 900;
          if (useCompactLandscape || useTabletLayout) {
            final padding = useCompactLandscape ? AppSpacing.sm : AppSpacing.lg;
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
                    width: useCompactLandscape ? AppSpacing.sm : AppSpacing.lg,
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
    required this.onBackgroundLoaded,
    required this.onBackgroundError,
    required this.restoreStatus,
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
    required this.sttResultController,
  });

  final GlobalKey repaintBoundaryKey;
  final List<DrawingStroke> strokes;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerMoveEvent> onPointerMove;
  final ValueChanged<PointerEvent> onPointerUp;
  final ImageProvider<Object>? backgroundImage;
  final bool inputEnabled;
  final VoidCallback onBackgroundLoaded;
  final VoidCallback onBackgroundError;
  final DrawingDraftRestoreStatus restoreStatus;
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
            if (!inputEnabled)
              _DraftRestoreOverlay(
                status: restoreStatus,
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
    required this.onContinue,
    required this.onStartNew,
    required this.onRetryQuery,
    required this.onRetryImage,
  });

  final DrawingDraftRestoreStatus status;
  final VoidCallback onContinue;
  final VoidCallback onStartNew;
  final VoidCallback onRetryQuery;
  final VoidCallback onRetryImage;

  @override
  Widget build(BuildContext context) {
    final loading =
        status == DrawingDraftRestoreStatus.loading ||
        status == DrawingDraftRestoreStatus.loadingImage;
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading) const CircularProgressIndicator(),
                  if (loading) const SizedBox(height: AppSpacing.md),
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
                    ),
                  ],
                ],
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
    required this.onRetrySave,
    this.questionController,
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
  final VoidCallback onRetrySave;
  final AiQuestionController? questionController;

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
          SegmentedButton<double>(
            segments: [
              for (final (label, value) in _thicknesses)
                ButtonSegment(value: value, label: Text(label)),
            ],
            selected: {selectedThickness},
            showSelectedIcon: true,
            onSelectionChanged: (values) => onThicknessChanged(values.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (questionController case final controller?)
            AiQuestionLoadPanel(controller: controller, loadOnMount: false)
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
          const SizedBox(height: AppSpacing.lg),
          _SaveStatusIndicator(status: saveStatus, onRetry: onRetrySave),
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

class _SaveStatusIndicator extends StatelessWidget {
  const _SaveStatusIndicator({required this.status, required this.onRetry});

  final DrawingSaveStatus status;
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
          if (status == DrawingSaveStatus.failed)
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
  });

  final int? sessionId;
  final DrawingRepository? repository;
  final int? conversationId, lastQuestionMessageId;
  final bool conversationAlreadyEnded;
  final ConversationEndRepository? conversationEndRepository;
  final String? conversationEndIdempotencyKey;
  final ConversationEndRequest? conversationEndRequest;
  final String Function()? idempotencyKeyProvider;
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
    if (sessionId == null ||
        repository == null ||
        completionController == null) {
      showAppMessage(context, message: '아직 마음을 저장할 수 없어요. 잠시 후 다시 해 주세요.');
      return;
    }
    if (!skipped && _selectedEmotions.isEmpty) return;
    setState(() => _isSubmitting = true);
    final rawTitle = _titleController.text;
    try {
      final completed = await completionController.submit(
        reflection: SaveDrawingReflectionRequestDto(
          title: rawTitle.isEmpty ? null : rawTitle,
          selectedEmotions: skipped
              ? const []
              : List.unmodifiable(_selectedEmotions),
          // TODO(REFLECTION): Add direct-expression UI when its UX is agreed.
          expressedEmotionText: null,
          skipped: skipped,
        ),
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
            completionController.failedStep ==
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
