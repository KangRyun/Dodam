import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/drawing_upload_error.dart';
import '../../application/photo_upload_validation.dart';
import '../../data/image_picker_photo_adapter.dart';
import '../../domain/pending_htp_photo.dart';
import '../../domain/photo_picker_adapter.dart';
import 'guided_camera_screen.dart';

/// 한 HTP 주제에 쓸 사진 한 장을 얻는 전략(촬영 또는 앨범).
///
/// 기본 구현은 [GuidedCameraScreen]을 열고 "앨범" 선택 시 갤러리로 넘긴다.
/// 테스트는 카메라 없이 가짜 사진을 주입한다.
typedef HtpSubjectPhotoAcquirer =
    Future<PickedPhoto?> Function(BuildContext context, String subject);

/// 선촬영 화면을 띄워 집·나무·사람 사진을 [store]에 보관한다(S15P11B209-872).
///
/// 세 장을 모두 촬영하면 `true`, 취소·중단이면 보관분을 정리하고 `false`를
/// 돌려준다. HTP를 사진으로 시작하는 여러 진입(아동 홈·보호자 활동 선택)이
/// 같은 선촬영 흐름을 쓰도록 한 곳에 둔다.
Future<bool> runHtpPhotoPrecapture({
  required BuildContext context,
  required int childId,
  required PendingHtpPhotoStore store,
}) async {
  // 이전에 남은 보관 사진이 있으면 지우고 새로 시작한다.
  await store.clear(childId);
  if (!context.mounted) return false;
  final captured = await Navigator.of(context).push<List<PendingHtpPhoto>?>(
    MaterialPageRoute(
      builder: (routeContext) => HtpPhotoPrecaptureScreen(
        childId: childId,
        store: store,
        onCompleted: (photos) => Navigator.of(routeContext).pop(photos),
        onCancelled: () => Navigator.of(routeContext).pop(null),
      ),
    ),
  );
  if (captured == null || captured.isEmpty) {
    await store.clear(childId);
    return false;
  }
  return true;
}

/// HTP 사진 활동의 선촬영 화면(S15P11B209-872).
///
/// 집→나무→사람 순서로 각 주제 사진을 촬영·확인(재촬영 가능)한 뒤 기기에
/// 보관한다. 세 장이 모두 보관되면 [onCompleted]로 넘겨, 상위에서 주제별
/// 업로드·대화 처리를 시작하게 한다. 업로드·세션 생성은 여기서 하지 않는다.
class HtpPhotoPrecaptureScreen extends StatefulWidget {
  HtpPhotoPrecaptureScreen({
    required this.childId,
    required this.store,
    required this.onCompleted,
    this.onCancelled,
    HtpSubjectPhotoAcquirer? acquirePhoto,
    PhotoPickerAdapter? photoPickerAdapter,
    this.dimensionReader = readPhotoDimensions,
    super.key,
  }) : acquirePhoto =
           acquirePhoto ??
           _cameraAcquirer(photoPickerAdapter ?? ImagePickerPhotoAdapter());

  final int childId;
  final PendingHtpPhotoStore store;

  /// 세 주제 사진이 모두 보관된 뒤 호출된다(보관 순서 목록 전달).
  final ValueChanged<List<PendingHtpPhoto>> onCompleted;

  /// 첫 주제에서 사용자가 그만두면 호출된다.
  final VoidCallback? onCancelled;

  final HtpSubjectPhotoAcquirer acquirePhoto;
  final PhotoDimensionReader dimensionReader;

  static HtpSubjectPhotoAcquirer _cameraAcquirer(PhotoPickerAdapter picker) =>
      (context, subject) async {
        final result = await Navigator.of(context).push<Object?>(
          MaterialPageRoute<Object?>(
            builder: (_) => GuidedCameraScreen(drawingSubject: subject),
          ),
        );
        if (result == 'gallery') return picker.pickFromGallery();
        if (result is PickedPhoto) return result;
        return null;
      };

  @override
  State<HtpPhotoPrecaptureScreen> createState() =>
      _HtpPhotoPrecaptureScreenState();
}

enum _PrecapturePhase { idle, acquiring, previewing, saving }

const List<({String code, String label})> _htpSubjects = [
  (code: 'HOUSE', label: '집'),
  (code: 'TREE', label: '나무'),
  (code: 'PERSON', label: '사람'),
];

class _HtpPhotoPrecaptureScreenState extends State<HtpPhotoPrecaptureScreen> {
  int _index = 0;
  _PrecapturePhase _phase = _PrecapturePhase.idle;
  ValidatedPhoto? _validated;
  DrawingUploadErrorPresentation? _pickError;
  bool _finished = false;

  ({String code, String label}) get _subject => _htpSubjects[_index];
  bool get _busy => _phase != _PrecapturePhase.idle &&
      _phase != _PrecapturePhase.previewing;

  Future<void> _acquireForCurrent() async {
    if (!mounted || _busy || _finished) return;
    setState(() {
      _phase = _PrecapturePhase.acquiring;
      _pickError = null;
    });
    final subject = _subject.code;
    PickedPhoto? picked;
    try {
      picked = await widget.acquirePhoto(context, subject);
    } on Object {
      picked = null;
    }
    if (!mounted) return;
    if (picked == null) {
      // 취소·실패 — 이 주제 시작 화면으로 돌아가 다시 시도하거나 그만둘 수 있게 한다.
      setState(() => _phase = _PrecapturePhase.idle);
      return;
    }
    final result = await validatePickedPhoto(
      picked,
      dimensionReader: widget.dimensionReader,
    );
    if (!mounted) return;
    switch (result) {
      case PhotoValidationOk(:final validated):
        setState(() {
          _validated = validated;
          _phase = _PrecapturePhase.previewing;
        });
      case PhotoValidationFailed(:final type):
        setState(() {
          _pickError = presentationForValidationError(type);
          _phase = _PrecapturePhase.idle;
        });
    }
  }

  Future<void> _useCurrentPhoto() async {
    final validated = _validated;
    if (validated == null || _phase != _PrecapturePhase.previewing) return;
    setState(() => _phase = _PrecapturePhase.saving);
    try {
      await widget.store.save(
        widget.childId,
        PendingHtpPhoto(
          subject: _subject.code,
          bytes: validated.photo.bytes,
          mimeType: validated.mimeType,
          width: validated.width,
          height: validated.height,
          fileName: validated.photo.fileName,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _phase = _PrecapturePhase.previewing);
      showAppMessage(
        context,
        message: '사진을 저장하지 못했어요. 다시 시도해 주세요.',
        type: AppMessageType.error,
      );
      return;
    }
    if (!mounted) return;
    if (_index >= _htpSubjects.length - 1) {
      _finished = true;
      final stored = await widget.store.load(widget.childId);
      if (!mounted) return;
      widget.onCompleted(stored);
      return;
    }
    setState(() {
      _index += 1;
      _validated = null;
      _phase = _PrecapturePhase.idle;
    });
    unawaited(_acquireForCurrent());
  }

  void _retakeCurrent() {
    if (_phase != _PrecapturePhase.previewing) return;
    setState(() {
      _validated = null;
      _phase = _PrecapturePhase.idle;
    });
    unawaited(_acquireForCurrent());
  }

  void _cancel() {
    if (_finished) return;
    widget.onCancelled?.call();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.childCanvas,
    appBar: AppTopBar(
      title: '사진으로 시작하기',
      onBack: _busy ? null : _cancel,
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
            child: SingleChildScrollView(
              child: _phase == _PrecapturePhase.previewing && _validated != null
                  ? _buildPreview(context)
                  : _buildCapturePrompt(context),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildProgress() => Row(
    key: const ValueKey('htp-precapture-progress'),
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < _htpSubjects.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpacing.sm),
        _StepDot(
          label: _htpSubjects[i].label,
          done: i < _index,
          current: i == _index,
        ),
      ],
    ],
  );

  Widget _buildCapturePrompt(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buildProgress(),
      const SizedBox(height: AppSpacing.xl),
      Text(
        '${_subject.label} 그림을 찍어요',
        textAlign: TextAlign.center,
        style: AppTypography.titleLg,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        '집·나무·사람 그림을 차례로 찍어 둘게요 (${_index + 1}/${_htpSubjects.length})',
        textAlign: TextAlign.center,
        style: AppTypography.body.copyWith(color: AppColors.inkMuted),
      ),
      const SizedBox(height: AppSpacing.lg),
      if (_pickError case final error?) ...[
        _ErrorBanner(icon: error.icon, message: error.message),
        const SizedBox(height: AppSpacing.md),
      ],
      AppButton(
        key: const ValueKey('htp-precapture-open-camera'),
        label: '${_subject.label} 사진 찍기',
        variant: AppButtonVariant.child,
        leading: const Icon(Icons.camera_alt_rounded),
        isLoading: _phase == _PrecapturePhase.acquiring,
        onPressed: _busy ? null : () => unawaited(_acquireForCurrent()),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppButton(
        key: const ValueKey('htp-precapture-cancel'),
        label: '그만두기',
        variant: AppButtonVariant.secondary,
        onPressed: _busy ? null : _cancel,
      ),
    ],
  );

  Widget _buildPreview(BuildContext context) {
    final validated = _validated!;
    final saving = _phase == _PrecapturePhase.saving;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProgress(),
        const SizedBox(height: AppSpacing.md),
        Text(
          '${_subject.label} 사진, 이대로 쓸까요?',
          textAlign: TextAlign.center,
          style: AppTypography.titleLg,
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          label: '${_subject.label} 사진 미리보기',
          image: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.memory(validated.photo.bytes, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          key: const ValueKey('htp-precapture-use'),
          label: _index >= _htpSubjects.length - 1
              ? '이 사진 쓰고 시작하기'
              : '이 사진 쓰고 다음',
          variant: AppButtonVariant.child,
          isLoading: saving,
          onPressed: saving ? null : () => unawaited(_useCurrentPhoto()),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const ValueKey('htp-precapture-retake'),
          label: '다시 찍기',
          variant: AppButtonVariant.secondary,
          onPressed: saving ? null : _retakeCurrent,
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.done,
    required this.current,
  });

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = done || current ? AppColors.tangerine : AppColors.outline;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done
              ? Icons.check_circle_rounded
              : current
              ? Icons.camera_alt_rounded
              : Icons.circle_outlined,
          color: color,
          size: 24,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: AppTypography.bodySm.copyWith(
            color: current ? AppColors.ink : AppColors.inkMuted,
            fontWeight: current ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.icon, required this.message});

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
