import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/network/api_failure_presentation.dart';
import '../../../../design_system/design_system.dart';
import '../../../drawing/data/dto/drawing_dtos.dart';

@immutable
final class EmotionChoicePresentation {
  const EmotionChoicePresentation({
    required this.emotion,
    required this.label,
    required this.assetPath,
    required this.accent,
    required this.softBackground,
    required this.canvasBackground,
    required this.response,
  });

  final DrawingEmotionType emotion;
  final String label;
  final String assetPath;
  final Color accent;
  final Color softBackground;
  final Color canvasBackground;
  final String response;
}

const emotionChoicePresentations = <EmotionChoicePresentation>[
  EmotionChoicePresentation(
    emotion: DrawingEmotionType.scared,
    label: '불안',
    assetPath: 'assets/characters/emotions/dodam_emotion_anxious.png',
    accent: Color(0xFF765EAD),
    softBackground: Color(0xFFF0EBFA),
    canvasBackground: Color(0xFFE9E1F5),
    response: '걱정되는 마음을 골랐구나. 도담이가 함께 있을게.',
  ),
  EmotionChoicePresentation(
    emotion: DrawingEmotionType.angry,
    label: '화남',
    assetPath: 'assets/characters/emotions/dodam_emotion_angry.png',
    accent: Color(0xFFC34F35),
    softBackground: Color(0xFFFBE5DE),
    canvasBackground: Color(0xFFF4DDD5),
    response: '화난 마음을 골랐구나. 그런 마음도 괜찮아.',
  ),
  EmotionChoicePresentation(
    emotion: DrawingEmotionType.sad,
    label: '슬픔',
    assetPath: 'assets/characters/emotions/dodam_emotion_sad.png',
    accent: Color(0xFF3E77B2),
    softBackground: Color(0xFFE5F0FA),
    canvasBackground: Color(0xFFDCEAF7),
    response: '슬픈 마음을 골랐구나. 도담이가 잘 기억해 둘게.',
  ),
  EmotionChoicePresentation(
    emotion: DrawingEmotionType.calm,
    label: '편안',
    assetPath: 'assets/characters/emotions/dodam_emotion_calm.png',
    accent: Color(0xFF3F7448),
    softBackground: Color(0xFFE7F2E5),
    canvasBackground: Color(0xFFDFEFDD),
    response: '편안한 마음을 골랐구나.',
  ),
  EmotionChoicePresentation(
    emotion: DrawingEmotionType.happy,
    label: '기쁨',
    assetPath: 'assets/characters/emotions/dodam_emotion_joy.png',
    accent: Color(0xFF925E00),
    softBackground: Color(0xFFFCF0C7),
    canvasBackground: Color(0xFFF7E6AD),
    response: '기쁜 마음을 골랐구나.',
  ),
];

EmotionChoicePresentation emotionPresentationOf(DrawingEmotionType emotion) =>
    emotionChoicePresentations.firstWhere(
      (presentation) => presentation.emotion == emotion,
    );

Future<bool?> showEmotionSkipConfirmation(BuildContext context) =>
    showDialog<bool>(
      context: context,
      requestFocus: true,
      builder: (context) => const _EmotionSkipConfirmationDialog(),
    );

class EmotionSelectionHeader extends StatelessWidget {
  const EmotionSelectionHeader({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('오늘 그림, 다 그렸어!', style: AppTypography.label),
      SizedBox(height: AppSpacing.xxs),
      Text('그림을 그리고 나니, 지금 마음은 어때?', style: AppTypography.titleLg),
      SizedBox(height: AppSpacing.xs),
      Text('지금 마음과 가장 비슷한 표정을 하나 골라줘.', style: AppTypography.bodySm),
    ],
  );
}

class CompletedDrawingPreview extends StatelessWidget {
  const CompletedDrawingPreview({
    required this.completedDrawingImage,
    required this.height,
    super.key,
  });

  final BinaryUploadDto? completedDrawingImage;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bytes = completedDrawingImage?.bytes;
    final imageBytes = bytes == null || bytes.isEmpty
        ? null
        : bytes is Uint8List
        ? bytes
        : Uint8List.fromList(bytes);
    return Semantics(
      image: true,
      label: '내가 완성한 그림',
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('emotion-drawing-preview'),
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEF8),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outlineStrong),
            boxShadow: const [
              BoxShadow(
                color: Color(0x16785528),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: imageBytes == null
                ? const _CompletedDrawingUnavailable()
                : Image.memory(
                    imageBytes,
                    key: const ValueKey('emotion-drawing-preview-image'),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const _CompletedDrawingUnavailable(),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CompletedDrawingUnavailable extends StatelessWidget {
  const _CompletedDrawingUnavailable();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.canvas,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          '완성한 그림을 불러오지 못했어요.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(color: AppColors.inkMuted),
        ),
      ),
    ),
  );
}

class EmotionChoiceCard extends StatelessWidget {
  const EmotionChoiceCard({
    required this.presentation,
    required this.isSelected,
    required this.isDimmed,
    required this.onTap,
    this.focusNode,
    super.key,
  });

  final EmotionChoicePresentation presentation;
  final bool isSelected;
  final bool isDimmed;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    selected: isSelected,
    label: isSelected
        ? '${presentation.label}, 선택됨'
        : '${presentation.label} 감정 선택',
    child: ExcludeSemantics(
      child: AnimatedOpacity(
        key: ValueKey('emotion-opacity-${presentation.emotion.apiValue}'),
        opacity: isDimmed ? 0.52 : 1,
        duration: const Duration(milliseconds: 180),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: isSelected ? -4 : 0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, offset, child) =>
              Transform.translate(offset: Offset(0, offset), child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected
                  ? presentation.softBackground
                  : const Color(0xFFFFFCF4),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isSelected
                    ? presentation.accent
                    : const Color(0xFFECE3D1),
                width: isSelected ? 3 : 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: presentation.accent.withValues(alpha: 0.22),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : const [],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                focusNode: focusNode,
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final imageHeight = (constraints.maxWidth * 0.72)
                                  .clamp(82.0, 132.0);
                              return SizedBox(
                                width: double.infinity,
                                height: imageHeight,
                                child: Image.asset(
                                  presentation.assetPath,
                                  key: ValueKey(
                                    'emotion-image-${presentation.emotion.apiValue}',
                                  ),
                                  fit: BoxFit.contain,
                                  excludeFromSemantics: true,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            presentation.label,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyStrong,
                          ),
                        ],
                      ),
                      if (isSelected)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.check_circle_rounded,
                            key: ValueKey(
                              'emotion-check-${presentation.emotion.apiValue}',
                            ),
                            color: presentation.accent,
                            size: 28,
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
  );
}

class EmotionConfirmationPanel extends StatelessWidget {
  const EmotionConfirmationPanel({
    required this.presentation,
    required this.isSubmitting,
    required this.canConfirm,
    required this.onConfirm,
    this.failure,
    super.key,
  });

  final EmotionChoicePresentation presentation;
  final bool isSubmitting;
  final bool canConfirm;
  final VoidCallback onConfirm;
  final ApiFailurePresentation? failure;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('emotion-confirmation-panel'),
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: presentation.softBackground, width: 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: '${presentation.response} 이 마음이 지금 마음과 가장 비슷해?',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: presentation.softBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    presentation.assetPath,
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      presentation.response,
                      style: AppTypography.bodyStrong,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          '이 마음이 지금 마음과 가장 비슷해?',
          textAlign: TextAlign.center,
          style: AppTypography.titleMd,
        ),
        if (failure case final failure?) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            label: failure.message,
            child: ExcludeSemantics(
              child: Container(
                key: const ValueKey('emotion-submit-error'),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  failure.canRetry
                      ? '${failure.message} 고른 마음은 그대로 있어요.'
                      : failure.message,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(color: AppColors.error),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _EmotionActionButton(
          key: const ValueKey('emotion-submit'),
          label: isSubmitting ? '마음을 저장하고 있어요' : '응! 맞아!',
          backgroundColor: presentation.accent,
          foregroundColor: Colors.white,
          isLoading: isSubmitting,
          onPressed: canConfirm ? onConfirm : null,
        ),
      ],
    ),
  );
}

class EmotionSkipButton extends StatelessWidget {
  const EmotionSkipButton({
    required this.onPressed,
    required this.isLoading,
    this.focusNode,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final label = isLoading ? '넘어갈 준비를 하고 있어요' : '지금은 고르지 않을래';
    return Semantics(
      key: ValueKey(
        isLoading
            ? 'emotion-skip-loading-semantics'
            : 'emotion-skip-idle-semantics',
      ),
      button: true,
      enabled: onPressed != null && !isLoading,
      liveRegion: isLoading,
      label: label,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: TextButton(
            focusNode: focusNode,
            onPressed: onPressed == null || isLoading ? null : onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.inkMuted,
              disabledForegroundColor: AppColors.onDisabled,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading) ...[
                  const ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyStrong,
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

class EmotionSkipFailureMessage extends StatelessWidget {
  const EmotionSkipFailureMessage({required this.failure, super.key});

  final ApiFailurePresentation failure;

  @override
  Widget build(BuildContext context) {
    final message = failure.canRetry
        ? '${failure.message} 넘어가려던 선택은 그대로 있어요.'
        : failure.message;
    return Semantics(
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('emotion-skip-error'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.errorSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.error),
          ),
        ),
      ),
    );
  }
}

class _EmotionSkipConfirmationDialog extends StatefulWidget {
  const _EmotionSkipConfirmationDialog();

  @override
  State<_EmotionSkipConfirmationDialog> createState() =>
      _EmotionSkipConfirmationDialogState();
}

class _EmotionSkipConfirmationDialogState
    extends State<_EmotionSkipConfirmationDialog> {
  bool _isClosing = false;

  void _finish(bool confirmed) {
    if (_isClosing) return;
    _isClosing = true;
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('emotion-skip-dialog'),
    backgroundColor: AppColors.surface,
    insetPadding: const EdgeInsets.all(AppSpacing.md),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    contentPadding: const EdgeInsets.all(AppSpacing.lg),
    content: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_border_rounded,
              size: 52,
              color: AppColors.tangerine,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '지금은 마음을 고르지 않고 넘어갈까?',
              textAlign: TextAlign.center,
              style: AppTypography.titleLg,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '나중에 그림을 보면서 다시 이야기해도 괜찮아.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Builder(
              builder: (context) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final stackButtons =
                    MediaQuery.sizeOf(context).width < 520 || textScale > 1.3;
                final reconsider = AppButton(
                  key: const ValueKey('emotion-skip-cancel'),
                  label: '다시 생각해볼래',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _finish(false),
                );
                final continueButton = AppButton(
                  key: const ValueKey('emotion-skip-confirm'),
                  label: '응, 넘어갈래',
                  variant: AppButtonVariant.primary,
                  onPressed: () => _finish(true),
                );
                if (stackButtons) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      continueButton,
                      const SizedBox(height: AppSpacing.sm),
                      reconsider,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: reconsider),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: continueButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmotionActionButton extends StatelessWidget {
  const _EmotionActionButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null && !isLoading,
    liveRegion: isLoading,
    label: label,
    child: ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.childButtonHeight,
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onPressed == null || isLoading ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              disabledBackgroundColor: AppColors.disabled,
              disabledForegroundColor: AppColors.onDisabled,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading) ...[
                  ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: foregroundColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTypography.button,
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
