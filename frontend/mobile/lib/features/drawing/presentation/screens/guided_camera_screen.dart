import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/photo_picker_adapter.dart';

const _tutorialStorageKey = 'htp_camera_tutorial_hidden';

/// 종이 그림이 프레임 안에 들어오도록 안내하는 HTP 전용 인앱 카메라.
class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({required this.drawingSubject, super.key});

  final String drawingSubject;

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen>
    with WidgetsBindingObserver {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  CameraController? _controller;
  Object? _initializationError;
  bool _initializing = true;
  bool _capturing = false;
  bool _tutorialVisible = false;
  bool _hideTutorial = false;
  FlashMode _flashMode = FlashMode.off;

  String get _subjectLabel => switch (widget.drawingSubject.toUpperCase()) {
    'TREE' => '나무',
    'PERSON' => '사람',
    _ => '집',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(controller.dispose());
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initialize(showTutorial: false));
    }
  }

  Future<void> _initialize({bool showTutorial = true}) async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _initializationError = null;
      });
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera is available.');
      final rearCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _controller?.dispose();
      final hidden = showTutorial
          ? await _storage.read(key: _tutorialStorageKey) == 'true'
          : true;
      setState(() {
        _controller = controller;
        _initializing = false;
        _tutorialVisible = !hidden;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _initializationError = error;
        _initializing = false;
      });
    }
  }

  Future<void> _closeTutorial() async {
    if (_hideTutorial) {
      await _storage.write(key: _tutorialStorageKey, value: 'true');
    }
    if (mounted) setState(() => _tutorialVisible = false);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 기기에서는 플래시를 사용할 수 없어요.')),
        );
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(
        PickedPhoto(bytes: bytes, fileName: file.name, mimeType: 'image/jpeg'),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진을 찍지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _focus(
    TapDownDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final point = Offset(
      (details.localPosition.dx / constraints.maxWidth).clamp(0, 1),
      (details.localPosition.dy / constraints.maxHeight).clamp(0, 1),
    );
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } on Object {
      // 일부 기기는 초점 좌표 설정을 지원하지 않아도 촬영은 가능하다.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
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
    if (_initializationError != null || _controller == null) {
      return _CameraError(onRetry: _initialize, onSettings: openAppSettings);
    }
    final controller = _controller!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onTapDown: (details) => _focus(details, constraints),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: const Color(0xFF383E47),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
                const _PaperGuideFrame(),
                Positioned(
                  top: 14,
                  right: 14,
                  child: _HtpStepPanel(currentSubject: widget.drawingSubject),
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
  const _CameraError({required this.onRetry, required this.onSettings});
  final Future<void> Function() onRetry;
  final Future<bool> Function() onSettings;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
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
            const Text(
              '카메라를 열 수 없어요',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '카메라 권한을 확인하거나 잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
                FilledButton(onPressed: onSettings, child: const Text('설정 열기')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
