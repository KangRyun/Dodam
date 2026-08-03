import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../design_system/design_system.dart';
import '../../data/device_photo_permission_service.dart';
import '../../domain/photo_permission_service.dart';
import '../../domain/photo_picker_adapter.dart';

const _tutorialStorageKey = 'htp_camera_tutorial_hidden';

Future<List<CameraDescription>> _availablePluginCameras() => availableCameras();

abstract interface class GuidedCameraController {
  bool get isInitialized;
  double get aspectRatio;

  Widget buildPreview();
  Future<void> initialize();
  Future<void> dispose();
  Future<void> setFlashMode(FlashMode mode);
  Future<void> setFocusPoint(Offset point);
  Future<void> setExposurePoint(Offset point);
  Future<PickedPhoto> takePicture();
}

abstract interface class GuidedCameraPlatform {
  Future<List<CameraDescription>> availableCameras();
  GuidedCameraController createController(CameraDescription description);
}

abstract interface class GuidedCameraTutorialStore {
  Future<bool> isHidden();
  Future<void> hide();
}

final class _PluginGuidedCameraPlatform implements GuidedCameraPlatform {
  const _PluginGuidedCameraPlatform();

  @override
  Future<List<CameraDescription>> availableCameras() =>
      _availablePluginCameras();

  @override
  GuidedCameraController createController(CameraDescription description) =>
      _PluginGuidedCameraController(description);
}

final class _PluginGuidedCameraController implements GuidedCameraController {
  _PluginGuidedCameraController(CameraDescription description)
    : _controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

  final CameraController _controller;

  @override
  bool get isInitialized => _controller.value.isInitialized;
  @override
  double get aspectRatio => _controller.value.aspectRatio;
  @override
  Widget buildPreview() => CameraPreview(_controller);
  @override
  Future<void> initialize() => _controller.initialize();
  @override
  Future<void> dispose() => _controller.dispose();
  @override
  Future<void> setFlashMode(FlashMode mode) => _controller.setFlashMode(mode);
  @override
  Future<void> setFocusPoint(Offset point) => _controller.setFocusPoint(point);
  @override
  Future<void> setExposurePoint(Offset point) =>
      _controller.setExposurePoint(point);
  @override
  Future<PickedPhoto> takePicture() async {
    final file = await _controller.takePicture();
    return PickedPhoto(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      mimeType: 'image/jpeg',
    );
  }
}

final class _SecureGuidedCameraTutorialStore
    implements GuidedCameraTutorialStore {
  const _SecureGuidedCameraTutorialStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<bool> isHidden() async =>
      await _storage.read(key: _tutorialStorageKey) == 'true';
  @override
  Future<void> hide() =>
      _storage.write(key: _tutorialStorageKey, value: 'true');
}

enum _CameraFailureKind {
  permissionDenied,
  permissionPermanentlyDenied,
  permissionRestricted,
  noCamera,
  cameraInUse,
  initialization,
}

final class _CameraFailure {
  const _CameraFailure(this.kind, this.message);

  final _CameraFailureKind kind;
  final String message;
}

/// 종이 그림이 프레임 안에 들어오도록 안내하는 HTP 전용 인앱 카메라.
class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({
    required this.drawingSubject,
    this.cameraPlatform,
    this.permissionService,
    this.tutorialStore,
    super.key,
  });

  final String drawingSubject;
  final GuidedCameraPlatform? cameraPlatform;
  final PhotoPermissionService? permissionService;
  final GuidedCameraTutorialStore? tutorialStore;

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen>
    with WidgetsBindingObserver {
  late final GuidedCameraPlatform _cameraPlatform =
      widget.cameraPlatform ?? const _PluginGuidedCameraPlatform();
  late final PhotoPermissionService _permissionService =
      widget.permissionService ?? const DevicePhotoPermissionService();
  late final GuidedCameraTutorialStore _tutorialStore =
      widget.tutorialStore ?? const _SecureGuidedCameraTutorialStore();

  GuidedCameraController? _controller;
  _CameraFailure? _failure;
  bool _initializing = true;
  bool _capturing = false;
  bool _tutorialVisible = false;
  bool _hideTutorial = false;
  bool _openingSettings = false;
  bool _foreground = true;
  bool _detached = false;
  bool _disposed = false;
  FlashMode _flashMode = FlashMode.off;
  int _generation = 0;
  int? _requestedInitializationGeneration;
  Future<void> _operations = Future<void>.value();

  String get _subjectLabel => switch (widget.drawingSubject.toUpperCase()) {
    'TREE' => '나무',
    'PERSON' => '사람',
    _ => '집',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final generation = _generation;
    _requestedInitializationGeneration = generation;
    _enqueue(
      () => _initializeGeneration(
        generation,
        requestPermission: true,
        showTutorial: true,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || _detached) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (_foreground) return;
        _foreground = true;
        _generation += 1;
        _scheduleInitialization(requestPermission: false, showTutorial: false);
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _releaseForBackground(detached: false);
        return;
      case AppLifecycleState.detached:
        _releaseForBackground(detached: true);
        return;
    }
  }

  static Future<void> _runAfter(
    Future<void> previous,
    Future<void> Function() operation,
  ) async {
    try {
      await previous;
    } on Object {
      // 앞선 실패가 다음 lifecycle 작업을 막지 않게 한다.
    }
    try {
      await operation();
    } on Object {
      // 개별 작업은 화면 상태로 변환하며 dispose 실패는 안전하게 무시한다.
    }
  }

  void _enqueue(Future<void> Function() operation) {
    final previous = _operations;
    _operations = _runAfter(previous, operation);
  }

  bool _isCurrent(int generation) =>
      mounted &&
      !_disposed &&
      !_detached &&
      _foreground &&
      generation == _generation;

  bool _isControllerCurrent(
    GuidedCameraController controller,
    int generation,
  ) => _isCurrent(generation) && identical(_controller, controller);

  void _scheduleInitialization({
    required bool requestPermission,
    required bool showTutorial,
  }) {
    if (!mounted || _disposed || _detached || !_foreground) return;
    final generation = _generation;
    if (_requestedInitializationGeneration == generation) return;
    _requestedInitializationGeneration = generation;
    setState(() {
      _initializing = true;
      _failure = null;
    });
    _enqueue(
      () => _initializeGeneration(
        generation,
        requestPermission: requestPermission,
        showTutorial: showTutorial,
      ),
    );
  }

  void _retry({bool requestPermission = false}) {
    if (_initializing || !_foreground || _detached || _disposed) return;
    _generation += 1;
    _scheduleInitialization(
      requestPermission: requestPermission,
      showTutorial: false,
    );
  }

  Future<void> _initializeGeneration(
    int generation, {
    required bool requestPermission,
    required bool showTutorial,
  }) async {
    GuidedCameraController? candidate;
    try {
      var permission = await _permissionService.status(
        PhotoPermissionKind.camera,
      );
      if (!_isCurrent(generation)) return;
      if (permission == PhotoPermissionStatus.denied && requestPermission) {
        permission = await _permissionService.request(
          PhotoPermissionKind.camera,
        );
      }
      if (!_isCurrent(generation)) return;
      if (permission != PhotoPermissionStatus.granted) {
        _showFailure(_permissionFailure(permission), generation);
        return;
      }

      final cameras = await _cameraPlatform.availableCameras();
      if (!_isCurrent(generation)) return;
      if (cameras.isEmpty) {
        _showFailure(
          const _CameraFailure(
            _CameraFailureKind.noCamera,
            '이 기기에서 사용할 수 있는 카메라를 찾지 못했어요.',
          ),
          generation,
        );
        return;
      }
      final rearCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      candidate = _cameraPlatform.createController(rearCamera);
      await candidate.initialize();
      if (!_isCurrent(generation)) {
        await _disposeSafely(candidate);
        candidate = null;
        return;
      }
      await candidate.setFlashMode(_flashMode);
      if (!_isCurrent(generation)) {
        await _disposeSafely(candidate);
        candidate = null;
        return;
      }
      final hidden = showTutorial ? await _tutorialStore.isHidden() : true;
      if (!_isCurrent(generation)) {
        await _disposeSafely(candidate);
        candidate = null;
        return;
      }
      final previous = _controller;
      final initialized = candidate;
      candidate = null;
      setState(() {
        _controller = initialized;
        _initializing = false;
        _failure = null;
        _tutorialVisible = !hidden;
      });
      if (previous != null && !identical(previous, initialized)) {
        await _disposeSafely(previous);
      }
    } on Object catch (error) {
      if (candidate != null) await _disposeSafely(candidate);
      if (_isCurrent(generation)) {
        _showFailure(_failureFor(error), generation);
      }
    } finally {
      if (_requestedInitializationGeneration == generation) {
        _requestedInitializationGeneration = null;
      }
    }
  }

  _CameraFailure _permissionFailure(PhotoPermissionStatus status) =>
      switch (status) {
        PhotoPermissionStatus.granted => const _CameraFailure(
          _CameraFailureKind.initialization,
          '카메라를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.',
        ),
        PhotoPermissionStatus.denied => const _CameraFailure(
          _CameraFailureKind.permissionDenied,
          '사진을 찍으려면 카메라 권한이 필요해요.',
        ),
        PhotoPermissionStatus.permanentlyDenied => const _CameraFailure(
          _CameraFailureKind.permissionPermanentlyDenied,
          '기기 설정에서 카메라 권한을 허용해 주세요.',
        ),
        PhotoPermissionStatus.restricted => const _CameraFailure(
          _CameraFailureKind.permissionRestricted,
          '카메라 사용이 기기 설정 또는 보호자 정책으로 제한되어 있어요.',
        ),
      };

  _CameraFailure _failureFor(Object error) {
    if (error is CameraException) {
      final code = error.code.toLowerCase();
      if (code.contains('restricted')) {
        return _permissionFailure(PhotoPermissionStatus.restricted);
      }
      if (code.contains('withoutprompt') || code.contains('permanent')) {
        return _permissionFailure(PhotoPermissionStatus.permanentlyDenied);
      }
      if (code.contains('denied')) {
        return _permissionFailure(PhotoPermissionStatus.denied);
      }
      if (code.contains('inuse') ||
          code.contains('in_use') ||
          code.contains('busy') ||
          code.contains('already')) {
        return const _CameraFailure(
          _CameraFailureKind.cameraInUse,
          '다른 앱에서 카메라를 사용 중이에요. 잠시 후 다시 시도해 주세요.',
        );
      }
    }
    return const _CameraFailure(
      _CameraFailureKind.initialization,
      '카메라를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.',
    );
  }

  void _showFailure(_CameraFailure failure, int generation) {
    if (!_isCurrent(generation)) return;
    setState(() {
      _controller = null;
      _failure = failure;
      _initializing = false;
      _tutorialVisible = false;
    });
  }

  void _releaseForBackground({required bool detached}) {
    if (_detached || (!_foreground && !detached)) return;
    _foreground = false;
    _detached = detached;
    _generation += 1;
    _requestedInitializationGeneration = null;
    final controller = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _initializing = false;
        _capturing = false;
        _tutorialVisible = false;
      });
    }
    if (controller != null) {
      _enqueue(() => _disposeSafely(controller));
    }
  }

  Future<void> _disposeSafely(GuidedCameraController controller) async {
    try {
      await controller.dispose();
    } on Object {
      // lifecycle 정리 실패가 이후 재초기화를 막지 않게 한다.
    }
  }

  Future<void> _closeTutorial() async {
    final generation = _generation;
    if (_hideTutorial) {
      await _tutorialStore.hide();
    }
    if (_isCurrent(generation)) {
      setState(() => _tutorialVisible = false);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    final generation = _generation;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (_isControllerCurrent(controller, generation)) {
        setState(() => _flashMode = next);
      }
    } on Object {
      if (mounted && _isControllerCurrent(controller, generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 기기에서는 플래시를 사용할 수 없어요.')),
        );
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.isInitialized || _capturing) {
      return;
    }
    final generation = _generation;
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      if (!mounted || !_isControllerCurrent(controller, generation)) return;
      Navigator.of(context).pop(photo);
    } on Object {
      if (mounted && _isControllerCurrent(controller, generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진을 찍지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (_isControllerCurrent(controller, generation)) {
        setState(() => _capturing = false);
      }
    }
  }

  Future<void> _focus(TapDownDetails details, Size previewSize) async {
    final controller = _controller;
    if (controller == null || !controller.isInitialized) return;
    final generation = _generation;
    final point = Offset(
      (details.localPosition.dx / previewSize.width).clamp(0, 1),
      (details.localPosition.dy / previewSize.height).clamp(0, 1),
    );
    try {
      await controller.setFocusPoint(point);
      if (!_isControllerCurrent(controller, generation)) return;
      await controller.setExposurePoint(point);
    } on Object {
      // 일부 기기는 초점 좌표 설정을 지원하지 않아도 촬영은 가능하다.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _detached = true;
    _foreground = false;
    _generation += 1;
    _requestedInitializationGeneration = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      _enqueue(() => _disposeSafely(controller));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF292E35),
    body: SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _CameraHeader(
                subject: _subjectLabel,
                flashEnabled: _flashMode != FlashMode.off,
                onClose: () => Navigator.of(context).pop(),
                onFlash: _toggleFlash,
                onHelp: () => setState(() => _tutorialVisible = true),
              ),
              Expanded(child: _buildPreview()),
              _CameraControls(
                capturing: _capturing,
                onCapture: _capture,
                onGallery: () => Navigator.of(context).pop('gallery'),
              ),
            ],
          ),
          if (_tutorialVisible)
            _TutorialOverlay(
              hideAgain: _hideTutorial,
              onChanged: (value) => setState(() => _hideTutorial = value),
              onClose: _closeTutorial,
            ),
        ],
      ),
    ),
  );

  Widget _buildPreview() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.sunshine),
      );
    }
    if (_failure case final failure?) {
      return _CameraError(
        failure: failure,
        openingSettings: _openingSettings,
        onRetry: () => _retry(
          requestPermission:
              failure.kind == _CameraFailureKind.permissionDenied,
        ),
        onSettings:
            failure.kind == _CameraFailureKind.permissionPermanentlyDenied
            ? _openPermissionSettings
            : null,
      );
    }
    if (_controller == null) {
      return _CameraError(
        failure: const _CameraFailure(
          _CameraFailureKind.initialization,
          '카메라를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.',
        ),
        openingSettings: false,
        onRetry: () => _retry(),
      );
    }
    final controller = _controller!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = _containedPreviewSize(
            constraints.biggest,
            controller.aspectRatio,
          );
          return Center(
            child: SizedBox.fromSize(
              key: const ValueKey('guided-camera-preview-space'),
              size: previewSize,
              child: GestureDetector(
                key: const ValueKey('guided-camera-focus-area'),
                onTapDown: (details) => _focus(details, previewSize),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF383E47),
                        child: KeyedSubtree(
                          key: const ValueKey('guided-camera-preview'),
                          child: controller.buildPreview(),
                        ),
                      ),
                      const KeyedSubtree(
                        key: ValueKey('guided-camera-guide'),
                        child: _PaperGuideFrame(),
                      ),
                      Positioned(
                        top: 14,
                        right: 14,
                        child: _HtpStepPanel(
                          currentSubject: widget.drawingSubject,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '그림 전체가 네모 안에 들어오게 해주세요',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Size _containedPreviewSize(Size available, double aspectRatio) {
    final safeAspectRatio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 1.0;
    if (available.width / available.height > safeAspectRatio) {
      return Size(available.height * safeAspectRatio, available.height);
    }
    return Size(available.width, available.width / safeAspectRatio);
  }

  Future<void> _openPermissionSettings() async {
    if (_openingSettings) return;
    setState(() => _openingSettings = true);
    var opened = false;
    try {
      opened = await _permissionService.openSettings();
    } on Object {
      opened = false;
    }
    if (!mounted || _disposed) return;
    setState(() => _openingSettings = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('설정 화면을 열지 못했어요. 기기 설정에서 카메라 권한을 확인해 주세요.'),
        ),
      );
    }
  }
}

class _CameraHeader extends StatelessWidget {
  const _CameraHeader({
    required this.subject,
    required this.flashEnabled,
    required this.onClose,
    required this.onFlash,
    required this.onHelp,
  });

  final String subject;
  final bool flashEnabled;
  final VoidCallback onClose, onFlash, onHelp;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 68,
    child: Row(
      children: [
        TextButton.icon(
          key: const ValueKey('guided-camera-close'),
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          label: const Text('닫기'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
        Expanded(
          child: Text(
            '종이 그림 찍기 · $subject',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: '촬영 도움말',
          onPressed: onHelp,
          color: Colors.white70,
          icon: const Icon(Icons.help_outline_rounded),
        ),
        TextButton.icon(
          onPressed: onFlash,
          icon: Icon(flashEnabled ? Icons.flash_on : Icons.flash_off),
          label: Text(flashEnabled ? '켜짐' : '플래시'),
          style: TextButton.styleFrom(
            foregroundColor: flashEnabled ? AppColors.sunshine : Colors.white70,
          ),
        ),
      ],
    ),
  );
}

class _CameraControls extends StatelessWidget {
  const _CameraControls({
    required this.capturing,
    required this.onCapture,
    required this.onGallery,
  });

  final bool capturing;
  final VoidCallback onCapture, onGallery;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 36,
          child: IconButton.filledTonal(
            tooltip: '앨범에서 선택',
            onPressed: capturing ? null : onGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ),
        Semantics(
          key: const ValueKey('guided-camera-capture'),
          button: true,
          label: capturing ? '사진 촬영 중' : '사진 촬영',
          child: InkWell(
            onTap: capturing ? null : onCapture,
            customBorder: const CircleBorder(),
            child: Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: capturing ? Colors.white38 : Colors.white,
                ),
                child: capturing
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PaperGuideFrame extends StatelessWidget {
  const _PaperGuideFrame();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 54, vertical: 42),
      child: CustomPaint(painter: _GuideFramePainter()),
    ),
  );
}

class _HtpStepPanel extends StatelessWidget {
  const _HtpStepPanel({required this.currentSubject});

  final String currentSubject;

  @override
  Widget build(BuildContext context) {
    const steps = [('HOUSE', '집'), ('TREE', '나무'), ('PERSON', '사람')];
    final currentIndex = steps.indexWhere(
      (step) => step.$1 == currentSubject.toUpperCase(),
    );
    return Container(
      width: 142,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF20252C).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '필요한 그림',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < steps.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    index < currentIndex
                        ? Icons.check_circle_rounded
                        : index == currentIndex
                        ? Icons.camera_alt_rounded
                        : Icons.circle_outlined,
                    size: 16,
                    color: index <= currentIndex
                        ? AppColors.sunshine
                        : Colors.white38,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      steps[index].$2,
                      style: TextStyle(
                        color: index == currentIndex
                            ? Colors.white
                            : Colors.white60,
                        fontWeight: index == currentIndex
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (index == currentIndex)
                    const Text(
                      '촬영 중',
                      style: TextStyle(color: AppColors.sunshine, fontSize: 11),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 9.0;
    const gap = 7.0;
    final rect = Offset.zero & size;
    for (var x = 0.0; x < rect.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + dash).clamp(0, rect.width), 0),
        border,
      );
      canvas.drawLine(
        Offset(x, rect.height),
        Offset((x + dash).clamp(0, rect.width), rect.height),
        border,
      );
    }
    for (var y = 0.0; y < rect.height; y += dash + gap) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, (y + dash).clamp(0, rect.height)),
        border,
      );
      canvas.drawLine(
        Offset(rect.width, y),
        Offset(rect.width, (y + dash).clamp(0, rect.height)),
        border,
      );
    }
    final corner = Paint()
      ..color = AppColors.sunshine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square;
    const length = 34.0;
    canvas
      ..drawLine(const Offset(0, length), Offset.zero, corner)
      ..drawLine(Offset.zero, const Offset(length, 0), corner)
      ..drawLine(Offset(size.width - length, 0), Offset(size.width, 0), corner)
      ..drawLine(Offset(size.width, 0), Offset(size.width, length), corner)
      ..drawLine(
        Offset(0, size.height - length),
        Offset(0, size.height),
        corner,
      )
      ..drawLine(Offset(0, size.height), Offset(length, size.height), corner)
      ..drawLine(
        Offset(size.width - length, size.height),
        Offset(size.width, size.height),
        corner,
      )
      ..drawLine(
        Offset(size.width, size.height),
        Offset(size.width, size.height - length),
        corner,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TutorialOverlay extends StatelessWidget {
  const _TutorialOverlay({
    required this.hideAgain,
    required this.onChanged,
    required this.onClose,
  });

  final bool hideAgain;
  final ValueChanged<bool> onChanged;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.58),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF4CF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.tangerine,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '사진 찍기 전에 확인해 주세요',
                            style: AppTypography.titleMd,
                          ),
                          SizedBox(height: 4),
                          Text(
                            '아래 내용을 지켜주시면 그림을 더 정확하게 확인할 수 있어요.',
                            style: AppTypography.bodySm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _TutorialItem(text: '다른 그림이 섞이지 않게 한 장만 찍어주세요.'),
                const _TutorialItem(text: '밝은 곳에서 그림자가 지지 않게 찍어주세요.'),
                const _TutorialItem(text: '종이가 접히거나 가려지지 않게 펼쳐주세요.'),
                const _TutorialItem(text: '그림 전체가 네모 안내선 안에 들어오게 해주세요.'),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: hideAgain,
                  onChanged: (value) => onChanged(value ?? false),
                  title: const Text('다시 보지 않기'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.leaf,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: const Text('확인 · 사진 찍으러 가기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TutorialItem extends StatelessWidget {
  const _TutorialItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        const Icon(Icons.circle, size: 7, color: AppColors.tangerine),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTypography.body)),
      ],
    ),
  );
}

class _CameraError extends StatelessWidget {
  const _CameraError({
    required this.failure,
    required this.openingSettings,
    required this.onRetry,
    this.onSettings,
  });

  final _CameraFailure failure;
  final bool openingSettings;
  final VoidCallback onRetry;
  final Future<void> Function()? onSettings;

  String get _title => switch (failure.kind) {
    _CameraFailureKind.permissionDenied ||
    _CameraFailureKind.permissionPermanentlyDenied => '카메라 권한이 필요해요',
    _CameraFailureKind.permissionRestricted => '카메라 사용이 제한되어 있어요',
    _CameraFailureKind.noCamera => '카메라를 찾지 못했어요',
    _CameraFailureKind.cameraInUse => '카메라를 사용 중이에요',
    _CameraFailureKind.initialization => '카메라를 열 수 없어요',
  };

  String get _retryLabel => failure.kind == _CameraFailureKind.permissionDenied
      ? '권한 다시 요청'
      : failure.kind == _CameraFailureKind.permissionRestricted
      ? '다시 확인'
      : '다시 시도';

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        key: const ValueKey('guided-camera-error'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: [
                if (failure.kind !=
                    _CameraFailureKind.permissionPermanentlyDenied)
                  OutlinedButton(
                    key: const ValueKey('guided-camera-retry'),
                    onPressed: onRetry,
                    child: Text(_retryLabel),
                  ),
                if (onSettings case final openSettings?)
                  FilledButton(
                    key: const ValueKey('guided-camera-open-settings'),
                    onPressed: openingSettings ? null : openSettings,
                    child: Text(openingSettings ? '설정 여는 중' : '설정 열기'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
