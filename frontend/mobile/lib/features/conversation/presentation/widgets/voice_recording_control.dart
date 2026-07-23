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

final class _VoiceRecordingControlState extends State<VoiceRecordingControl> {
  @override
  void initState() {
    super.initState();
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
    widget.controller.removeListener(_handleChanged);
    super.dispose();
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
    final label = recordingNow
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
          icon: controller.isBusy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(recordingNow ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: recordingNow
                ? AppColors.error
                : AppColors.tangerine,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
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
