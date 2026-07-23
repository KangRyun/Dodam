import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/models/ai_question.dart';

// 질문 도착 시 캔버스 위에 표시하는 캐릭터와 말풍선
final class AiQuestionBubbleOverlay extends StatelessWidget {
  const AiQuestionBubbleOverlay({
    required this.question,
    required this.visible,
    required this.selectedOptionId,
    required this.onOptionSelected,
    required this.showResponseActions,
    required this.onSkip,
    super.key,
  });

  static const _characterAsset = 'assets/characters/dodami.png';

  final AiQuestion? question;
  final bool visible;
  final int? selectedOptionId;
  final ValueChanged<int> onOptionSelected;
  final bool showResponseActions;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final currentQuestion = question;
    if (currentQuestion == null) return const SizedBox.shrink();

    return Positioned(
      right: AppSpacing.lg,
      bottom: AppSpacing.lg,
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
                label: '도다미 질문. ${currentQuestion.text}',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IgnorePointer(
                        child: _QuestionBubble(text: currentQuestion.text),
                      ),
                      if (showResponseActions) ...[
                        const SizedBox(height: AppSpacing.sm),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _ResponseActions(
                            key: ValueKey(
                              'ai-question-actions-${currentQuestion.messageId}',
                            ),
                            options: currentQuestion.options,
                            selectedOptionId: selectedOptionId,
                            onSelected: onOptionSelected,
                            onSkip: onSkip,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      const IgnorePointer(child: _DodamiCharacter()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ResponseActions extends StatelessWidget {
  const _ResponseActions({
    required this.options,
    required this.selectedOptionId,
    required this.onSelected,
    required this.onSkip,
    super.key,
  });

  final List<AiQuestionOption> options;
  final int? selectedOptionId;
  final ValueChanged<int> onSelected;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (options.isNotEmpty)
        _QuestionOptions(
          options: options,
          selectedOptionId: selectedOptionId,
          onSelected: onSelected,
        ),
      const SizedBox(height: AppSpacing.xs),
      TextButton.icon(
        key: const ValueKey('ai-question-skip'),
        onPressed: onSkip,
        icon: const Icon(Icons.sentiment_neutral_rounded),
        label: const Text('말 안 할래'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.inkMuted,
          backgroundColor: AppColors.surface,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: AppColors.outlineStrong),
          ),
        ),
      ),
    ],
  );
}

final class _QuestionOptions extends StatelessWidget {
  const _QuestionOptions({
    required this.options,
    required this.selectedOptionId,
    required this.onSelected,
  });

  final List<AiQuestionOption> options;
  final int? selectedOptionId;
  final ValueChanged<int> onSelected;

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
                onTap: () => onSelected(option.optionId),
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
  final VoidCallback onTap;

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
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('ai-question-bubble'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
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
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
    ),
  );
}

final class _DodamiCharacter extends StatelessWidget {
  const _DodamiCharacter();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('dodami-character'),
    width: 124,
    height: 124,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.surface,
      border: Border.all(color: AppColors.tangerineSoft, width: 4),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: ClipOval(
      child: Transform.scale(
        scale: 1.35,
        child: Image.asset(
          AiQuestionBubbleOverlay._characterAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}
