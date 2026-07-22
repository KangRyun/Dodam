import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';
import '../../../../design_system/design_system.dart';
import '../../../drawing/application/drawing_sync_coordinator.dart';
import '../../../drawing/application/drawing_draft_restore_controller.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';
import '../../../drawing/domain/repositories/drawing_repository.dart';
import '../../../drawing/presentation/models/drawing_stroke.dart';
import '../../../drawing/presentation/widgets/drawing_canvas.dart';

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    required this.childId,
    this.sessionId,
    this.drawingRepository,
    this.syncPolicy = const DrawingSyncPolicy(),
    this.syncCoordinator,
    this.draftRestoreController,
    this.draftImageProviderFactory,
    super.key,
  });

  final String childId;
  final int? sessionId;
  final DrawingRepository? drawingRepository;
  final DrawingSyncPolicy syncPolicy;
  final DrawingSyncCoordinator? syncCoordinator;
  final DrawingDraftRestoreController? draftRestoreController;
  final DraftImageProviderFactory? draftImageProviderFactory;

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

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _handleSyncChanged() {
    if (mounted) setState(() {});
  }

  void _handleDraftRestoreChanged() {
    if (mounted) setState(() {});
  }

  void _startStroke(PointerDownEvent event) {
    if (_activePointer != null) return;
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

  void _showCompletePlaceholder() {
    showAppMessage(context, message: '그림 완료는 다음 단계에서 연결할게요.');
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
          );
          final sidePanel = _DrawingSidePanel(
            selectedColor: _color,
            selectedThickness: _thickness,
            onColorChanged: (color) => setState(() => _color = color),
            onThicknessChanged: (value) => setState(() => _thickness = value),
            canComplete: _activeStroke == null && _completedStrokes.isNotEmpty,
            onComplete: _showCompletePlaceholder,
            saveStatus: _syncCoordinator.saveStatus,
            onRetrySave: () => unawaited(_syncCoordinator.retry()),
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
    required this.onComplete,
    required this.saveStatus,
    required this.onRetrySave,
  });

  final Color selectedColor;
  final double selectedThickness;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onThicknessChanged;
  final bool canComplete;
  final VoidCallback onComplete;
  final DrawingSaveStatus saveStatus;
  final VoidCallback onRetrySave;

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
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.lavenderSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Text(
              '대화와 마이크는 다음 단계에서 만나요.',
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

class EmotionSelectScreen extends StatelessWidget {
  const EmotionSelectScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '감정 선택',
    description: '그림을 그리며 느낀 감정을 고르는 화면이에요.',
    childFriendly: true,
    primaryLabel: '선택 완료',
    onPrimary: () => Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.activityComplete(childId)),
  );
}

class ActivityCompleteScreen extends StatelessWidget {
  const ActivityCompleteScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '활동 완료',
    description: '참 잘했어요. 이제 보호자에게 태블릿을 전달해 주세요.',
    childFriendly: true,
    canPop: false,
  );
}
