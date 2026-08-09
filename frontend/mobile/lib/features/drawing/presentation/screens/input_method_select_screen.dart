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
import 'guided_camera_screen.dart';

enum _Step { methodChoice, photoSource, cameraGuidance, preview }

enum _InputPhase {
  idle,
  picking,
  creatingSession,
  uploading,
  completing,
  leaving,
  disposed,
}

final class _DrawingUploadSnapshot {
  const _DrawingUploadSnapshot({
    required this.source,
    required this.sessionId,
    required this.routeIdentity,
    required this.image,
    required this.uploadMetadata,
    required this.drawingDurationMs,
    required this.clientCompletedAt,
    required this.uploadIdempotencyKey,
    required this.completionIdempotencyKey,
  });

  final ValidatedPhoto source;
  final int sessionId;
  final String routeIdentity;
  final BinaryUploadDto image;
  final UploadDrawingImageMetadataDto uploadMetadata;
  final int drawingDurationMs;
  final String clientCompletedAt;
  final String uploadIdempotencyKey;
  final String completionIdempotencyKey;
}

final class _DrawingUploadAttempt {
  const _DrawingUploadAttempt({
    required this.generation,
    required this.snapshot,
    required this.cancellation,
  });

  final int generation;
  final _DrawingUploadSnapshot snapshot;
  final DrawingUploadCancellation cancellation;
}

/// 촬영 도움말 항목(아이콘, 문구). 아이콘만으로 뜻을 전달하지 않도록 문구를
/// 항상 함께 보여준다(S15P11B209-471).
const List<(IconData, String)> _cameraGuidanceTips = [
  (Icons.crop_free_rounded, '그림 전체가 화면에 들어오게 해줘.'),
  (Icons.wb_sunny_rounded, '밝은 곳에서 그림자가 지지 않게 찍어줘.'),
  (Icons.grid_on_rounded, '카메라를 그림과 나란히 맞춰줘.'),
  (Icons.pan_tool_rounded, '흔들리지 않게 잠깐 멈춰 찍어줘.'),
];

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
/// 첫 방식 선택에서 "사진으로 시작하기"를 고르면, 단일 촬영 대신 HTP 선촬영
/// 배치 흐름(집·나무·사람 미리 촬영)을 시작하라는 신호로 pop된다
/// (S15P11B209-872).
class HtpPhotoBatchRequested {
  const HtpPhotoBatchRequested();
}

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
    this.htpPhotoBatchEnabled = false,
    this.idempotencyKeyProvider,
    this.pendingPhoto,
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
       assert(
         pendingPhoto == null || existingDrawingSessionId != null,
         '미리 촬영한 사진 자동 업로드는 기존 UPLOAD 세션에만 올린다.',
       ),
       useInAppCamera = photoPickerAdapter == null,
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

  /// 참이면 "사진으로 시작하기"가 단일 촬영이 아니라 HTP 선촬영 배치를
  /// 요청하며 [HtpPhotoBatchRequested]로 pop한다(S15P11B209-872). 첫 주제
  /// 방식 선택에서만 켠다.
  final bool htpPhotoBatchEnabled;

  /// 선촬영해 보관해 둔 사진(S15P11B209-872). 주어지면 카메라·방식 선택 없이
  /// [existingDrawingSessionId] 세션에 이 사진을 바로 업로드한다.
  final ValidatedPhoto? pendingPhoto;

  final String Function()? idempotencyKeyProvider;
  final bool useInAppCamera;
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

  _InputPhase _phase = _InputPhase.idle;
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
  _DrawingUploadSnapshot? _pendingUploadSnapshot;
  _DrawingUploadAttempt? _activeUploadAttempt;
  int _uploadGeneration = 0;
  int _pickerGeneration = 0;
  bool _isLeaving = false;
  bool _preUploadCancelRequested = false;
  Future<DrawingSessionResolution>? _sessionCreationFuture;
  String? _sessionCreationIdentity;
  Future<DrawingStageCompleteResponseDto>? _completionSettlement;
  int _permissionSettingsOperation = 0;
  String? _advanceIdempotencyKey;
  String? _advanceRequestIdentity;
  late final DateTime _flowStartedAt = widget.now?.call() ?? DateTime.now();

  /// 이 화면이 새 세션을 만들었는지(복원 모드가 아니면 참). 복원한 세션은
  /// 취소해도 삭제하지 않는다.
  bool get _ownsSession => widget.existingDrawingSessionId == null;

  bool get _busy => _phase != _InputPhase.idle;

  bool get _canStartAction =>
      mounted && !_isLeaving && _phase == _InputPhase.idle;

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
      final pending = widget.pendingPhoto;
      if (pending != null) {
        // 선촬영한 사진은 확인·촬영 없이 미리보기 상태에서 바로 업로드한다.
        _validated = pending;
        _step = _Step.preview;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_confirmAndUpload());
        });
      }
    } else {
      _step = _Step.methodChoice;
    }
  }

  @override
  void didUpdateWidget(covariant InputMethodSelectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldContext = oldWidget.restoredActivityContext;
    final newContext = widget.restoredActivityContext;
    final identityChanged =
        oldWidget.childId != widget.childId ||
        oldWidget.drawingTypeId != widget.drawingTypeId ||
        oldWidget.htpAssessmentId != widget.htpAssessmentId ||
        oldWidget.existingDrawingSessionId != widget.existingDrawingSessionId ||
        oldContext?.htpAssessmentId != newContext?.htpAssessmentId ||
        oldContext?.stepOrder != newContext?.stepOrder ||
        oldContext?.drawingSubject != newContext?.drawingSubject;
    if (identityChanged) {
      final pendingCompletion = _completionSettlement;
      final newRouteIdentity = _routeInputIdentity;
      _invalidateUpload(clearSnapshot: true);
      _invalidatePicker();
      _sessionCreationFuture = null;
      _sessionCreationIdentity = null;
      _advanceIdempotencyKey = null;
      _advanceRequestIdentity = null;
      _phase = pendingCompletion == null
          ? _InputPhase.idle
          : _InputPhase.completing;
      _canvasError = false;
      _photoPickError = null;
      _photoPermissionIssue = null;
      _validated = null;
      _uploadError = null;
      _uploadProgressPercent = null;
      final existingSessionId = widget.existingDrawingSessionId;
      if (existingSessionId == null) {
        _step = _Step.methodChoice;
        _sessionId = null;
        _sessionResolution = null;
      } else {
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
      }
      if (pendingCompletion != null) {
        unawaited(
          _releaseCompletionAfterIdentityChange(
            pendingCompletion,
            newRouteIdentity,
          ),
        );
      }
    }
  }

  Future<void> _releaseCompletionAfterIdentityChange(
    Future<DrawingStageCompleteResponseDto> completion,
    String routeIdentity,
  ) async {
    try {
      await completion;
    } on Object {
      // 이전 identity의 결과는 성공·실패와 무관하게 현재 화면에 표시하지 않는다.
    }
    if (!mounted ||
        _isLeaving ||
        _phase != _InputPhase.completing ||
        routeIdentity != _routeInputIdentity) {
      return;
    }
    setState(() => _phase = _InputPhase.idle);
  }

  @override
  void dispose() {
    _isLeaving = true;
    _phase = _InputPhase.disposed;
    _invalidatePicker();
    _sessionCreationIdentity = null;
    _invalidateUpload(clearSnapshot: false);
    super.dispose();
  }

  Future<void> _handleCanvasChoice() async {
    if (!_canStartAction) return;
    final routeIdentity = _routeInputIdentity;
    setState(() {
      _phase = _InputPhase.creatingSession;
      _canvasError = false;
    });
    try {
      final resolution = await _createHtpResolution('CANVAS');
      if (!mounted || !_isCanvasChoiceCurrent(routeIdentity)) return;
      Navigator.of(context).pop(resolution);
    } on Object {
      if (!_isCanvasChoiceCurrent(routeIdentity)) return;
      setState(() => _canvasError = true);
    } finally {
      if (_isCanvasChoiceCurrent(routeIdentity)) {
        setState(() => _phase = _InputPhase.idle);
      }
    }
  }

  bool _isCanvasChoiceCurrent(String routeIdentity) =>
      mounted &&
      !_isLeaving &&
      _phase == _InputPhase.creatingSession &&
      routeIdentity == _routeInputIdentity;

  void _choosePhotoMethod() {
    if (!_canStartAction) return;
    // 선촬영 배치가 켜져 있으면 단일 촬영 대신 상위에 배치 시작을 신호한다.
    if (widget.htpPhotoBatchEnabled) {
      _isLeaving = true;
      Navigator.of(context).pop(const HtpPhotoBatchRequested());
      return;
    }
    _invalidateUpload(clearSnapshot: true);
    setState(() {
      _step = _Step.photoSource;
      _photoPickError = null;
      _photoPermissionIssue = null;
    });
  }

  Future<void> _openGuidedCamera() async {
    if (!_canStartAction) return;
    if (!widget.useInAppCamera) {
      await _pickFrom(
        widget.photoPickerAdapter.pickFromCamera,
        permissionKind: PhotoPermissionKind.camera,
      );
      return;
    }
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => GuidedCameraScreen(
          drawingSubject:
              widget.restoredActivityContext?.drawingSubject ?? 'HOUSE',
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'gallery') {
      await _pickFrom(
        widget.photoPickerAdapter.pickFromGallery,
        permissionKind: PhotoPermissionKind.photos,
      );
      return;
    }
    if (result is PickedPhoto) {
      await _pickFrom(
        () async => result,
        permissionKind: PhotoPermissionKind.camera,
      );
    }
  }

  void _backToMethodChoice() {
    if (!_canStartAction) return;
    _invalidateUpload(clearSnapshot: true);
    setState(() {
      _step = _Step.methodChoice;
      _photoPickError = null;
      _photoPermissionIssue = null;
    });
  }

  /// 카메라를 고르면 시스템 카메라를 바로 열지 않고 촬영 도움말을 먼저 보여준다
  /// (S15P11B209-471). 이 단계는 설명만 하므로 picker·권한·서버 상태를 만들지
  /// 않는다 — 실제 촬영은 [_captureFromCamera]에서만 시작한다.
  void _showCameraGuidance() {
    if (!_canStartAction) return;
    _invalidateUpload(clearSnapshot: true);
    setState(() {
      _step = _Step.cameraGuidance;
      _photoPickError = null;
      _photoPermissionIssue = null;
    });
  }

  /// 촬영 도움말에서 사진 소스 선택으로 되돌아간다.
  ///
  /// 화면 자체를 pop하지 않는다 — 아이는 앨범으로 바꾸거나 다시 촬영을 고를 수
  /// 있어야 한다. 세션을 만든 적이 없으므로 정리할 서버 상태도 없다.
  void _backToPhotoSource() {
    if (!_canStartAction) return;
    setState(() {
      _step = _Step.photoSource;
      _photoPickError = null;
      _photoPermissionIssue = null;
    });
  }

  /// 도움말의 `촬영하기`. 실제 기기에서는 가이드가 포함된 인앱 카메라를 연다.
  Future<void> _captureFromCamera() => _openGuidedCamera();

  Future<void> _pickFrom(
    Future<PickedPhoto?> Function() pick, {
    required PhotoPermissionKind permissionKind,
  }) async {
    if (!_canStartAction) return;
    _invalidateUpload(clearSnapshot: true);
    final pickerGeneration = ++_pickerGeneration;
    final pickerIdentity = _routeInputIdentity;
    setState(() {
      _phase = _InputPhase.picking;
      _photoPickError = null;
      _photoPermissionIssue = null;
    });
    try {
      final photo = await pick();
      if (!_isPickerCurrent(pickerGeneration, pickerIdentity)) return;
      if (photo == null) {
        // 시스템 picker를 사용자가 취소한 것 — 오류가 아니라 이 화면에
        // 그대로 남는다.
        setState(() => _phase = _InputPhase.idle);
        return;
      }
      final result = await validatePickedPhoto(
        photo,
        dimensionReader: widget.dimensionReader,
      );
      if (!_isPickerCurrent(pickerGeneration, pickerIdentity)) return;
      switch (result) {
        case PhotoValidationOk(:final validated):
          setState(() {
            _validated = validated;
            _uploadError = null;
            _step = _Step.preview;
            _phase = _InputPhase.idle;
          });
        case PhotoValidationFailed(:final type):
          setState(() {
            _photoPickError = presentationForValidationError(type);
            _phase = _InputPhase.idle;
          });
      }
    } on PlatformException catch (error) {
      if (!_isPickerCurrent(pickerGeneration, pickerIdentity)) return;
      final permissionIssue = await _permissionIssue(error, permissionKind);
      if (!_isPickerCurrent(pickerGeneration, pickerIdentity)) return;
      setState(() {
        if (permissionIssue != null) {
          _photoPermissionIssue = permissionIssue;
        } else {
          _photoPickError = presentationForValidationError(
            PhotoValidationErrorType.undecodable,
          );
        }
        _phase = _InputPhase.idle;
      });
    } on Object {
      if (!_isPickerCurrent(pickerGeneration, pickerIdentity)) return;
      setState(() {
        _photoPickError = presentationForValidationError(
          PhotoValidationErrorType.undecodable,
        );
        _phase = _InputPhase.idle;
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
    if (!_canStartAction) return;
    final operation = ++_permissionSettingsOperation;
    final pickerGeneration = _pickerGeneration;
    final routeIdentity = _routeInputIdentity;
    final phase = _phase;
    final wasLeaving = _isLeaving;
    final permissionIssue = _photoPermissionIssue;
    var opened = false;
    try {
      opened = await widget.photoPermissionService.openSettings();
    } on Object {
      // 현재 operation이면 아래에서 같은 복구 안내를 표시하고, stale이면 버린다.
    }
    if (!mounted ||
        !_isPermissionSettingsCurrent(
          operation: operation,
          pickerGeneration: pickerGeneration,
          routeIdentity: routeIdentity,
          phase: phase,
          wasLeaving: wasLeaving,
          permissionIssue: permissionIssue,
        ) ||
        opened) {
      return;
    }
    final target = kind == PhotoPermissionKind.camera ? '카메라' : '사진';
    showAppMessage(
      context,
      message: '설정 화면을 열지 못했어요. 기기 설정에서 직접 $target 권한을 허용해 주세요.',
      type: AppMessageType.error,
    );
  }

  bool _isPermissionSettingsCurrent({
    required int operation,
    required int pickerGeneration,
    required String routeIdentity,
    required _InputPhase phase,
    required bool wasLeaving,
    required _PhotoPermissionIssue? permissionIssue,
  }) =>
      mounted &&
      !wasLeaving &&
      !_isLeaving &&
      phase == _InputPhase.idle &&
      _phase == phase &&
      // 권한 안내는 사진 소스 선택과 촬영 도움말 두 단계에서 나올 수 있다.
      (_step == _Step.photoSource || _step == _Step.cameraGuidance) &&
      operation == _permissionSettingsOperation &&
      pickerGeneration == _pickerGeneration &&
      routeIdentity == _routeInputIdentity &&
      identical(permissionIssue, _photoPermissionIssue);

  void _reselectPhoto() {
    if (!_canStartAction) return;
    _invalidatePicker();
    _invalidateUpload(clearSnapshot: true);
    setState(() {
      _validated = null;
      _uploadError = null;
      _uploadProgressPercent = null;
      _step = _Step.photoSource;
    });
  }

  String get _routeInputIdentity {
    final activityContext = widget.restoredActivityContext;
    return '${widget.childId}|${widget.drawingTypeId}|'
        '${widget.htpAssessmentId}|${widget.existingDrawingSessionId}|'
        '${activityContext?.htpAssessmentId}|${activityContext?.stepOrder}|'
        '${activityContext?.drawingSubject}|UPLOAD';
  }

  void _invalidatePicker() {
    _pickerGeneration += 1;
  }

  bool _isPickerCurrent(int generation, String routeIdentity) =>
      mounted &&
      !_isLeaving &&
      _phase == _InputPhase.picking &&
      generation == _pickerGeneration &&
      routeIdentity == _routeInputIdentity;

  Future<DrawingSessionResolution> _resolveUploadSession() {
    final resolution = _sessionResolution;
    if (_sessionId != null && resolution != null) {
      return Future.value(resolution);
    }

    final routeIdentity = _routeInputIdentity;
    final pending = _sessionCreationFuture;
    if (pending != null && _sessionCreationIdentity == routeIdentity) {
      return pending;
    }

    late final Future<DrawingSessionResolution> future;
    future = () async {
      try {
        final created = await _createHtpResolution('UPLOAD');
        if (_sessionCreationIdentity == routeIdentity &&
            _routeInputIdentity == routeIdentity) {
          _sessionId = created.sessionId;
          _sessionResolution = created;
        }
        return created;
      } finally {
        if (identical(_sessionCreationFuture, future)) {
          _sessionCreationFuture = null;
          _sessionCreationIdentity = null;
        }
      }
    }();
    _sessionCreationIdentity = routeIdentity;
    _sessionCreationFuture = future;
    return future;
  }

  Future<void> _confirmAndUpload() async {
    if (!_canStartAction) return;
    if (_uploadError case final error? when !error.canRetry) return;
    final validated = _validated;
    if (validated == null) return;
    final generation = ++_uploadGeneration;
    DrawingUploadEndpoint endpoint = DrawingUploadEndpoint.upload;
    _DrawingUploadAttempt? attempt;
    Future<DrawingStageCompleteResponseDto>? completionFuture;
    setState(() {
      _phase = _InputPhase.creatingSession;
      _preUploadCancelRequested = false;
      _uploadError = null;
      _uploadProgressPercent = null;
    });
    try {
      final resolution = await _resolveUploadSession();
      if (!_isOperationCurrent(generation) || _preUploadCancelRequested) return;
      final sessionId = resolution.sessionId;

      var snapshot = _pendingUploadSnapshot;
      final routeIdentity = _uploadRouteIdentity(sessionId);
      if (snapshot == null ||
          !identical(snapshot.source, validated) ||
          snapshot.sessionId != sessionId ||
          snapshot.routeIdentity != routeIdentity) {
        final now = widget.now?.call() ?? DateTime.now();
        snapshot = _DrawingUploadSnapshot(
          source: validated,
          sessionId: sessionId,
          routeIdentity: routeIdentity,
          image: BinaryUploadDto(
            bytes: List<int>.unmodifiable(validated.photo.bytes),
            fileName: validated.photo.fileName,
            mimeType: validated.mimeType,
          ),
          uploadMetadata: UploadDrawingImageMetadataDto(
            clientCapturedAt: now.toUtc().toIso8601String(),
            rotationDegrees: 0,
            cropApplied: false,
          ),
          drawingDurationMs: now
              .difference(_flowStartedAt)
              .inMilliseconds
              .clamp(1, 1 << 31),
          clientCompletedAt: now.toUtc().toIso8601String(),
          uploadIdempotencyKey: _createIdempotencyKey(),
          completionIdempotencyKey: _createIdempotencyKey(),
        );
        _pendingUploadSnapshot = snapshot;
      }

      attempt = _DrawingUploadAttempt(
        generation: generation,
        snapshot: snapshot,
        cancellation: DrawingUploadCancellation(),
      );
      _activeUploadAttempt = attempt;
      setState(() {
        _phase = _InputPhase.uploading;
        _uploadProgressPercent = 0;
      });
      final repository = widget.repository;
      final uploaded = repository is CancellableDrawingUploadRepository
          ? await repository.uploadDrawing(
              sessionId,
              snapshot.image,
              metadata: snapshot.uploadMetadata,
              idempotencyKey: snapshot.uploadIdempotencyKey,
              cancellation: attempt.cancellation,
              onProgress: (sent, total) =>
                  _handleUploadProgress(attempt!, sent, total),
            )
          : repository is DrawingUploadProgressRepository
          ? await repository.uploadDrawing(
              sessionId,
              snapshot.image,
              metadata: snapshot.uploadMetadata,
              idempotencyKey: snapshot.uploadIdempotencyKey,
              onProgress: (sent, total) =>
                  _handleUploadProgress(attempt!, sent, total),
            )
          : await repository.uploadDrawing(
              sessionId,
              snapshot.image,
              metadata: snapshot.uploadMetadata,
              idempotencyKey: snapshot.uploadIdempotencyKey,
            );
      if (!_isAttemptCurrent(attempt)) return;

      if (widget.repository is! UploadedDrawingCompletionRepository) {
        throw UnsupportedError('Uploaded drawing completion is unavailable.');
      }
      endpoint = DrawingUploadEndpoint.completion;
      setState(() {
        _phase = _InputPhase.completing;
        _uploadProgressPercent = null;
      });
      completionFuture =
          (widget.repository as UploadedDrawingCompletionRepository)
              .completeUploadedDrawingStage(
                sessionId,
                metadata: DrawingCompleteMetadataDto(
                  sourceAssetId: uploaded.drawingAssetId,
                  drawingDurationMs: snapshot.drawingDurationMs,
                  clientCompletedAt: snapshot.clientCompletedAt,
                ),
                idempotencyKey: snapshot.completionIdempotencyKey,
              );
      _completionSettlement = completionFuture;
      final completed = await completionFuture;
      if (!_isAttemptCurrent(attempt)) return;
      if (!mounted) return;
      final initial = _sessionResolution!;
      _activeUploadAttempt = null;
      _isLeaving = true;
      _phase = _InputPhase.leaving;
      Navigator.of(context).pop(
        DrawingSessionResolution(
          sessionId: completed.drawingSessionId,
          currentStage: completed.currentStage,
          activityContext: initial.activityContext,
          inputMethod: 'UPLOAD',
          // 업로드 완료 분석 ID를 대화 화면까지 넘겨 첫 질문을 생성하게 한다
          // (S15P11B209-942).
          conversationAnalysisId: completed.analysis.analysisId,
        ),
      );
    } on Object catch (error) {
      final stillCurrent = attempt == null
          ? _isOperationCurrent(generation)
          : _isAttemptCurrent(attempt);
      if (!stillCurrent) return;
      if (attempt == null && _preUploadCancelRequested) return;
      _activeUploadAttempt = null;
      if (isDrawingUploadCancelled(error)) {
        setState(() {
          _phase = _InputPhase.idle;
          _uploadError = null;
          _uploadProgressPercent = null;
        });
        return;
      }
      setState(() {
        _phase = _InputPhase.idle;
        _uploadError = DrawingUploadErrorPresentation.of(
          error,
          endpoint: endpoint,
        );
        _uploadProgressPercent = null;
      });
    } finally {
      if (identical(_completionSettlement, completionFuture)) {
        _completionSettlement = null;
      }
      if (identical(_activeUploadAttempt, attempt)) {
        _activeUploadAttempt = null;
      }
      if (_isOperationCurrent(generation) &&
          _phase != _InputPhase.idle &&
          _phase != _InputPhase.leaving) {
        setState(() => _phase = _InputPhase.idle);
      }
    }
  }

  void _handleUploadProgress(
    _DrawingUploadAttempt attempt,
    int sent,
    int total,
  ) {
    if (!_isAttemptCurrent(attempt) ||
        _phase != _InputPhase.uploading ||
        total <= 0) {
      return;
    }
    final percent = ((sent / total) * 100).floor().clamp(0, 100);
    if (_uploadProgressPercent == percent) return;
    setState(() => _uploadProgressPercent = percent);
  }

  bool _isOperationCurrent(int generation) =>
      mounted && !_isLeaving && generation == _uploadGeneration;

  bool _isAttemptCurrent(_DrawingUploadAttempt? attempt) =>
      attempt != null &&
      _isOperationCurrent(attempt.generation) &&
      identical(_activeUploadAttempt, attempt) &&
      !attempt.cancellation.isCancelled &&
      attempt.snapshot.routeIdentity ==
          _uploadRouteIdentity(attempt.snapshot.sessionId);

  String _uploadRouteIdentity(int sessionId) {
    final context = _sessionResolution?.activityContext;
    return '${widget.childId}|${widget.drawingTypeId}|$sessionId|'
        '${widget.htpAssessmentId ?? context?.htpAssessmentId}|'
        '${context?.stepOrder}|${context?.drawingSubject}|UPLOAD';
  }

  void _invalidateUpload({required bool clearSnapshot}) {
    _uploadGeneration += 1;
    final attempt = _activeUploadAttempt;
    _activeUploadAttempt = null;
    attempt?.cancellation.cancel();
    if (clearSnapshot) _pendingUploadSnapshot = null;
  }

  void _cancelUpload() {
    if (_phase != _InputPhase.uploading) return;
    final attempt = _activeUploadAttempt;
    if (attempt == null || attempt.cancellation.isCancelled) return;
    attempt.cancellation.cancel();
    setState(() {
      _uploadError = null;
      _uploadProgressPercent = null;
    });
  }

  void _cancelPreparation() {
    if (_phase != _InputPhase.creatingSession || _preUploadCancelRequested) {
      return;
    }
    setState(() => _preUploadCancelRequested = true);
  }

  Future<void> _leave() async {
    if (_isLeaving) return;
    final phaseAtLeave = _phase;
    final pendingCompletion = _completionSettlement;
    final pendingSessionCreation = _sessionCreationFuture;
    _isLeaving = true;
    _invalidatePicker();
    if (phaseAtLeave == _InputPhase.completing) {
      _uploadGeneration += 1;
      _activeUploadAttempt = null;
    } else {
      _invalidateUpload(clearSnapshot: false);
    }
    setState(() => _phase = _InputPhase.leaving);

    if (pendingCompletion != null) {
      try {
        final completed = await pendingCompletion;
        if (!mounted) return;
        final initial = _sessionResolution;
        if (initial != null) {
          Navigator.of(context).pop(
            DrawingSessionResolution(
              sessionId: completed.drawingSessionId,
              currentStage: completed.currentStage,
              activityContext: initial.activityContext,
              inputMethod: 'UPLOAD',
              conversationAnalysisId: completed.analysis.analysisId,
            ),
          );
          return;
        }
      } on Object {
        // 완료가 실패하면 아래에서 이 화면이 만든 미완료 세션을 정리한다.
      }
    }

    if (pendingSessionCreation != null) {
      try {
        await pendingSessionCreation;
      } on Object {
        // 생성 실패라면 정리할 세션이 없으므로 그대로 이탈한다.
      }
    }

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
    final repository = widget.repository as HtpDrawingRepository;
    final requestIdentity = '$_routeInputIdentity|NEXT_STEP|$inputMethod';
    // 같은 논리 요청의 재시도만 같은 Key를 쓴다. assessment/session/stage 또는
    // 입력 방식이 바뀌면 Backend 전역 unique 제약과 충돌하지 않도록 새 Key를 쓴다.
    if (_advanceRequestIdentity != requestIdentity) {
      _advanceRequestIdentity = requestIdentity;
      _advanceIdempotencyKey = null;
    }
    final idempotencyKey = _advanceIdempotencyKey ??=
        widget.idempotencyKeyProvider?.call() ?? _createIdempotencyKey();
    final assessment = await repository.moveToNextHtpStep(
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
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      // 촬영 도움말에서의 시스템 back은 화면을 떠나는 대신 사진 소스 선택으로
      // 돌아간다 — `돌아가기` 버튼과 같은 동작이다(S15P11B209-471).
      if (_step == _Step.cameraGuidance && _canStartAction) {
        _backToPhotoSource();
        return;
      }
      unawaited(_leave());
    },
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
                  _Step.cameraGuidance => _buildCameraGuidance(context),
                  // 선촬영해 둔 사진은 이미 확인·재촬영을 거쳤으므로 "이 사진으로
                  // 시작할까?" 확인 대신 곧장 업로드 진행 화면만 보여준다
                  // (S15P11B209-872).
                  _Step.preview => widget.pendingPhoto != null
                      ? _buildPendingUpload(context)
                      : _buildPreview(context),
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
              if (widget.htpPhotoUploadEnabled)
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
        onPressed: _busy ? null : () => unawaited(_leave()),
      ),
    ],
  );

  /// 시스템 카메라를 열기 전에 보여주는 촬영 도움말(S15P11B209-471).
  ///
  /// 바깥 `SingleChildScrollView` 안에 들어가므로 여기서 다시 스크롤을 만들지
  /// 않는다. 아이콘은 문구를 거드는 장식이라 스크린리더에서 제외하고, 읽기
  /// 순서는 제목 → 도움말 → CTA가 되도록 배치 순서를 그대로 따른다.
  Widget _buildCameraGuidance(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buildHeader(title: '그림을 예쁘게 찍어볼까?', description: '그림이 잘 보이도록 이렇게 찍어줘.'),
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
      Container(
        key: const ValueKey('camera-guidance-tips'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, (icon, text))
                in _cameraGuidanceTips.indexed) ...[
              if (index > 0) const SizedBox(height: AppSpacing.md),
              _CameraGuidanceTip(icon: icon, text: text),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      AppButton(
        key: const ValueKey('camera-guidance-capture'),
        label: '촬영하기',
        variant: AppButtonVariant.child,
        isLoading: _phase == _InputPhase.picking,
        onPressed: _busy ? null : () => unawaited(_captureFromCamera()),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppButton(
        key: const ValueKey('camera-guidance-back'),
        label: '돌아가기',
        variant: AppButtonVariant.secondary,
        onPressed: _busy ? null : _backToPhotoSource,
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
                  // 카메라는 촬영 도움말을 먼저 보여준다 — 여기서는 단계만
                  // 바꾸고 picker·권한·세션을 건드리지 않는다.
                  onTap: _busy ? null : _showCameraGuidance,
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
              onPressed: _busy ? null : () => unawaited(_leave()),
            ),
          ),
        ],
      ),
    ],
  );

  /// 선촬영한 사진의 주제(집·나무·사람) 라벨. 진행 문구에 붙인다.
  String get _pendingSubjectLabel => switch (widget
          .restoredActivityContext
          ?.drawingSubject) {
    'HOUSE' => '집',
    'TREE' => '나무',
    'PERSON' => '사람',
    _ => '',
  };

  /// 선촬영해 둔 사진을 자동 업로드하는 동안 보여주는 화면(S15P11B209-872).
  ///
  /// 미리보기·"이 사진 사용하기" 확인을 없애고, 도담이가 진행률만큼 걸어가는
  /// 로딩바만 보여준다. 진행률은 실제 업로드 진행(onSendProgress)에 묶여 있어
  /// 반복 애니메이션이 없다(완료 시 값이 확정돼 테스트에서도 정착한다).
  Widget _buildPendingUpload(BuildContext context) {
    final subject = _pendingSubjectLabel;
    final prefix = subject.isEmpty ? '' : '$subject 그림 ';
    // 진행률바 배분: 실제 바이트 전송은 앞 85%에만 반영하고(파일 전송은 금방
    // 끝난다), 진행 신호가 없는 서버 처리(완료 응답 대기) 구간은 85%→98%로
    // 천천히 기어가게 해 "꽉 채우고 멈춤"으로 보이지 않게 한다.
    const sendShare = 0.85;
    final sent = (_uploadProgressPercent ?? 0) / 100;
    final (double progress, String message, Duration duration) =
        switch (_phase) {
          _InputPhase.creatingSession => (
            0.05,
            '사진을 올릴 준비를 하고 있어요',
            const Duration(milliseconds: 400),
          ),
          _InputPhase.uploading => (
            0.05 + sent * (sendShare - 0.05),
            '$prefix사진을 올리고 있어요',
            const Duration(milliseconds: 450),
          ),
          // 서버 처리 대기: 실제 진행 신호가 없어 100%에는 닿지 않게 하고
          // 8초에 걸쳐 98%까지 서서히 기어간다(유한 → 테스트에서 정착).
          _InputPhase.completing => (
            0.98,
            '$prefix사진을 확인하고 있어요',
            const Duration(seconds: 8),
          ),
          _ => (
            0.05,
            '$prefix사진을 올리고 있어요',
            const Duration(milliseconds: 400),
          ),
        };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_uploadError case final error?) ...[
          _ErrorBanner(
            key: const ValueKey('input-method-upload-error'),
            icon: error.icon,
            message: error.message,
          ),
          if (error.canRetry) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const ValueKey('input-method-confirm'),
              label: '다시 시도',
              variant: AppButtonVariant.child,
              onPressed: _canStartAction ? _confirmAndUpload : null,
            ),
          ],
        ] else
          _UploadMascotBar(
            key: const ValueKey('input-method-pending-upload'),
            progress: progress,
            message: message,
            duration: duration,
          ),
      ],
    );
  }

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
        if (_phase == _InputPhase.uploading)
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
        if (_phase == _InputPhase.creatingSession) ...[
          Semantics(
            liveRegion: true,
            label: '업로드 준비 중',
            child: const Text('사진을 올릴 준비를 하고 있어요'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_phase == _InputPhase.completing) ...[
          Semantics(
            liveRegion: true,
            label: '완료 처리 중',
            child: const Text('완료 처리 중이에요'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_uploadError?.canRetry != false)
          AppButton(
            key: const ValueKey('input-method-confirm'),
            label: _uploadError != null ? '다시 시도' : '이 사진 사용하기',
            variant: AppButtonVariant.child,
            isLoading:
                _phase == _InputPhase.creatingSession ||
                _phase == _InputPhase.uploading ||
                _phase == _InputPhase.completing,
            onPressed: _canStartAction ? _confirmAndUpload : null,
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
                onPressed: _canStartAction ? _reselectPhoto : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                key: const ValueKey('input-method-preview-cancel'),
                label: switch (_phase) {
                  _InputPhase.creatingSession =>
                    _preUploadCancelRequested ? '준비 취소 중' : '준비 취소',
                  _InputPhase.uploading =>
                    _activeUploadAttempt?.cancellation.isCancelled == true
                        ? '업로드 취소 중'
                        : '업로드 취소',
                  _InputPhase.completing => '완료 처리 중',
                  _InputPhase.leaving || _InputPhase.disposed => '나가는 중',
                  _ => '취소',
                },
                variant: AppButtonVariant.secondary,
                onPressed: switch (_phase) {
                  _InputPhase.creatingSession =>
                    _preUploadCancelRequested ? null : _cancelPreparation,
                  _InputPhase.uploading =>
                    _activeUploadAttempt?.cancellation.isCancelled == true
                        ? null
                        : _cancelUpload,
                  _InputPhase.idle => () => unawaited(_leave()),
                  _ => null,
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 도담이가 진행률만큼 바 위를 걸어가는 업로드 로딩바(S15P11B209-872).
///
/// [progress](0~1)와 [TweenAnimationBuilder]로만 움직인다 — `repeat()` 같은
/// 무한 반복이 없어 업로드가 끝나 값이 확정되면 애니메이션이 정착한다(위젯
/// 테스트의 pumpAndSettle가 타임아웃 나지 않는다).
class _UploadMascotBar extends StatelessWidget {
  const _UploadMascotBar({
    required this.progress,
    required this.message,
    required this.duration,
    super.key,
  });

  final double progress;
  final String message;

  /// 현재 진행률로 채워지는 데 걸리는 시간. 전송 구간은 짧게 반응하고, 서버
  /// 처리 대기 구간은 길게 잡아 바가 멈춘 듯 보이지 않고 서서히 차오르게 한다.
  final Duration duration;

  static const double _mascotSize = 168;
  static const double _trackHeight = 18;

  @override
  Widget build(BuildContext context) {
    final target = progress.clamp(0.0, 1.0);
    return Semantics(
      liveRegion: true,
      label: message,
      value: '${(target * 100).round()}%',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final travel = (width - _mascotSize).clamp(0.0, width);
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: target),
                  duration: duration,
                  curve: Curves.easeOut,
                  builder: (context, value, _) => SizedBox(
                    width: width,
                    height: _mascotSize + _trackHeight + AppSpacing.xs,
                    child: Stack(
                      children: [
                        Positioned(
                          left: travel * value,
                          top: 0,
                          child: Image.asset(
                            'assets/characters/dodam_resume_loading.png',
                            width: _mascotSize,
                            height: _mascotSize,
                            filterQuality: FilterQuality.medium,
                            // 테스트 등 에셋을 못 읽는 환경에서도 예외로 실패하지
                            // 않도록 자리만 차지하는 placeholder로 대체한다.
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: _mascotSize,
                              height: _mascotSize,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              _trackHeight / 2,
                            ),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: _trackHeight,
                              backgroundColor: AppColors.outline,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.tangerine,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: AppTypography.body),
          ],
        ),
      ),
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
/// 촬영 도움말 한 줄. 아이콘은 장식이라 낭독에서 제외하고 문구만 읽게 한다.
class _CameraGuidanceTip extends StatelessWidget {
  const _CameraGuidanceTip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: Icon(icon, size: AppIconSize.lg, color: AppColors.tangerine),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text, style: AppTypography.body)),
    ],
  );
}

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
      PhotoPermissionStatus.granted => '$target에 접근하지 못했어요. 다시 시도해 주세요.',
      PhotoPermissionStatus.denied => '$target 권한이 필요해요. 다시 선택해 권한을 허용해 주세요.',
      PhotoPermissionStatus.permanentlyDenied => '기기 설정에서 $target 권한을 허용해 주세요.',
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
