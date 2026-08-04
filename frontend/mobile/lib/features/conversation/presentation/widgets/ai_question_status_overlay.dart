import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/network/network.dart';
import '../../../../design_system/design_system.dart';
import '../../application/ai_question_controller.dart';
import '../../application/ai_question_display_controller.dart';
import '../../application/conversation_retry_policy.dart';

enum AiOverlayPhase { idle, preparing, question, failure }

final class AiQuestionStatusOverlay extends StatefulWidget {
  const AiQuestionStatusOverlay({
    required this.controller,
    required this.displayController,
    required this.conversationStartInFlight,
    required this.conversationStartError,
    required this.onRetryConversationStart,
    required this.onRetryQuestion,
    this.maxPreparingDuration = const Duration(milliseconds: 2500),
    super.key,
  });

  final AiQuestionController? controller;
  final AiQuestionDisplayController displayController;
  final bool conversationStartInFlight;
  final Object? conversationStartError;
  final VoidCallback onRetryConversationStart;
  final VoidCallback onRetryQuestion;
  final Duration maxPreparingDuration;

  @override
  State<AiQuestionStatusOverlay> createState() =>
      _AiQuestionStatusOverlayState();
}

final class _AiQuestionStatusOverlayState
    extends State<AiQuestionStatusOverlay> {
  Timer? _preparingTimer;
  bool _preparingExpired = false;
  int _preparingGeneration = 0;

  bool get _isPreparing =>
      widget.conversationStartInFlight || widget.controller?.isLoading == true;
  bool get _shouldPresentPreparing =>
      _isPreparing &&
      widget.conversationStartError == null &&
      widget.controller?.status != AiQuestionStatus.failure &&
      !widget.displayController.hasUnresolvedQuestion;

  AiOverlayPhase get _phase {
    if (widget.conversationStartError != null ||
        widget.controller?.status == AiQuestionStatus.failure) {
      return AiOverlayPhase.failure;
    }
    if (widget.displayController.hasUnresolvedQuestion) {
      return AiOverlayPhase.question;
    }
    if (_isPreparing && !_preparingExpired) return AiOverlayPhase.preparing;
    return AiOverlayPhase.idle;
  }

  Object? get _failure =>
      widget.conversationStartError ?? widget.controller?.error;

  bool get _canRetryFailure {
    if (widget.conversationStartError != null) {
      return canRetryConversationRequest(
        widget.conversationStartError,
        endpoint: ConversationRequestEndpoint.conversationStart,
      );
    }
    return widget.controller?.canRetry == true;
  }

  VoidCallback get _retryFailure => widget.conversationStartError != null
      ? widget.onRetryConversationStart
      : widget.onRetryQuestion;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleSourceChanged);
    widget.displayController.addListener(_handleSourceChanged);
    _restartPreparingPresentation();
  }

  @override
  void didUpdateWidget(covariant AiQuestionStatusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleSourceChanged);
      widget.controller?.addListener(_handleSourceChanged);
    }
    if (oldWidget.displayController != widget.displayController) {
      oldWidget.displayController.removeListener(_handleSourceChanged);
      widget.displayController.addListener(_handleSourceChanged);
    }
    final sourceChanged =
        oldWidget.controller != widget.controller ||
        oldWidget.displayController != widget.displayController ||
        oldWidget.conversationStartInFlight !=
            widget.conversationStartInFlight ||
        oldWidget.conversationStartError != widget.conversationStartError ||
        oldWidget.maxPreparingDuration != widget.maxPreparingDuration;
    if (sourceChanged) _restartPreparingPresentation();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleSourceChanged);
    widget.displayController.removeListener(_handleSourceChanged);
    _cancelPreparingTimer();
    super.dispose();
  }

  void _handleSourceChanged() {
    if (!mounted) return;
    if (_shouldPresentPreparing) {
      if (_preparingTimer == null) _restartPreparingPresentation();
    } else {
      _cancelPreparingTimer();
      _preparingExpired = false;
    }
    setState(() {});
  }

  void _restartPreparingPresentation() {
    _cancelPreparingTimer();
    _preparingExpired = false;
    if (!_shouldPresentPreparing) return;
    final generation = _preparingGeneration;
    _preparingTimer = Timer(widget.maxPreparingDuration, () {
      if (!mounted || generation != _preparingGeneration) return;
      _preparingTimer = null;
      setState(() => _preparingExpired = true);
    });
  }

  void _cancelPreparingTimer() {
    _preparingGeneration += 1;
    _preparingTimer?.cancel();
    _preparingTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    final canRetry = phase == AiOverlayPhase.failure && _canRetryFailure;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Positioned.fill(
      child: IgnorePointer(
        key: const ValueKey('ai-question-status-hit-test'),
        ignoring: !canRetry,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 280 &&
                constraints.maxWidth > constraints.maxHeight;
            final content = switch (phase) {
              AiOverlayPhase.preparing => _PreparingStatus(compact: compact),
              AiOverlayPhase.failure => _FailureStatus(
                error: _failure,
                onRetry: canRetry ? _retryFailure : null,
                compact: compact,
              ),
              AiOverlayPhase.idle ||
              AiOverlayPhase.question => const SizedBox.shrink(),
            };
            final presentedContent = switch (phase) {
              AiOverlayPhase.preparing ||
              AiOverlayPhase.failure => TweenAnimationBuilder<double>(
                key: ValueKey('ai-question-status-${phase.name}-entrance'),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0, end: 1),
                child: content,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - value)),
                    child: child,
                  ),
                ),
              ),
              AiOverlayPhase.idle || AiOverlayPhase.question => content,
            };

            return Padding(
              padding: EdgeInsets.all(compact ? AppSpacing.xs : AppSpacing.lg),
              child: Align(
                alignment: Alignment.bottomRight,
                child: presentedContent,
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _PreparingStatus extends StatelessWidget {
  const _PreparingStatus({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('ai-question-preparing'),
    container: true,
    liveRegion: true,
    label: '새 질문을 생각하고 있어요. 그림을 보며 잠시만 기다려 주세요.',
    child: ExcludeSemantics(
      child: compact
          ? Row(
              key: const ValueKey('ai-question-status-content'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Flexible(
                  child: _StatusBubble(
                    title: '새 질문을 생각하고 있어요',
                    description: '그림을 보며 잠시만 기다려 주세요.',
                    compact: true,
                  ),
                ),
                SizedBox(width: AppSpacing.xs),
                _StatusCharacter(size: 72),
              ],
            )
          : const Column(
              key: ValueKey('ai-question-status-content'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBubble(
                  title: '새 질문을 생각하고 있어요',
                  description: '그림을 보며 잠시만 기다려 주세요.',
                ),
                SizedBox(height: AppSpacing.sm),
                _StatusCharacter(),
              ],
            ),
    ),
  );
}

final class _FailureStatus extends StatelessWidget {
  const _FailureStatus({
    required this.error,
    required this.onRetry,
    required this.compact,
  });

  final Object? error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final description = ApiFailurePresentation.of(
      error,
      childFriendly: true,
    ).message;
    return Semantics(
      key: const ValueKey('ai-question-error'),
      container: true,
      liveRegion: true,
      label: '질문을 불러오지 못했어요. $description',
      child: compact
          ? Row(
              key: const ValueKey('ai-question-status-content'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: _StatusBubble(
                        title: '질문을 불러오지 못했어요',
                        description: description,
                        accent: AppColors.error,
                        compact: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onRetry case final retry?) ...[
                      _RetryButton(onPressed: retry),
                      const SizedBox(height: AppSpacing.xxs),
                    ],
                    const IgnorePointer(child: _StatusCharacter(size: 72)),
                  ],
                ),
              ],
            )
          : Column(
              key: const ValueKey('ai-question-status-content'),
              mainAxisSize: MainAxisSize.min,
              children: [
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: _StatusBubble(
                      title: '질문을 불러오지 못했어요',
                      description: description,
                      accent: AppColors.error,
                    ),
                  ),
                ),
                if (onRetry case final retry?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _RetryButton(onPressed: retry),
                ],
                const SizedBox(height: AppSpacing.sm),
                const IgnorePointer(child: _StatusCharacter()),
              ],
            ),
    );
  }
}

final class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('ai-question-retry'),
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: AppColors.error,
      backgroundColor: AppColors.surface,
    ),
    icon: const Icon(Icons.refresh_rounded),
    label: const Text('다시 불러오기'),
  );
}

final class _StatusCharacter extends StatelessWidget {
  const _StatusCharacter({this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('ai-question-status-character'),
    width: size,
    height: size,
    child: Image.asset(
      'assets/characters/dodam_drawing.png',
      excludeFromSemantics: true,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    ),
  );
}

final class _StatusBubble extends StatelessWidget {
  const _StatusBubble({
    required this.title,
    required this.description,
    this.accent = AppColors.tangerineSoft,
    this.compact = false,
  });

  final String title;
  final String description;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        right: 48,
        bottom: -5,
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: accent, width: 2),
            ),
          ),
        ),
      ),
      Container(
        constraints: BoxConstraints(maxWidth: compact ? 620 : 300),
        padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: accent, width: 2),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: compact ? 13 : 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
