import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/models/ai_question.dart';

// 질문 도착 시 캔버스 위에 표시하는 캐릭터와 말풍선
final class AiQuestionBubbleOverlay extends StatelessWidget {
  const AiQuestionBubbleOverlay({
    required this.question,
    required this.visible,
    super.key,
  });

  static const _characterAsset = 'assets/characters/dodami.png';

  final AiQuestion? question;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final currentQuestion = question;
    if (currentQuestion == null) return const SizedBox.shrink();

    return Positioned(
      right: AppSpacing.lg,
      bottom: AppSpacing.lg,
      child: IgnorePointer(
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
                      _QuestionBubble(text: currentQuestion.text),
                      const SizedBox(height: AppSpacing.xs),
                      const _DodamiCharacter(),
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
