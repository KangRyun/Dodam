import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/drawing_session_start_controller.dart';
import '../../application/drawing_upload_error.dart';
import '../../application/photo_upload_validation.dart';
import '../../data/dto/drawing_dtos.dart';
import '../../data/image_picker_photo_adapter.dart';
import '../../domain/photo_picker_adapter.dart';
import '../../domain/repositories/drawing_repository.dart';

enum _Step { methodChoice, photoSource, preview }

/// S15P11B209-466~476: 새 활동을 "캔버스에 직접 그리기"로 시작할지 "사진으로
/// 시작하기"로 시작할지 고르는 화면.
///
/// 461/463/464의 활동 안내 팝업(시작하기)이 확인된 뒤에만 이 화면으로
/// 들어온다. 캔버스를 고르면 기존 CANVAS 세션 생성 흐름을 그대로 쓰고,
/// 사진을 고르면 시스템 카메라 앱 위임 또는 시스템 Photo Picker로 사진을
/// 받아 검증·미리보기 후 UPLOAD 세션을 만들어 업로드한다. 어느 경로든
/// [DrawingSessionResolution]을 pop해 호출부가 기존 Drawing Route로
/// 그대로 이어가게 한다. 사용자가 끝까지 취소하면 `null`을 pop한다.
class InputMethodSelectScreen extends StatefulWidget {
  InputMethodSelectScreen({
    required this.childId,
    required this.drawingTypeId,
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.repository,
    PhotoPickerAdapter? photoPickerAdapter,
    this.dimensionReader = readPhotoDimensions,
    this.now,
    super.key,
  }) : photoPickerAdapter = photoPickerAdapter ?? ImagePickerPhotoAdapter();

  final int childId;
  final int drawingTypeId;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final DrawingRepository repository;
  final PhotoPickerAdapter photoPickerAdapter;
  final PhotoDimensionReader dimensionReader;
  final DateTime Function()? now;

  @override
  State<InputMethodSelectScreen> createState() =>
      _InputMethodSelectScreenState();
}

class _InputMethodSelectScreenState extends State<InputMethodSelectScreen> {
  late final DrawingSessionStartController _controller =
      DrawingSessionStartController(
        repository: widget.repository,
        now: widget.now,
      );

  _Step _step = _Step.methodChoice;

  /// 세션 생성·업로드 등 되돌릴 수 없는 요청이 진행 중일 때만 켜진다.
  /// 켜져 있는 동안 모든 선택 버튼을 잠가 중복 탭·중복 세션 생성을 막는다.
  bool _busy = false;
  bool _canvasError = false;
  DrawingUploadErrorPresentation? _photoPickError;
  DrawingUploadErrorPresentation? _uploadError;
  ValidatedPhoto? _validated;

  /// 사진 경로에서만 지연 생성된다 — 유효한 사진이 확보되기 전에는 세션을
  /// 만들지 않는다. 한 번 만들어지면 재시도·다른 사진 재선택에도 그대로
  /// 재사용해 세션이 여러 개 남지 않게 한다.
  int? _sessionId;

  Future<void> _handleCanvasChoice() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _canvasError = false;
    });
    try {
      final resolution = await _controller.createNewSession(
        childId: widget.childId,
        drawingTypeId: widget.drawingTypeId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(resolution);
    } on Object {
      if (!mounted) return;
      setState(() => _canvasError = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _choosePhotoMethod() {
    if (_busy) return;
    setState(() {
      _step = _Step.photoSource;
      _photoPickError = null;
    });
  }

  void _backToMethodChoice() {
    if (_busy) return;
    setState(() {
      _step = _Step.methodChoice;
      _photoPickError = null;
    });
  }

  Future<void> _pickFrom(Future<PickedPhoto?> Function() pick) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _photoPickError = null;
    });
    try {
      final photo = await pick();
      if (!mounted) return;
      if (photo == null) {
        // 시스템 picker를 사용자가 취소한 것 — 오류가 아니라 이 화면에
        // 그대로 남는다.
        setState(() => _busy = false);
        return;
      }
      final result = await validatePickedPhoto(
        photo,
        dimensionReader: widget.dimensionReader,
      );
      if (!mounted) return;
      switch (result) {
        case PhotoValidationOk(:final validated):
          setState(() {
            _validated = validated;
            _uploadError = null;
            _step = _Step.preview;
            _busy = false;
          });
        case PhotoValidationFailed(:final type):
          setState(() {
            _photoPickError = presentationForValidationError(type);
            _busy = false;
          });
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _photoPickError = presentationForValidationError(
          PhotoValidationErrorType.undecodable,
        );
        _busy = false;
      });
    }
  }

  void _reselectPhoto() {
    if (_busy) return;
    setState(() {
      _validated = null;
      _uploadError = null;
      _step = _Step.photoSource;
    });
  }

  Future<void> _confirmAndUpload() async {
    if (_busy) return;
    final validated = _validated;
    if (validated == null) return;
    setState(() {
      _busy = true;
      _uploadError = null;
    });
    try {
      var sessionId = _sessionId;
      if (sessionId == null) {
        final now = widget.now?.call() ?? DateTime.now();
        final session = await widget.repository.createSession(
          CreateDrawingSessionRequestDto(
            childId: widget.childId,
            drawingTypeId: widget.drawingTypeId,
            inputMethod: 'UPLOAD',
            clientStartedAt: now.toUtc().toIso8601String(),
          ),
        );
        sessionId = session.drawingSessionId;
        if (!mounted) return;
        setState(() => _sessionId = sessionId);
      }

      await widget.repository.uploadDrawing(
        sessionId,
        BinaryUploadDto(
          bytes: validated.photo.bytes,
          fileName: validated.photo.fileName,
          mimeType: validated.mimeType,
        ),
      );

      // 업로드 응답에는 진행 단계가 없어, 이후 화면 이동을 위해 최신 세션
      // 상태를 다시 조회한다(currentStage를 임의로 가정하지 않는다).
      final refreshed = await widget.repository.getSession(sessionId);
      if (!mounted) return;
      Navigator.of(context).pop(
        DrawingSessionResolution(
          sessionId: refreshed.drawingSessionId,
          currentStage: refreshed.currentStage,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _uploadError = DrawingUploadErrorPresentation.of(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final sessionId = _sessionId;
    if (sessionId != null && widget.repository is DrawingSessionDiscarder) {
      try {
        await (widget.repository as DrawingSessionDiscarder).deleteSession(
          sessionId,
        );
      } on Object {
        // 취소는 사용자에게 항상 성공해야 한다 — 정리 실패는 조용히 넘긴다.
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: AppColors.childCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.contentMaxWidth,
                ),
                child: switch (_step) {
                  _Step.methodChoice => _buildMethodChoice(context),
                  _Step.photoSource => _buildPhotoSource(context),
                  _Step.preview => _buildPreview(context),
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildHeader({required String title, required String description}) =>
      Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: 52, color: widget.accentColor),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.titleLg,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.inkMuted),
          ),
        ],
      );

  Widget _buildMethodChoice(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buildHeader(title: widget.title, description: '어떻게 시작할까?'),
      const SizedBox(height: AppSpacing.lg),
      if (_canvasError) ...[
        _ErrorBanner(
          key: const ValueKey('input-method-canvas-error'),
          icon: Icons.error_outline_rounded,
          message: '활동을 시작하지 못했어요. 다시 시도해 주세요.',
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 480;
          final cardWidth = narrow ? constraints.maxWidth : 220.0;
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: cardWidth,
                child: _ChoiceCard(
                  key: const ValueKey('input-method-canvas'),
                  icon: Icons.palette_rounded,
                  title: '그림판에 그리기',
                  description: '화면에 직접 그림을 그려요',
                  color: AppColors.leaf,
                  isLoading: _busy,
                  onTap: _busy ? null : _handleCanvasChoice,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _ChoiceCard(
                  key: const ValueKey('input-method-photo'),
                  icon: Icons.photo_camera_rounded,
                  title: '사진으로 시작하기',
                  description: '그려둔 그림을 사진으로 담아요',
                  color: AppColors.tangerine,
                  onTap: _busy ? null : _choosePhotoMethod,
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      AppButton(
        key: const ValueKey('input-method-cancel'),
        label: '취소',
        variant: AppButtonVariant.secondary,
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
      ),
    ],
  );

  Widget _buildPhotoSource(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buildHeader(title: widget.title, description: '사진을 어떻게 가져올까?'),
      const SizedBox(height: AppSpacing.lg),
      if (_photoPickError case final error?) ...[
        _ErrorBanner(
          key: const ValueKey('input-method-photo-error'),
          icon: error.icon,
          message: error.message,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 480;
          final cardWidth = narrow ? constraints.maxWidth : 220.0;
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: cardWidth,
                child: _ChoiceCard(
                  key: const ValueKey('input-method-camera'),
                  icon: Icons.camera_alt_rounded,
                  title: '카메라로 찍기',
                  description: '지금 바로 촬영해요',
                  color: AppColors.tangerine,
                  isLoading: _busy,
                  onTap: _busy
                      ? null
                      : () =>
                            _pickFrom(widget.photoPickerAdapter.pickFromCamera),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _ChoiceCard(
                  key: const ValueKey('input-method-gallery'),
                  icon: Icons.photo_library_rounded,
                  title: '앨범에서 선택',
                  description: '가지고 있는 사진을 골라요',
                  color: AppColors.lavender,
                  isLoading: _busy,
                  onTap: _busy
                      ? null
                      : () => _pickFrom(
                          widget.photoPickerAdapter.pickFromGallery,
                        ),
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: AppButton(
              key: const ValueKey('input-method-back'),
              label: '뒤로',
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : _backToMethodChoice,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton(
              key: const ValueKey('input-method-cancel'),
              label: '취소',
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildPreview(BuildContext context) {
    final validated = _validated!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '이 사진으로 시작할까?',
          textAlign: TextAlign.center,
          style: AppTypography.titleLg,
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          label: '선택한 사진 미리보기',
          image: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.memory(validated.photo.bytes, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_uploadError case final error?) ...[
          _ErrorBanner(
            key: const ValueKey('input-method-upload-error'),
            icon: error.icon,
            message: error.message,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        AppButton(
          key: const ValueKey('input-method-confirm'),
          label: _uploadError != null ? '다시 시도' : '이 사진 사용하기',
          variant: AppButtonVariant.child,
          isLoading: _busy,
          onPressed: _busy ? null : _confirmAndUpload,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: AppButton(
                key: const ValueKey('input-method-reselect'),
                label: '다시 선택',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _reselectPhoto,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                key: const ValueKey('input-method-preview-cancel'),
                label: '취소',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : () => unawaited(_cancel()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.isLoading = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title, description;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    enabled: onTap != null,
    label: isLoading ? '$title, 준비하는 중' : '$title. $description',
    child: ExcludeSemantics(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 160,
              minWidth: AppSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    const SizedBox.square(
                      // AppButton과 같은 'loading' 키를 노출해 진행 중 상태를
                      // 같은 방식으로 찾을 수 있게 한다.
                      key: ValueKey('loading'),
                      dimension: 48,
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xs),
                        child: CircularProgressIndicator(
                          color: AppColors.tangerine,
                        ),
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 48,
                      color: onTap == null ? AppColors.disabled : color,
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 오류를 색상만으로 구분하지 않도록 아이콘+문구를 함께 보여주는 배너.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: message,
    child: ExcludeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.errorSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.error, size: AppIconSize.lg),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodySm.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
