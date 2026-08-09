import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../child_mode/domain/dodam_costume.dart';
import '../../../child_mode/presentation/widgets/dodam_companion.dart';
import '../../application/conversation_end_controller.dart';
import '../../application/option_answer_submission_controller.dart';
import '../../application/question_skip_controller.dart';
import '../../application/voice_recording_controller.dart';
import '../../application/voice_answer_upload_controller.dart';
import '../../domain/models/ai_question.dart';
import 'voice_recording_control.dart';

const _questionSkipAsset =
    'assets/images/conversation/question_skip_pastel.png';
const _questionStopAsset =
    'assets/images/conversation/question_stop_pastel.png';

// 질문 도착 시 캔버스 위에 표시하는 캐릭터와 말풍선
final class AiQuestionBubbleOverlay extends StatelessWidget {
  const AiQuestionBubbleOverlay({
    required this.question,
    required this.visible,
    required this.selectedOptionId,
    required this.onOptionSelected,
    required this.showResponseActions,
    required this.submissionStatus,
    required this.skipStatus,
    required this.onSkip,
    required this.endStatus,
    required this.onEnd,
    this.voiceRecordingController,
    this.voiceAnswerUploadStatus = VoiceAnswerUploadStatus.idle,
    this.onRetryVoiceAnswerUpload,
    this.answerRetryable = true,
    this.answerOptionsEnabled = true,
    this.skipRetryable = true,
    this.endRetryable = true,
    this.voiceRetryable = true,
    this.showTtsReplay = false,
    this.onReplayTts,
    this.companion = DodamCostume.base,
    this.compact = false,
    super.key,
  });

  final AiQuestion? question;
  final bool visible;
  final String? selectedOptionId;
  final ValueChanged<String> onOptionSelected;
  final bool showResponseActions;
  final OptionAnswerSubmissionStatus submissionStatus;
  final QuestionSkipStatus skipStatus;
  final VoidCallback onSkip;
  final ConversationEndStatus endStatus;
  final VoidCallback onEnd;
  final VoiceRecordingController? voiceRecordingController;
  final VoiceAnswerUploadStatus voiceAnswerUploadStatus;
  final VoidCallback? onRetryVoiceAnswerUpload;

  /// 실패한 조작을 같은 버튼으로 다시 시도해도 되는지.
  ///
  /// 권한·검증처럼 결과가 달라지지 않는 실패에서는 조작을 잠가, 아이가 같은
  /// 버튼을 반복해 눌러도 아무 일도 일어나지 않는 상황을 만들지 않는다.
  /// 잠기더라도 건너뛰기·대화 그만하기 중 살아 있는 경로로 빠져나갈 수 있다.
  final bool answerRetryable;
  final bool answerOptionsEnabled;
  final bool skipRetryable;
  final bool endRetryable;
  final bool voiceRetryable;

  /// 질문 음성이 끝내 나오지 않아 직접 눌러 들을 수 있게 해야 하는지 (P0-3).
  ///
  /// 서버 TTS → 짧은 재시도 → 기기 음성이 모두 실패한 뒤에만 켠다. 글을 못 읽는 아이에게
  /// 질문이 닿는 마지막 길이라, 다른 조작이 잠겨 있어도 이 버튼은 살려 둔다.
  final bool showTtsReplay;
  final VoidCallback? onReplayTts;

  /// 활동 시작 시 서버 확정 preferredCharacter에서 만든 immutable snapshot.
  final DodamCostume companion;

  /// 좁은 화면용 촘촘한 배치를 쓸지 여부다.
  ///
  /// 담긴 상자의 높이로 스스로 판단하지 않는다. 말풍선은 종이 위로 넘쳐 그려질
  /// 수 있어 상자 높이가 화면 여유와 다르고, 그 차이 때문에 배치가 화면 종류와
  /// 무관하게 뒤집힌 적이 있다. 화면 종류를 아는 쪽에서 넘긴다.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currentQuestion = question;
    if (currentQuestion == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = compact ? AppSpacing.sm : AppSpacing.lg;
          final maxWidth = min(
            compact ? 280.0 : 300.0,
            max(1.0, constraints.maxWidth - inset * 2),
          );
          final maxHeight = max(1.0, constraints.maxHeight - inset * 2);

          return Padding(
            padding: EdgeInsets.all(inset),
            child: Align(
              alignment: Alignment.bottomRight,
              child: IgnorePointer(
                ignoring: !visible,
                child: ExcludeSemantics(
                  excluding: !visible,
                  child: AnimatedSlide(
                    offset: visible ? Offset.zero : const Offset(0, 0.12),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Semantics(
                        container: true,
                        liveRegion: true,
                        label: '${companion.label} 질문. ${currentQuestion.text}',
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxWidth,
                            maxHeight: maxHeight,
                          ),
                          child: Scrollbar(
                            child: CustomScrollView(
                              key: const ValueKey('ai-question-overlay-scroll'),
                              primary: false,
                              shrinkWrap: true,
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (compact)
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            IgnorePointer(
                                              child: DodamCompanionAvatar(
                                                companion: companion,
                                                compact: true,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.xs,
                                            ),
                                            Expanded(
                                              child: IgnorePointer(
                                                child: _QuestionBubble(
                                                  text: currentQuestion.text,
                                                  compact: true,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        IgnorePointer(
                                          child: _QuestionBubble(
                                            text: currentQuestion.text,
                                          ),
                                        ),
                                      if (showTtsReplay &&
                                          onReplayTts != null) ...[
                                        const SizedBox(height: AppSpacing.xs),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            key: const ValueKey(
                                              'question-tts-replay',
                                            ),
                                            onPressed: onReplayTts,
                                            icon: const Icon(
                                              Icons.volume_up_rounded,
                                            ),
                                            label: const Text('다시 들려줘'),
                                          ),
                                        ),
                                      ],
                                      if (voiceRecordingController
                                          case final controller?) ...[
                                        const SizedBox(height: AppSpacing.sm),
                                        VoiceRecordingControl(
                                          controller: controller,
                                          enabled:
                                              submissionStatus !=
                                                  OptionAnswerSubmissionStatus
                                                      .submitting &&
                                              skipStatus !=
                                                  QuestionSkipStatus
                                                      .submitting &&
                                              endStatus !=
                                                  ConversationEndStatus
                                                      .submitting &&
                                              (voiceAnswerUploadStatus !=
                                                      VoiceAnswerUploadStatus
                                                          .failure ||
                                                  voiceRetryable),
                                        ),
                                        if (voiceAnswerUploadStatus ==
                                            VoiceAnswerUploadStatus
                                                .uploading) ...[
                                          const SizedBox(height: AppSpacing.xs),
                                          const LinearProgressIndicator(
                                            key: ValueKey(
                                              'voice-answer-uploading',
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          const Text(
                                            '목소리를 보내고 있어요.',
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                        if (voiceAnswerUploadStatus ==
                                            VoiceAnswerUploadStatus
                                                .failure) ...[
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            voiceRetryable
                                                ? '목소리를 보내지 못했어요.'
                                                : '지금은 목소리를 보낼 수 없어요.\n'
                                                      '아래에서 골라서 답해 볼까요?',
                                            key: const ValueKey(
                                              'voice-answer-upload-failure',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: AppColors.error,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          // 다시 보내도 같은 결과인 실패에는 버튼을 만들지 않는다.
                                          if (voiceRetryable)
                                            TextButton(
                                              key: const ValueKey(
                                                'voice-answer-upload-retry',
                                              ),
                                              onPressed:
                                                  onRetryVoiceAnswerUpload,
                                              style: TextButton.styleFrom(
                                                minimumSize: const Size(48, 48),
                                              ),
                                              child: const Text('다시 보내기'),
                                            ),
                                        ],
                                        // 동의 부재는 아이 화면에 어른 문구를 노출하지 않고
                                        // 선택형 답변으로 자연스럽게 유도한다(가드레일 9절).
                                        if (voiceAnswerUploadStatus ==
                                            VoiceAnswerUploadStatus
                                                .consentRequired) ...[
                                          const SizedBox(height: AppSpacing.xs),
                                          const Text(
                                            '목소리로 답하기는 지금 쓸 수 없어요.\n'
                                            '아래에서 골라서 답해 볼까요?',
                                            key: ValueKey(
                                              'voice-answer-consent-required',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: AppColors.inkMuted,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ],
                                      const SizedBox(height: AppSpacing.sm),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        child: _ResponseActions(
                                          key: ValueKey(
                                            'ai-question-actions-'
                                            '${currentQuestion.messageId}',
                                          ),
                                          showOptions: showResponseActions,
                                          options: currentQuestion.options,
                                          selectedOptionId: selectedOptionId,
                                          onSelected: onOptionSelected,
                                          onSkip: onSkip,
                                          submissionStatus: submissionStatus,
                                          skipStatus: skipStatus,
                                          endStatus: endStatus,
                                          onEnd: onEnd,
                                          answerRetryable: answerRetryable,
                                          answerOptionsEnabled:
                                              answerOptionsEnabled,
                                          skipRetryable: skipRetryable,
                                          endRetryable: endRetryable,
                                          compact: compact,
                                        ),
                                      ),
                                      if (!compact) ...[
                                        const SizedBox(height: AppSpacing.xs),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: IgnorePointer(
                                            child: DodamCompanionAvatar(
                                              companion: companion,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 실패 안내 한 줄. 색만으로 구분하지 않도록 문구를 항상 함께 낭독한다.
final class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

final class _ResponseActions extends StatelessWidget {
  const _ResponseActions({
    required this.showOptions,
    required this.options,
    required this.selectedOptionId,
    required this.onSelected,
    required this.onSkip,
    required this.submissionStatus,
    required this.skipStatus,
    required this.endStatus,
    required this.onEnd,
    required this.answerRetryable,
    required this.answerOptionsEnabled,
    required this.skipRetryable,
    required this.endRetryable,
    required this.compact,
    super.key,
  });

  final bool showOptions;
  final List<AiQuestionOption> options;
  final String? selectedOptionId;
  final ValueChanged<String> onSelected;
  final VoidCallback onSkip;
  final OptionAnswerSubmissionStatus submissionStatus;
  final QuestionSkipStatus skipStatus;
  final ConversationEndStatus endStatus;
  final VoidCallback onEnd;
  final bool answerRetryable;
  final bool answerOptionsEnabled;
  final bool skipRetryable;
  final bool endRetryable;
  final bool compact;

  /// 어느 요청이든 전송 중이면 다른 조작을 막는다.
  bool get _busy =>
      submissionStatus == OptionAnswerSubmissionStatus.submitting ||
      skipStatus == QuestionSkipStatus.submitting ||
      endStatus == ConversationEndStatus.submitting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showOptions && options.isNotEmpty)
          _QuestionOptions(
            options: options,
            selectedOptionId: selectedOptionId,
            onSelected: onSelected,
            enabled: !_busy && answerOptionsEnabled,
          ),
        if (submissionStatus == OptionAnswerSubmissionStatus.submitting) ...[
          const SizedBox(height: AppSpacing.xs),
          const LinearProgressIndicator(
            key: ValueKey('ai-question-answer-submitting'),
          ),
        ],
        // 다시 눌러 볼 수 있는 실패와 그렇지 않은 실패의 안내를 구분한다.
        // 어느 쪽도 내부 status·errorCode를 드러내지 않는다.
        if (submissionStatus == OptionAnswerSubmissionStatus.failure)
          _FailureNotice(
            key: ValueKey('ai-question-answer-failure'),
            message: answerRetryable
                ? '답을 보내지 못했어요. 다시 눌러 주세요.'
                : '지금은 이 답을 보낼 수 없어요. 다른 방법으로 해 볼까요?',
          ),
        if (skipStatus == QuestionSkipStatus.failure)
          _FailureNotice(
            key: ValueKey('ai-question-skip-failure'),
            message: skipRetryable
                ? '계속 그리기로 돌아가지 못했어요. 다시 눌러 주세요.'
                : '지금은 넘어갈 수 없어요. 답을 골라 볼까요?',
          ),
        if (endStatus == ConversationEndStatus.failure)
          _FailureNotice(
            key: ValueKey('ai-conversation-end-failure'),
            message: endRetryable
                ? '대화를 끝내지 못했어요. 다시 시도해 주세요.'
                : '지금은 대화를 끝낼 수 없어요. 조금 더 이야기해 볼까요?',
          ),
        const SizedBox(height: AppSpacing.sm),
        _QuestionActionCard(
          buttonKey: const ValueKey('ai-question-skip'),
          semanticsLabel: skipStatus == QuestionSkipStatus.submitting
              ? '현재 질문 건너뛰는 중'
              : '현재 질문 건너뛰기',
          label: skipStatus == QuestionSkipStatus.submitting
              ? '계속 그리기로 돌아가는 중'
              : '이 질문 건너뛰기',
          assetPath: _questionSkipAsset,
          illustrationKey: const ValueKey('ai-question-skip-illustration'),
          compact: compact,
          loading: skipStatus == QuestionSkipStatus.submitting,
          backgroundColor: const Color(0xFFFAF7FF),
          pressedColor: const Color(0xFFEDE5FA),
          borderColor: const Color(0xFFD8C9B5),
          foregroundColor: const Color(0xFF4E3F62),
          onPressed: _busy || !skipRetryable ? null : onSkip,
        ),
        const SizedBox(height: AppSpacing.sm),
        _QuestionActionCard(
          buttonKey: const ValueKey('ai-conversation-end'),
          semanticsLabel: endStatus == ConversationEndStatus.submitting
              ? 'AI 질문 마무리하는 중'
              : 'AI 질문 그만 받기',
          label: endStatus == ConversationEndStatus.submitting
              ? '대화를 마무리하는 중'
              : '질문 그만 받기',
          assetPath: _questionStopAsset,
          illustrationKey: const ValueKey('ai-question-stop-illustration'),
          compact: compact,
          loading: endStatus == ConversationEndStatus.submitting,
          backgroundColor: const Color(0xFFFFF6F0),
          pressedColor: const Color(0xFFFBE2D3),
          borderColor: const Color(0xFFE2BEA4),
          foregroundColor: const Color(0xFF5A4035),
          onPressed: _busy || !endRetryable ? null : onEnd,
        ),
      ],
    );
  }
}

final class _QuestionActionCard extends StatelessWidget {
  const _QuestionActionCard({
    required this.buttonKey,
    required this.semanticsLabel,
    required this.label,
    required this.assetPath,
    required this.illustrationKey,
    required this.compact,
    required this.loading,
    required this.backgroundColor,
    required this.pressedColor,
    required this.borderColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final Key buttonKey;
  final String semanticsLabel;
  final String label;
  final String assetPath;
  final Key illustrationKey;
  final bool compact;
  final bool loading;
  final Color backgroundColor;
  final Color pressedColor;
  final Color borderColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 26.0 : 30.0;
    final enabled = onPressed != null && !loading;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: enabled ? borderColor : AppColors.outline),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: TextButton(
        key: buttonKey,
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          disabledForegroundColor: AppColors.onDisabled,
          backgroundColor: backgroundColor,
          disabledBackgroundColor: const Color(0xFFF3EFE8),
          minimumSize: const Size.fromHeight(56),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.sm : AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          shape: shape,
        ).copyWith(overlayColor: WidgetStatePropertyAll(pressedColor)),
        child: Row(
          children: [
            if (loading)
              SizedBox.square(
                dimension: iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: foregroundColor,
                ),
              )
            else
              ExcludeSemantics(
                child: Image.asset(
                  assetPath,
                  key: illustrationKey,
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
              ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: enabled ? foregroundColor : AppColors.onDisabled,
                  fontSize: compact ? 14 : 15,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _QuestionOptions extends StatelessWidget {
  const _QuestionOptions({
    required this.options,
    required this.selectedOptionId,
    required this.onSelected,
    required this.enabled,
  });

  final List<AiQuestionOption> options;
  final String? selectedOptionId;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final optionWidth = (constraints.maxWidth - AppSpacing.xs) / 2;
      return Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final option in options)
            SizedBox(
              width: optionWidth,
              child: _QuestionOptionButton(
                option: option,
                selected: selectedOptionId == option.optionId,
                onTap: enabled ? () => onSelected(option.optionId) : null,
              ),
            ),
        ],
      );
    },
  );
}

final class _QuestionOptionButton extends StatelessWidget {
  const _QuestionOptionButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AiQuestionOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: option.label,
    child: Material(
      color: selected ? AppColors.tangerineSoft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: selected ? AppColors.tangerine : AppColors.outlineStrong,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey('ai-question-option-${option.optionId}'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (option.emoji case final emoji?) ...[
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    option.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: AppColors.tangerine,
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

final class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('ai-question-bubble'),
    padding: EdgeInsets.symmetric(
      horizontal: compact ? AppSpacing.sm : AppSpacing.lg,
      vertical: compact ? AppSpacing.xs : AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.tangerine, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.ink,
        fontSize: compact ? 16 : 19,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
    ),
  );
}
