import 'package:flutter/material.dart';

import '../../../../core/network/network.dart';
import '../../../../design_system/design_system.dart';
import '../../application/voice_answer_playback_controller.dart';
import '../../domain/models/voice_answer_audio.dart';

/// 보호자 Activity Detail에서 저장된 아동 음성을 재생·정지한다.
final class VoiceAnswerPlaybackControl extends StatelessWidget {
  const VoiceAnswerPlaybackControl({
    required this.controller,
    required this.messageId,
    super.key,
  });

  final VoiceAnswerPlaybackController controller;
  final int messageId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final active = controller.activeMessageId == messageId;
      final status = active
          ? controller.status
          : VoiceAnswerPlaybackStatus.idle;
      return switch (status) {
        VoiceAnswerPlaybackStatus.loading => _status(
          key: ValueKey('voice-answer-loading-$messageId'),
          message: '음성을 불러오고 있어요.',
          progress: true,
        ),
        VoiceAnswerPlaybackStatus.playing => _button(
          key: ValueKey('voice-answer-stop-$messageId'),
          semanticsLabel: '아이 음성 답변 재생 정지',
          icon: Icons.stop_circle_outlined,
          label: '재생 정지',
          onPressed: controller.stop,
        ),
        VoiceAnswerPlaybackStatus.failure => _failure(),
        VoiceAnswerPlaybackStatus.stopped => _ready(
          message: '재생을 멈췄어요.',
          label: '다시 재생',
        ),
        VoiceAnswerPlaybackStatus.completed => _ready(
          message: '재생이 끝났어요.',
          label: '다시 재생',
        ),
        VoiceAnswerPlaybackStatus.idle => _button(
          key: ValueKey('voice-answer-play-$messageId'),
          semanticsLabel: '아이 음성 답변 재생',
          icon: Icons.play_circle_outline,
          label: '음성 재생',
          onPressed: () => controller.play(messageId),
        ),
      };
    },
  );

  Widget _ready({required String message, required String label}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _status(
        key: ValueKey('voice-answer-status-$messageId'),
        message: message,
      ),
      const SizedBox(height: AppSpacing.xxs),
      _button(
        key: ValueKey('voice-answer-replay-$messageId'),
        semanticsLabel: '아이 음성 답변 다시 재생',
        icon: Icons.replay_rounded,
        label: label,
        onPressed: () => controller.play(messageId),
      ),
    ],
  );

  Widget _failure() {
    final failure = controller.error;
    final validationMessage = switch (failure) {
      VoiceAnswerPlaybackValidationFailure(:final reason) => switch (reason) {
        VoiceAnswerPlaybackValidationReason.invalidMessageId =>
          '음성 정보가 올바르지 않아요.',
        VoiceAnswerPlaybackValidationReason.emptyAudio => '녹음한 음성이 비어 있어요.',
        VoiceAnswerPlaybackValidationReason.tooLarge =>
          '이 음성은 크기가 너무 커서 재생할 수 없어요.',
        VoiceAnswerPlaybackValidationReason.unsupportedMimeType =>
          '지원하지 않는 음성 형식이에요.',
        VoiceAnswerPlaybackValidationReason.invalidResponse =>
          '음성 응답 형식이 올바르지 않아요.',
      },
      _ => null,
    };
    final presentation = ApiFailurePresentation.of(controller.error);
    final message =
        validationMessage ??
        switch (presentation.kind) {
          ApiFailureKind.notFound => '녹음한 음성을 찾을 수 없어요.',
          ApiFailureKind.forbidden => '이 음성을 재생할 권한이 없어요.',
          ApiFailureKind.unauthorized => '로그인이 만료되어 음성을 재생할 수 없어요.',
          _ => '음성을 재생하지 못했어요. ${presentation.message}',
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _status(
          key: ValueKey('voice-answer-failure-$messageId'),
          message: message,
          error: true,
        ),
        if (controller.canRetry) ...[
          const SizedBox(height: AppSpacing.xxs),
          _button(
            key: ValueKey('voice-answer-retry-$messageId'),
            semanticsLabel: '아이 음성 답변 다시 시도',
            icon: Icons.refresh_rounded,
            label: '다시 시도',
            onPressed: () => controller.play(messageId),
          ),
        ],
      ],
    );
  }

  Widget _status({
    required Key key,
    required String message,
    bool progress = false,
    bool error = false,
  }) => Semantics(
    key: key,
    liveRegion: true,
    label: message,
    child: ExcludeSemantics(
      child: Row(
        children: [
          if (progress) ...[
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: error ? AppColors.error : AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _button({
    required Key key,
    required String semanticsLabel,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => Semantics(
    button: true,
    label: semanticsLabel,
    child: ExcludeSemantics(
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.leaf,
            minimumSize: const Size(48, 48),
          ),
        ),
      ),
    ),
  );
}
