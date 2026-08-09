import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/voice_recording_controller.dart';
import '../../domain/models/voice_recording.dart';

final class VoiceRecordingControl extends StatefulWidget {
  const VoiceRecordingControl({
    required this.controller,
    this.onCompleted,
    this.enabled = true,
    super.key,
  });

  final VoiceRecordingController controller;
  final ValueChanged<VoiceRecording>? onCompleted;
  final bool enabled;

  @override
  State<VoiceRecordingControl> createState() => _VoiceRecordingControlState();
}

final class _VoiceRecordingControlState extends State<VoiceRecordingControl>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(covariant VoiceRecordingControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleChanged);
    widget.controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      widget.controller.interrupt();
    }
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    final controller = widget.controller;
    if (controller.isRecording) {
      final recording = await controller.stop();
      if (recording != null) widget.onCompleted?.call(recording);
      return;
    }
    await controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final recording = controller.recording;
    final recordingNow = controller.isRecording;
    final preparing =
        controller.status == VoiceRecordingStatus.preparing ||
        controller.status == VoiceRecordingStatus.starting;
    final label = preparing
        ? '질문을 들려주고 있어요'
        : recordingNow
        ? '${_formatDuration(controller.elapsed)} 녹음 끝내기'
        : recording == null
        ? '말로 대답할래'
        : '음성 답변 녹음 완료';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('voice-recording-toggle'),
          onPressed:
              !widget.enabled ||
                  controller.isBusy ||
                  (recording != null && !recordingNow)
              ? null
              : _toggleRecording,
          icon: preparing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(recordingNow ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: recordingNow
                ? AppColors.error
                : preparing
                ? AppColors.leaf
                : AppColors.tangerine,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        if (controller.status == VoiceRecordingStatus.permissionDenied) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '말로 대답하려면 마이크 사용을 허용해 주세요.',
            key: ValueKey('microphone-permission-denied'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (controller.status ==
            VoiceRecordingStatus.permissionPermanentlyDenied) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '기기 설정에서 도담의 마이크 권한을 켜 주세요.',
            key: ValueKey('microphone-permission-permanently-denied'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            key: const ValueKey('microphone-open-settings'),
            onPressed: controller.openPermissionSettings,
            icon: const Icon(Icons.settings_rounded),
            label: const Text('기기 설정 열기'),
          ),
        ],
        if (controller.status == VoiceRecordingStatus.failed) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '목소리를 담지 못했어요. 다시 말하거나 아래에서 골라도 괜찮아요.',
            key: ValueKey('voice-recording-failed'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (controller.status == VoiceRecordingStatus.interrupted) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '녹음이 잠시 멈췄어요. 다시 말하거나 아래에서 골라 주세요.',
            key: ValueKey('voice-recording-interrupted'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (recording != null && !recordingNow) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_formatDuration(recording.duration)} 동안 녹음했어요.',
            key: const ValueKey('voice-recording-completed'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
