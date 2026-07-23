import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../design_system/design_system.dart';
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
    this.draftRestoreController,
    this.draftImageProviderFactory,
    this.completionSnapshotProvider,
    this.idempotencyKeyProvider,
    this.conversationRepository,
    this.conversationAnswerRepository,
    this.questionSkipRepository,
    this.conversationEndRepository,
    this.conversationId,
    this.basisAnalysisId,
    super.key,
  });

  final String childId;
  final int? sessionId;
  final DrawingRepository? drawingRepository;
  final DrawingSyncPolicy syncPolicy;
  final DrawingSyncCoordinator? syncCoordinator;
  final DrawingDraftRestoreController? draftRestoreController;
  final DraftImageProviderFactory? draftImageProviderFactory;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;
  final String Function()? idempotencyKeyProvider;
  final ConversationRepository? conversationRepository;
  final ConversationAnswerRepository? conversationAnswerRepository;
  final QuestionSkipRepository? questionSkipRepository;
  final ConversationEndRepository? conversationEndRepository;
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
  Color _color = AppColors.drawingInk;
  double _thickness = _regular;
  int? _activePointer;
  final GlobalKey _canvasBoundaryKey = GlobalKey();
  late final DrawingSyncCoordinator _syncCoordinator;
  late final bool _ownsSyncCoordinator;
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
    final conversationRepository = widget.conversationRepository;
    final conversationId = widget.conversationId;
    // 대화 컨텍스트가 있는 활동에서만 질문 조회 시작
    if (conversationRepository != null && conversationId != null) {
      _questionController = AiQuestionController(
        conversationRepository,
        conversationId: conversationId,
        basisAnalysisId: widget.basisAnalysisId,
      );
      _questionController!.addListener(_handleQuestionChanged);
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
        widget.conversationEndRepository ??
            const MockConversationEndRepository(),
        conversationId: conversationId,
        idempotencyKeyProvider:
            widget.idempotencyKeyProvider ?? _createIdempotencyKey,
      )..addListener(_handleConversationEndChanged);
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
    super.dispose();
  }

  void _handleSyncChanged() {
    if (mounted) setState(() {});
  }

  void _handleDraftRestoreChanged() {
    if (mounted) setState(() {});
  }

  void _handleQuestionChanged() {
    final question = _questionController?.question;
    if (!mounted ||
        _conversationEndController?.completed == true ||
        _questionController?.status != AiQuestionStatus.success ||
        question == null) {
      return;
    }
    // 하위 상태 UI의 빌드 중 알림과 겹치지 않도록 다음 프레임에 반영
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accepted = _questionDisplayController.receive(question);
      if (accepted) {
        _questionSelectionController.beginQuestion(question);
        _answerSubmissionController?.beginQuestion();
        _questionSkipController?.beginQuestion();
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

  Future<void> _selectQuestionOption(int optionId) async {
    final question = _questionDisplayController.visibleQuestion;
    if (question == null) return;
    final valid = _questionSelectionController.select(question, optionId);
    final controller = _answerSubmissionController;
    if (!valid || controller == null) return;
    final submitted = await controller.submit(
      questionMessageId: question.messageId,
      optionId: optionId,
    );
    if (submitted) _questionDisplayController.dismiss();
  }

  Future<void> _skipQuestion() async {
    final question = _questionDisplayController.visibleQuestion;
    final controller = _questionSkipController;
    if (question == null || controller == null) return;
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
    final ended = await controller.submit(
      lastQuestionMessageId:
          _questionDisplayController.visibleQuestion?.messageId,
    );
    if (ended) _questionDisplayController.dismiss();
  }

  void _startStroke(PointerDownEvent event) {
    if (_activePointer != null) return;
    _invalidatePendingCompletion();
    // 그림 입력이 시작되면 질문 오버레이 숨김
    _questionDisplayController.dismiss();
    setState(() {
      _activePointer = event.pointer;
      _activeStroke = DrawingStroke(
        points: [_pointFrom(event)],
        color: _color,
        thickness: _thickness,
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
    }
  }

  void _undoLastStroke() {
    if (_activeStroke != null || _completedStrokes.isEmpty) return;
    _invalidatePendingCompletion();
    // A recovered Draft is a bitmap, so Undo intentionally targets only
    // vector strokes created after restore. TODO(API): Revisit when the server
    // provides an authoritative vector-history recovery contract.
    setState(() => _completedStrokes.removeLast());
    _syncCoordinator.recordUndo();
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
            drawingDurationMs: _syncCoordinator.elapsedMilliseconds,
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
      if (response.currentStage != 'ANALYZING') {
        throw StateError('Unexpected drawing stage');
      }
      if (!mounted) return;
      _invalidatePendingCompletion();
      // TODO(CONVERSATION): Replace this temporary MVP transition with
      // ANALYZING polling -> CONVERSING -> REFLECTION.
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.emotionSelect(widget.childId),
        arguments: EmotionSelectRouteArguments(
          sessionId: sessionId,
          repository: repository,
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
          );
          final sidePanel = _DrawingSidePanel(
            selectedColor: _color,
            selectedThickness: _thickness,
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
          if (constraints.maxWidth >= 900) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(flex: 3, child: canvas),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 320, child: sidePanel),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                SizedBox(height: 420, child: canvas),
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
  final int? selectedQuestionOptionId;
  final ValueChanged<int> onQuestionOptionSelected;
  final OptionAnswerSubmissionStatus answerSubmissionStatus;
  final QuestionSkipStatus questionSkipStatus;
  final ConversationEndStatus conversationEndStatus;
  final bool showQuestionResponseActions;
  final VoidCallback onQuestionSkip;
  final VoidCallback onConversationEnd;

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
    child: Stack(
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
    required this.selectedColor,
    required this.selectedThickness,
    required this.onColorChanged,
    required this.onThicknessChanged,
    required this.canComplete,
    required this.isCompleting,
    required this.onComplete,
    required this.saveStatus,
    required this.onRetrySave,
    this.questionController,
  });

  final Color selectedColor;
  final double selectedThickness;
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
          const _ToolHeading(icon: Icons.edit_rounded, label: '펜'),
          const SizedBox(height: AppSpacing.xs),
          const _SelectedToolCard(),
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
            AiQuestionLoadPanel(controller: controller)
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
      Text(
        label,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _SelectedToolCard extends StatelessWidget {
  const _SelectedToolCard();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.leafSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.leaf, width: 2),
    ),
    child: const Row(
      children: [
        Icon(Icons.edit_rounded, color: AppColors.leaf),
        SizedBox(width: AppSpacing.xs),
        Text('기본 펜 선택됨', style: TextStyle(fontWeight: FontWeight.w800)),
      ],
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
  });

  final int? sessionId;
  final DrawingRepository? repository;
}

class EmotionSelectScreen extends StatefulWidget {
  const EmotionSelectScreen({
    required this.childId,
    this.sessionId,
    this.drawingRepository,
    super.key,
  });

  final String childId;
  final int? sessionId;
  final DrawingRepository? drawingRepository;

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
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
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
    if (sessionId == null || repository == null) {
      showAppMessage(context, message: '아직 마음을 저장할 수 없어요. 잠시 후 다시 해 주세요.');
      return;
    }
    if (!skipped && _selectedEmotions.isEmpty) return;
    setState(() => _isSubmitting = true);
    final rawTitle = _titleController.text;
    try {
      await repository.saveReflection(
        sessionId,
        SaveDrawingReflectionRequestDto(
          title: rawTitle.isEmpty ? null : rawTitle,
          selectedEmotions: skipped
              ? const []
              : List.unmodifiable(_selectedEmotions),
          // TODO(REFLECTION): Add direct-expression UI when its UX is agreed.
          expressedEmotionText: null,
          skipped: skipped,
        ),
      );
      if (!mounted) return;
      // TODO(ACTIVITY_COMPLETE): Replace this placeholder transition with
      // POST /drawing-sessions/{id}/complete in the later completion step.
      Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.activityComplete(widget.childId));
    } on Object {
      if (mounted) {
        showAppMessage(
          context,
          message: '마음을 저장하지 못했어요. 고른 내용은 그대로 있으니 다시 해 주세요.',
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                          onTap: _isSubmitting
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
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                          label: '건너뛰기',
                          variant: AppButtonVariant.secondary,
                          isLoading: _isSubmitting,
                          onPressed: _isSubmitting
                              ? null
                              : () =>
                                    unawaited(_submitReflection(skipped: true)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton(
                          key: const ValueKey('emotion-submit'),
                          label: '다 했어요!',
                          variant: AppButtonVariant.child,
                          isLoading: _isSubmitting,
                          onPressed: _isSubmitting || _selectedEmotions.isEmpty
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

class ActivityCompleteScreen extends StatelessWidget {
  const ActivityCompleteScreen({required this.childId, super.key});

  final String childId;

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
                    child: Column(
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

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
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.guardianHome, (route) => false);
  }
}
