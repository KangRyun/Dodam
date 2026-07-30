import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/design_system.dart';
import '../../application/drawing_session_start_controller.dart';
import '../../application/drawing_upload_error.dart';
import '../../application/photo_upload_validation.dart';
import '../../data/device_photo_permission_service.dart';
import '../../data/dto/drawing_dtos.dart';
import '../../data/image_picker_photo_adapter.dart';
import '../../domain/photo_permission_service.dart';
import '../../domain/photo_picker_adapter.dart';
import '../../domain/repositories/drawing_repository.dart';

enum _Step { methodChoice, photoSource, preview }

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
    this.replaceActive = false,
    this.htpAssessmentId,
    this.existingDrawingSessionId,
    this.restoredActivityContext,
    this.htpPhotoUploadEnabled = false,
    this.idempotencyKeyProvider,
    PhotoPickerAdapter? photoPickerAdapter,
    PhotoPermissionService? photoPermissionService,
    this.dimensionReader = readPhotoDimensions,
    this.now,
    super.key,
  }) : assert(
         existingDrawingSessionId == null || htpAssessmentId == null,
         '복원 모드(existingDrawingSessionId)와 전환 모드(htpAssessmentId)는 '
         '동시에 켤 수 없다.',
       ),
       photoPickerAdapter = photoPickerAdapter ?? ImagePickerPhotoAdapter(),
       photoPermissionService =
           photoPermissionService ?? DevicePhotoPermissionService();

  final int childId;
  final int drawingTypeId;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final DrawingRepository repository;
  final bool replaceActive;
  final int? htpAssessmentId;

  /// 이미 만들어진 UPLOAD 세션을 복원한다(사진을 아직 찍지 않은 채 앱이
  /// 종료된 경우). 켜져 있으면 방식 선택 없이 사진 촬영 단계로 바로
  /// 들어가고, 취소해도 이 세션을 삭제하지 않으며, 완료 시 새 세션을
  /// 만들지 않고 이 세션 그대로 업로드·완료한다.
  final int? existingDrawingSessionId;

  /// 복원 모드에서 되돌려줄 `activityContext`(서버 재조회 없이 재진입
  /// 시점에 이미 알고 있는 값을 그대로 사용한다).
  final DrawingActivityContextDto? restoredActivityContext;

  /// 사진으로 시작하기 옵션을 노출할지 여부(S15P11B209-702, 기본 꺼짐).
  final bool htpPhotoUploadEnabled;
  final String Function()? idempotencyKeyProvider;
  final PhotoPickerAdapter photoPickerAdapter;
  final PhotoPermissionService photoPermissionService;
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

  late _Step _step;

  /// 세션 생성·업로드 등 되돌릴 수 없는 요청이 진행 중일 때만 켜진다.
  /// 켜져 있는 동안 모든 선택 버튼을 잠가 중복 탭·중복 세션 생성을 막는다.
  bool _busy = false;
  bool _canvasError = false;
  DrawingUploadErrorPresentation? _photoPickError;
  _PhotoPermissionIssue? _photoPermissionIssue;
  DrawingUploadErrorPresentation? _uploadError;
  int? _uploadProgressPercent;
  ValidatedPhoto? _validated;

  /// 사진 경로에서만 지연 생성된다 — 유효한 사진이 확보되기 전에는 세션을
  /// 만들지 않는다. 한 번 만들어지면 재시도·다른 사진 재선택에도 그대로
  /// 재사용해 세션이 여러 개 남지 않게 한다. 복원 모드에서는 기존 세션으로
  /// 미리 채워져 있어 새 세션을 만들지 않는다.
  int? _sessionId;
  DrawingSessionResolution? _sessionResolution;
  String? _uploadIdempotencyKey;
  String? _completionIdempotencyKey;
  String? _advanceIdempotencyKey;
  String? _advanceInputMethod;
  late final DateTime _flowStartedAt = widget.now?.call() ?? DateTime.now();

  /// 이 화면이 새 세션을 만들었는지(복원 모드가 아니면 참). 복원한 세션은
  /// 취소해도 삭제하지 않는다.
  bool get _ownsSession => widget.existingDrawingSessionId == null;

  @override
  void initState() {
    super.initState();
    final existingSessionId = widget.existingDrawingSessionId;
    if (existingSessionId != null) {
      _step = _Step.photoSource;
      _sessionId = existingSessionId;
      _sessionResolution = DrawingSessionResolution(
        sessionId: existingSessionId,
        currentStage: 'DRAWING',
        activityContext:
            widget.restoredActivityContext ??
            const DrawingActivityContextDto.general(),
        inputMethod: 'UPLOAD',
      );
      final now = widget.now?.call() ?? DateTime.now();
      _uploadIdempotencyKey =
          'htp-upload-$existingSessionId-${now.microsecondsSinceEpoch}';
      _completionIdempotencyKey =
          'htp-complete-$existingSessionId-${now.microsecondsSinceEpoch}';
    } else {
      _step = _Step.methodChoice;
    }
  }

  Future<void> _handleCanvasChoice() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _canvasError = false;
    });
    try {
      final resolution = await _createHtpResolution('CANVAS');
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
      _photoPermissionIssue = null;
    });
  }

  void _backToMethodChoice() {
    if (_busy) return;
    setState(() {
      _step = _Step.methodChoice;
      _photoPickError = null;
      _photoPermissionIssue = null;
    });
  }

  Future<void> _pickFrom(
    Future<PickedPhoto?> Function() pick, {
    required PhotoPermissionKind permissionKind,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _photoPickError = null;
      _photoPermissionIssue = null;
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
    } on PlatformException catch (error) {
      if (!mounted) return;
      final permissionIssue = await _permissionIssue(error, permissionKind);
      if (!mounted) return;
      setState(() {
        if (permissionIssue != null) {
          _photoPermissionIssue = permissionIssue;
        } else {
          _photoPickError = presentationForValidationError(
            PhotoValidationErrorType.undecodable,
          );
        }
        _busy = false;
      });
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

  Future<_PhotoPermissionIssue?> _permissionIssue(
    PlatformException error,
    PhotoPermissionKind kind,
  ) async {
    const permissionErrorCodes = {
      'camera_access_denied',
      'camera_access_restricted',
      'photo_access_denied',
      'photo_access_restricted',
    };
    if (!permissionErrorCodes.contains(error.code)) return null;
    final status = await widget.photoPermissionService.status(kind);
    return _PhotoPermissionIssue(kind: kind, status: status);
  }

  Future<void> _openPermissionSettings(PhotoPermissionKind kind) async {
    final opened = await widget.photoPermissionService.openSettings();
    if (!mounted || opened) return;
    final target = kind == PhotoPermissionKind.camera ? '카메라' : '사진';
    showAppMessage(
      context,
      message: '설정 화면을 열지 못했어요. 기기 설정에서 직접 $target 권한을 허용해 주세요.',
      type: AppMessageType.error,
    );
  }

  void _reselectPhoto() {
    if (_busy) return;
    setState(() {
      _validated = null;
      _uploadError = null;
      _uploadProgressPercent = null;
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
      _uploadProgressPercent = 0;
    });
    try {
      var sessionId = _sessionId;
      if (sessionId == null) {
        final now = widget.now?.call() ?? DateTime.now();
        final resolution = await _createHtpResolution('UPLOAD');
        sessionId = resolution.sessionId;
        if (!mounted) return;
        setState(() {
          _sessionId = sessionId;
          _sessionResolution = resolution;
          _uploadIdempotencyKey =
              'htp-upload-$sessionId-${now.microsecondsSinceEpoch}';
          _completionIdempotencyKey =
              'htp-complete-$sessionId-${now.microsecondsSinceEpoch}';
        });
      }

      final image = BinaryUploadDto(
        bytes: validated.photo.bytes,
        fileName: validated.photo.fileName,
        mimeType: validated.mimeType,
      );
      final metadata = UploadDrawingImageMetadataDto(
        clientCapturedAt: (widget.now?.call() ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        rotationDegrees: 0,
        cropApplied: false,
      );
      final repository = widget.repository;
      final uploaded = repository is DrawingUploadProgressRepository
          ? await repository.uploadDrawing(
              sessionId,
              image,
              metadata: metadata,
              idempotencyKey: _uploadIdempotencyKey!,
              onProgress: _handleUploadProgress,
            )
          : await repository.uploadDrawing(
              sessionId,
              image,
              metadata: metadata,
              idempotencyKey: _uploadIdempotencyKey!,
            );

      if (widget.repository is! UploadedDrawingCompletionRepository) {
        throw UnsupportedError('Uploaded drawing completion is unavailable.');
      }
      final completed =
          await (widget.repository as UploadedDrawingCompletionRepository)
              .completeUploadedDrawingStage(
                sessionId,
                metadata: DrawingCompleteMetadataDto(
                  sourceAssetId: uploaded.drawingAssetId,
                  drawingDurationMs: (widget.now?.call() ?? DateTime.now())
                      .difference(_flowStartedAt)
                      .inMilliseconds
                      .clamp(1, 1 << 31),
                  clientCompletedAt: (widget.now?.call() ?? DateTime.now())
                      .toUtc()
                      .toIso8601String(),
                ),
                idempotencyKey: _completionIdempotencyKey!,
              );
      if (!mounted) return;
      final initial = _sessionResolution!;
      Navigator.of(context).pop(
        DrawingSessionResolution(
          sessionId: completed.drawingSessionId,
          currentStage: completed.currentStage,
          activityContext: initial.activityContext,
          inputMethod: 'UPLOAD',
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadError = DrawingUploadErrorPresentation.of(error);
        _uploadProgressPercent = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleUploadProgress(int sent, int total) {
    if (!mounted || !_busy || total <= 0) return;
    final percent = ((sent / total) * 100).floor().clamp(0, 100);
    if (_uploadProgressPercent == percent) return;
    setState(() => _uploadProgressPercent = percent);
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final sessionId = _sessionId;
    if (_ownsSession &&
        sessionId != null &&
        widget.repository is DrawingSessionDiscarder) {
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

  Future<DrawingSessionResolution> _createHtpResolution(
    String inputMethod,
  ) async {
    final assessmentId = widget.htpAssessmentId;
    if (assessmentId == null) {
      return _controller.createHtpAssessment(
        childId: widget.childId,
        replaceActive: widget.replaceActive,
        inputMethod: inputMethod,
      );
    }
    if (widget.repository is! HtpDrawingRepository) {
      throw UnsupportedError('HTP activity is unavailable.');
    }
    // 같은 방식 재시도는 같은 Key를, 다른 방식으로 바꾸면 새 Key를 쓴다.
    if (_advanceInputMethod != inputMethod) {
      _advanceInputMethod = inputMethod;
      _advanceIdempotencyKey = null;
    }
    final idempotencyKey = _advanceIdempotencyKey ??=
        widget.idempotencyKeyProvider?.call() ?? _createIdempotencyKey();
    final assessment = await (widget.repository as HtpDrawingRepository)
        .moveToNextHtpStep(
          assessmentId,
          inputMethod: inputMethod,
          idempotencyKey: idempotencyKey,
        );
    final step = assessment.currentStep;
    return DrawingSessionResolution(
      sessionId: step.drawingSessionId,
      currentStage: step.currentStage,
      inputMethod: inputMethod,
      activityContext: DrawingActivityContextDto(
        activityKind: 'HTP',
        htpAssessmentId: assessment.htpAssessmentId,
        htpStatus: assessment.status,
        stepOrder: step.stepOrder,
        drawingSubject: step.drawingSubject,
      ),
    );
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
                  description: widget.htpPhotoUploadEnabled
                      ? '그려둔 그림을 사진으로 담아요'
                      : '곧 만나요',
                  color: AppColors.tangerine,
                  onTap: !widget.htpPhotoUploadEnabled || _busy
                      ? null
                      : _choosePhotoMethod,
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
      if (_photoPermissionIssue case final issue?) ...[
        _PermissionErrorBanner(
          key: const ValueKey('input-method-permission-error'),
          issue: issue,
          onOpenSettings:
              issue.status == PhotoPermissionStatus.permanentlyDenied
              ? () => _openPermissionSettings(issue.kind)
              : null,
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
                      : () => _pickFrom(
                          widget.photoPickerAdapter.pickFromCamera,
                          permissionKind: PhotoPermissionKind.camera,
                        ),
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
                          permissionKind: PhotoPermissionKind.photos,
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
          // 복원 모드는 이미 UPLOAD로 확정된 세션이라 방식 선택으로 되돌아갈
          // 수 없다 — "뒤로"를 누르면 새 HTP 활동을 또 만들게 된다.
          if (_ownsSession) ...[
            Expanded(
              child: AppButton(
                key: const ValueKey('input-method-back'),
                label: '뒤로',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _backToMethodChoice,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
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
        if (_busy)
          if (_uploadProgressPercent case final progress?) ...[
            Builder(
              builder: (context) {
                final statusMessage = progress >= 100
                    ? '업로드 100% · 사진을 확인하고 있어요'
                    : '사진을 올리고 있어요 $progress%';

                return Semantics(
                  label: '사진 업로드 $progress퍼센트',
                  value: '$progress%',
                  child: ExcludeSemantics(
                    child: Column(
                      key: const ValueKey('input-method-upload-progress'),
                      children: [
                        LinearProgressIndicator(value: progress / 100),
                        const SizedBox(height: AppSpacing.xs),
                        Text(statusMessage),
                      ],
                    ),
                  ),
                );
              },
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

final class _PhotoPermissionIssue {
  const _PhotoPermissionIssue({required this.kind, required this.status});

  final PhotoPermissionKind kind;
  final PhotoPermissionStatus status;

  String get message {
    final target = kind == PhotoPermissionKind.camera ? '카메라' : '사진';
    return switch (status) {
      PhotoPermissionStatus.denied =>
        '$target 권한이 필요해요. 다시 선택해 권한을 허용해 주세요.',
      PhotoPermissionStatus.permanentlyDenied =>
        '기기 설정에서 $target 권한을 허용해 주세요.',
      PhotoPermissionStatus.restricted =>
        '$target 사용이 기기 설정 또는 보호자 정책으로 제한되어 있어요.',
    };
  }
}

class _PermissionErrorBanner extends StatelessWidget {
  const _PermissionErrorBanner({
    required this.issue,
    required this.onOpenSettings,
    super.key,
  });

  final _PhotoPermissionIssue issue;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: issue.message,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.settings_rounded,
            color: AppColors.error,
            size: AppIconSize.lg,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              issue.message,
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
          ),
          if (onOpenSettings case final openSettings?)
            TextButton(
              key: const ValueKey('input-method-open-settings'),
              onPressed: openSettings,
              child: const Text('설정 열기'),
            ),
        ],
      ),
    ),
  );
}
